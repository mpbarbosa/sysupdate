#!/usr/bin/env bats
#
# Tests for scripts/setup-hyprland-alternatives.sh
# Covers: stage_prefix / rollback_prefix / commit_prefix (the atomic rebuild)
#         and build_one_dep's "name@ref" dependency pinning.
#
# The script needs root and rebuilds /opt/hyprland, so these tests reach its
# helpers through the SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1 seam (just above its
# --remove section), which defines them and runs nothing. It lives in
# tests/integration/ rather than tests/bash/ because it spawns a shell and
# touches the filesystem, which docs/guides/UNIT_TEST_GUIDE.md excludes from the
# unit suite. Like its neighbour
# tests/integration/launcher_port_reuse.bats, each probe sources the script in
# its own `bash -c` so the script's `set -euo pipefail` never leaks into the BATS
# shell and BATS's own positional args never reach the script's arg parser. DEST
# is repointed at a per-test temp dir, so no root, no network, no /opt access.
#
# Regression context: the rebuild used to `rm -rf /opt/hyprland` before building,
# so a failed build left the machine with NO compositor on disk — that happened
# here on 2026-10-28 (see docs/hyprland-status.md).

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    exec 0</dev/null
    export NO_COLOR=1
    SETUP="$REPO_ROOT/scripts/setup-hyprland-alternatives.sh"
}

# Evaluate <snippet> in a shell that has sourced the setup script's helpers and
# nothing else, with DEST pointing at this test's temp prefix. The prelude
# provides given_installed_build, standing in for a working installed build.
probe() {
    run env \
        SETUP="$SETUP" \
        TEST_DEST="$BATS_TEST_TMPDIR/hyprland" \
        TEST_CFG_LOG="$BATS_TEST_TMPDIR/cmake-configure.log" \
        TEST_KEEP_LOG="$BATS_TEST_TMPDIR/kept-configure.log" \
        TEST_BIN="$BATS_TEST_TMPDIR/bin" \
        SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1 \
        bash -c 'source "$SETUP"
DEST="$TEST_DEST"
given_installed_build() {
    mkdir -p "$DEST/bin" "$DEST/lib"
    echo "GOOD-BUILD" > "$DEST/bin/Hyprland"
    chmod +x "$DEST/bin/Hyprland"
    echo "GOOD-LIB"   > "$DEST/lib/libaquamarine.so.13"
}
given_orphaned_backup() {   # a killed run'"'"'s backup: $1 = pid, $2 = marker
    mkdir -p "$DEST.rollback.$1/bin"
    echo "$2" > "$DEST.rollback.$1/bin/Hyprland"
    chmod +x "$DEST.rollback.$1/bin/Hyprland"
}
given_wreckage() {          # what a killed run leaves at $DEST: libs, no binary
    mkdir -p "$DEST/lib"
    echo "NEW-DEP" > "$DEST/lib/libaquamarine.so.16"
}
show() { echo "$1=$(cat "$2" 2>/dev/null || echo MISSING)"; }
'"$1"
}

# ---------------------------------------------------------------------------
# stage_prefix
# ---------------------------------------------------------------------------

@test "stage_prefix: moves an existing prefix aside and leaves a fresh empty one" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        echo "new_prefix_entries=$(ls -A "$DEST" | wc -l)"
        show backup "$PREFIX_BACKUP/bin/Hyprland"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "new_prefix_entries=0" ]
    [ "${lines[1]}" = "backup=GOOD-BUILD" ]
}

@test "stage_prefix: creates the prefix and records no backup on a first build" {
    probe '
        stage_prefix >/dev/null
        echo "exists=$([ -d "$DEST" ] && echo yes)"
        echo "backup_path=${PREFIX_BACKUP:-none}"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "exists=yes" ]
    [ "${lines[1]}" = "backup_path=none" ]
}

# ---------------------------------------------------------------------------
# rollback_prefix — the guard that stops a failed build removing a compositor
# ---------------------------------------------------------------------------

@test "rollback_prefix: restores the previous build after a failed run" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        echo "HALF-BUILT" > "$DEST/partial-junk"   # what a crashed build leaves
        rollback_prefix 2>/dev/null
        show binary "$DEST/bin/Hyprland"
        show lib "$DEST/lib/libaquamarine.so.13"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "binary=GOOD-BUILD" ]
    [ "${lines[1]}" = "lib=GOOD-LIB" ]
}

@test "rollback_prefix: discards the half-built prefix and its leftovers" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        echo "HALF-BUILT" > "$DEST/partial-junk"
        rollback_prefix 2>/dev/null
        echo "junk=$([ -e "$DEST/partial-junk" ] && echo PRESENT || echo GONE)"
        echo "entries=$(ls -A "$DEST" | sort | tr "\n" ",")"
        echo "rollback_dirs=$(find "$(dirname "$DEST")" -maxdepth 1 -name "$(basename "$DEST").rollback.*" | wc -l)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "junk=GONE" ]
    [ "${lines[1]}" = "entries=bin,lib," ]
    [ "${lines[2]}" = "rollback_dirs=0" ]
}

@test "rollback_prefix: invents no build when there was no previous install" {
    probe '
        stage_prefix >/dev/null
        rollback_prefix 2>/dev/null
        show binary "$DEST/bin/Hyprland"
        echo "prefix_exists=$([ -d "$DEST" ] && echo yes)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "binary=MISSING" ]
    [ "${lines[1]}" = "prefix_exists=yes" ]
}

@test "rollback_prefix: leaves a committed build alone when the EXIT trap fires" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        mkdir -p "$DEST/bin"; echo "NEW-BUILD" > "$DEST/bin/Hyprland"
        commit_prefix >/dev/null
        rollback_prefix 2>/dev/null        # the trap still runs after a commit
        show binary "$DEST/bin/Hyprland"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "binary=NEW-BUILD" ]
}

# ---------------------------------------------------------------------------
# commit_prefix
# ---------------------------------------------------------------------------

@test "commit_prefix: keeps the new build and retires the old to .previous" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        mkdir -p "$DEST/bin"; echo "NEW-BUILD" > "$DEST/bin/Hyprland"
        commit_prefix >/dev/null
        show binary "$DEST/bin/Hyprland"
        show previous "$DEST.previous/bin/Hyprland"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "binary=NEW-BUILD" ]
    [ "${lines[1]}" = "previous=GOOD-BUILD" ]
}

@test "commit_prefix: keeps only one generation across two upgrades" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        mkdir -p "$DEST/bin"; echo "BUILD-2" > "$DEST/bin/Hyprland"
        commit_prefix >/dev/null
        PREFIX_COMMITTED=false                  # a second run of the script
        stage_prefix >/dev/null
        mkdir -p "$DEST/bin"; echo "BUILD-3" > "$DEST/bin/Hyprland"
        commit_prefix >/dev/null
        show binary "$DEST/bin/Hyprland"
        show previous "$DEST.previous/bin/Hyprland"
        echo "generations=$(find "$(dirname "$DEST")" -maxdepth 1 -name "$(basename "$DEST").previous*" | wc -l)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "binary=BUILD-3" ]
    [ "${lines[1]}" = "previous=BUILD-2" ]
    [ "${lines[2]}" = "generations=1" ]
}

# ---------------------------------------------------------------------------
# build_one_dep — "name@ref" pinning
# ---------------------------------------------------------------------------

@test "build_one_dep: a bare name builds that dependency's latest tag" {
    probe '
        build_hypr_dep()          { echo "hyprwm name=$1 ref=${2:-<latest>}"; }
        build_wayland_protocols() { echo "wayland ref=${1:-<latest>}"; }
        build_one_dep "aquamarine"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "hyprwm name=aquamarine ref=<latest>" ]
}

@test "build_one_dep: name@ref pins that dependency to the tag" {
    probe '
        build_hypr_dep()          { echo "hyprwm name=$1 ref=${2:-<latest>}"; }
        build_wayland_protocols() { echo "wayland ref=${1:-<latest>}"; }
        build_one_dep "aquamarine@v0.14.0"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "hyprwm name=aquamarine ref=v0.14.0" ]
}

@test "build_one_dep: hyprland-protocols routes to the plain CMake builder" {
    # Data-only, but a CMake project since v0.8.0 (XMLs + a configured .pc), so
    # build_hypr_dep handles it as-is — verified by building v0.8.0 into a temp
    # prefix, whose .pc satisfied `pkg-config --atleast-version=0.8.0`. It is in
    # DEPS_DEFAULT because apt ships 0.7.0 and Hyprland v0.57.0 needs >= 0.8.0.
    probe '
        build_hypr_dep()          { echo "hyprwm name=$1 ref=${2:-<latest>}"; }
        build_wayland_protocols() { echo "wayland ref=${1:-<latest>}"; }
        build_one_dep "hyprland-protocols"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "hyprwm name=hyprland-protocols ref=<latest>" ]
}

@test "build_one_dep: wayland-protocols routes to its own data-only builder" {
    probe '
        build_hypr_dep()          { echo "hyprwm name=$1 ref=${2:-<latest>}"; }
        build_wayland_protocols() { echo "wayland ref=${1:-<latest>}"; }
        build_one_dep "wayland-protocols@1.49"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "wayland ref=1.49" ]
}

# ---------------------------------------------------------------------------
# cleanup_build / arm_build_rollback
#
# Deliberately NOT a behavioural signal test. One was written and discarded: it
# passed whether or not the INT/TERM traps were armed, so it asserted nothing.
# Two measured reasons it cannot work in a harness:
#   * untrapped SIGTERM already runs the EXIT trap, so there is no difference
#     to detect on that signal;
#   * SIGINT cannot be delivered to a child a non-interactive shell backgrounded
#     — such a child has SIGINT set to ignore (`SigIgn` 0x6 in
#     /proc/<pid>/status) and bash cannot trap a signal ignored on entry.
# What remains testable is that the trap table is armed and actually called,
# which is what this covers. A test that cannot fail is worse than no test.
# ---------------------------------------------------------------------------

@test "cleanup_build: the rollback is armed for EXIT, INT and TERM" {
    run grep -cE "^[[:space:]]+trap (cleanup_build EXIT|'exit 130' INT|'exit 143' TERM)([[:space:]]|\$)" "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "cleanup_build: the build section calls arm_build_rollback" {
    run grep -c "^[[:space:]]*arm_build_rollback\$" "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# derive_cc_for — the C compiler that belongs with a given C++ compiler
#
# This was a hardcoded list naming g++-13 and g++-14, so g++-16 fell through to
# "cc" and silently mixed toolchains. g++-16 is not hypothetical: Hyprland
# v0.57.0 calls std::string::subview, which GCC 15's libstdc++ does not have.
# ---------------------------------------------------------------------------

@test "derive_cc_for: the system g++ pairs with gcc" {
    probe 'derive_cc_for g++'
    [ "$status" -eq 0 ]
    [ "$output" = "gcc" ]
}

@test "derive_cc_for: any versioned g++-N pairs with gcc-N" {
    probe '
        derive_cc_for g++-16
        derive_cc_for g++-14
        derive_cc_for /usr/bin/g++-20
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "gcc-16" ]
    [ "${lines[1]}" = "gcc-14" ]
    [ "${lines[2]}" = "gcc-20" ]
}

@test "derive_cc_for: clang++ pairs with clang, anything else with cc" {
    probe '
        derive_cc_for clang++
        derive_cc_for /opt/llvm/bin/clang++
        derive_cc_for tcc
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "clang" ]
    [ "${lines[1]}" = "clang" ]
    [ "${lines[2]}" = "cc" ]
}

# ---------------------------------------------------------------------------
# explain_configure_failure
#
# A failed CMake configure has two causes needing opposite fixes — an apt -dev
# package that is one install away, and a hypr* library that needs a source
# build of several minutes. The message used to print both and let the reader
# choose. On 2026-10-31 Hyprland v0.57.0 added a `libcanberra` module and that
# message sent the reader toward --with-deps for a missing libcanberra-dev.
#
# Each fixture below is real CMake output, not invented: the libcanberra one is
# from that failed v0.57.0 run, the aquamarine one from a configure of v0.57.0
# against the aquamarine 0.14.0 this machine had installed.
# ---------------------------------------------------------------------------

# Write <stdin> to the log the explain_* probes read.
given_configure_log() {
    cat > "$BATS_TEST_TMPDIR/cmake-configure.log"
}

explain() {
    probe '
        REF=v0.57.0
        CONFIG_LOG_KEEP="$TEST_KEEP_LOG"
        explain_configure_failure "$TEST_CFG_LOG" 2>&1
    '
}

@test "explain_configure_failure: a missing -dev package names the apt package" {
    given_configure_log <<'EOF'
-- Checking for modules 'xkbcommon>=1.11.0;uuid;cairo;pango;lcms2;libcanberra'
--   Package 'libcanberra' not found
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - libcanberra

Call Stack (most recent call first):
  CMakeLists.txt:269 (pkg_check_modules)
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo apt-get install -y libcanberra-dev"* ]]
    [[ "$output" == *"libcanberra"* ]]        # the module itself is named
    [[ "$output" != *"--with-deps"* ]]        # and no source build is suggested
}

@test "explain_configure_failure: a too-old hypr* dep names --with-deps" {
    given_configure_log <<'EOF'
-- Checking for module 'aquamarine>=0.15.0'
--   Package dependency requirement 'aquamarine >= 0.15.0' could not be satisfied.
Package 'aquamarine' has version '0.14.0', required version is '>= 0.15.0'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - aquamarine>=0.15.0

Call Stack (most recent call first):
  CMakeLists.txt:153 (pkg_check_modules)
EOF
    explain
    [ "$status" -eq 0 ]
    # The whole set, not just what failed: see the next two tests.
    [[ "$output" == *"--with-deps=hyprutils,wayland-protocols,aquamarine,hyprgraphics,hyprland-protocols"* ]]
    [[ "$output" != *"apt-get install -y aquamarine"* ]]
}

@test "explain_configure_failure: the --with-deps advice carries the whole dep set" {
    # Hyprland v0.57.0 wants hyprland-protocols >= 0.8.0 and apt ships 0.7.0.
    # Advising --with-deps=hyprland-protocols alone would be wrong: every run
    # rebuilds the prefix from scratch, so that run would drop hyprutils,
    # aquamarine, hyprgraphics and wayland-protocols and fail on one of those.
    given_configure_log <<'EOF'
-- Checking for module 'hyprland-protocols>=0.8.0'
--   Package dependency requirement 'hyprland-protocols >= 0.8.0' could not be satisfied.
Package 'hyprland-protocols' has version '0.7.0', required version is '>= 0.8.0'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - hyprland-protocols>=0.8.0

Call Stack (most recent call first):
  CMakeLists.txt:545 (pkg_check_modules)
EOF
    explain
    [ "$status" -eq 0 ]
    local arg
    arg="$(printf '%s\n' "$output" | grep -o -- '--with-deps=[^ ]*')"
    [ -n "$arg" ]
    for dep in hyprutils wayland-protocols aquamarine hyprgraphics hyprland-protocols; do
        [[ ",${arg#--with-deps=}," == *",$dep,"* ]]
    done
}

@test "explain_configure_failure: the --with-deps advice names each dep once" {
    # aquamarine is already in the default set, so the union must not repeat it.
    given_configure_log <<'EOF'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - aquamarine>=0.15.0

Call Stack (most recent call first):
EOF
    explain
    [ "$status" -eq 0 ]
    local arg
    arg="$(printf '%s\n' "$output" | grep -o -- '--with-deps=[^ ]*')"
    [ "$(printf '%s' "${arg#--with-deps=}" | tr ',' '\n' | grep -c '^aquamarine$')" = "1" ]
}

@test "explain_configure_failure: reports both classes when both are unsatisfied" {
    given_configure_log <<'EOF'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - libcanberra
   - hyprutils>=0.14.3

Call Stack (most recent call first):
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo apt-get install -y libcanberra-dev"* ]]
    [[ "$output" == *"--with-deps=hyprutils"* ]]
}

@test "explain_configure_failure: ignores an optional module the build fell back for" {
    # Hyprland probes udis86 with the same pkg_check_modules call shape and then
    # falls back to a subproject. It is absent from CMake's "required packages
    # were not found" list, which is why that list — and not the bare
    # "Package 'x' not found" lines — is what this function reads.
    given_configure_log <<'EOF'
-- Checking for module 'udis86>=1.7.2'
--   Package 'udis86' not found
-- udis86 dependency not found, falling back to subproject
-- Checking for module 'aquamarine>=0.15.0'
--   Package 'aquamarine' not found
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - aquamarine>=0.15.0

Call Stack (most recent call first):
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"--with-deps="*"aquamarine"* ]]
    [[ "$output" != *"udis86"* ]]
}

@test "explain_configure_failure: an unmapped module gets an apt-file hint" {
    given_configure_log <<'EOF'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - libfoobarbaz>=2.0

Call Stack (most recent call first):
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt-file search libfoobarbaz.pc"* ]]
}

@test "explain_configure_failure: still prints advice when no module is named" {
    # The parse pipelines run under the script's `set -euo pipefail`, where a
    # grep matching nothing fails the pipeline. Without the `|| true` guards
    # errexit killed this function and the run ended with no explanation at all.
    given_configure_log <<'EOF'
/tmp/hyprland-build-x/src/render/Renderer.cpp:91:5: error: no matching function
compilation terminated.
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"CMake configuration failed"* ]]
    [[ "$output" == *"Nothing in the log names an unsatisfied pkg-config module"* ]]
    [[ "$output" == *"--with-deps"* ]]
}

@test "explain_configure_failure: keeps the log where the build cleanup cannot reach it" {
    # The log lives in $build_root, which cleanup_build removes on exit, so the
    # path the message prints has to be a copy outside it.
    given_configure_log <<'EOF'
CMake Error at /usr/share/cmake-4.2/Modules/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:

   - libcanberra

Call Stack (most recent call first):
EOF
    explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"Full configure log: $BATS_TEST_TMPDIR/kept-configure.log"* ]]
    [ -s "$BATS_TEST_TMPDIR/kept-configure.log" ]
}

@test "compile failure: the build output is teed and a copy kept" {
    # Static, like the trap tests above: the compile path lives after the
    # DEFINE_ONLY seam, so there is no way to drive it from a harness. What is
    # checkable is that the wiring is present — before this, a compile failure
    # said "see output above" and cleanup_build then deleted the only log.
    run grep -cE 'tee "\$build_log"$' "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run grep -cE 'cp -f "\$build_log" "\$BUILD_LOG_KEEP"' "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "explain_configure_failure: the configure failure path calls it" {
    run grep -cE '^[[:space:]]+explain_configure_failure "\$cfg_log"$' "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# report_unmanaged_links
#
# update-alternatives will not replace a path that is a real file it does not
# own. It says so in one line among hundreds, and afterwards the group looks
# right — `--display` lists the slave, /etc/alternatives/<name> points at the new
# build — while PATH still finds the old binary. That happened here on
# 2026-10-31: Hyprland and hyprctl were links to a freshly built 0.57.0 while
# /usr/local/bin/hyprpm was still a 2025-12-14 file from an earlier /usr/local
# source install, so the compositor was ten months newer than its plugin manager.
# ---------------------------------------------------------------------------

@test "report_unmanaged_links: a link into /etc/alternatives is ours, and silent" {
    probe '
        mkdir -p "$TEST_BIN"
        ln -s /etc/alternatives/hyprpm "$TEST_BIN/hyprpm"
        rc=0
        report_unmanaged_links "$TEST_BIN/hyprpm" 2>&1 || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "status=0" ]
}

@test "report_unmanaged_links: a regular file is reported with the fix" {
    probe '
        mkdir -p "$TEST_BIN"
        printf "#!/bin/sh\n" > "$TEST_BIN/hyprpm"
        rc=0
        report_unmanaged_links "$TEST_BIN/hyprpm" 2>&1 || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"is a regular file"* ]]
    [[ "$output" == *"--skip-build"* ]]
    [[ "$output" == *"status=1"* ]]
}

@test "report_unmanaged_links: a link pointing somewhere else is reported too" {
    # The shape left behind by an old source install that symlinked its own
    # binary into /usr/local/bin: a link, but not one update-alternatives owns.
    probe '
        mkdir -p "$TEST_BIN"
        ln -s /opt/elsewhere/bin/hyprpm "$TEST_BIN/hyprpm"
        rc=0
        report_unmanaged_links "$TEST_BIN/hyprpm" 2>&1 || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"is a symlink to /opt/elsewhere/bin/hyprpm"* ]]
    [[ "$output" == *"status=1"* ]]
}

@test "report_unmanaged_links: a path that does not exist is not a problem" {
    probe '
        mkdir -p "$TEST_BIN"
        rc=0
        report_unmanaged_links "$TEST_BIN/absent" 2>&1 || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "status=0" ]
}

@test "report_unmanaged_links: among several paths, only the bad one is named" {
    probe '
        mkdir -p "$TEST_BIN"
        ln -s /etc/alternatives/Hyprland "$TEST_BIN/Hyprland"
        ln -s /etc/alternatives/hyprctl  "$TEST_BIN/hyprctl"
        printf "#!/bin/sh\n" > "$TEST_BIN/hyprpm"
        rc=0
        report_unmanaged_links "$TEST_BIN/Hyprland" "$TEST_BIN/hyprctl" "$TEST_BIN/hyprpm" 2>&1 || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"/hyprpm is a regular file"* ]]
    [[ "$output" != *"/hyprctl is"* ]]
    [[ "$output" != *"/Hyprland is"* ]]
    [[ "$output" == *"status=1"* ]]
}

@test "report_unmanaged_links: the registration path calls it" {
    run grep -cE '^report_unmanaged_links "\$LINK" /usr/local/bin/hyprctl /usr/local/bin/hyprpm \|\| true$' "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# cxx_can_build_source / newer_gxx_majors — picking a compiler that can build
#
# On 2026-11-05 Hyprland v0.57.1 failed ~46% in, at src/ipc/s1/S1.cpp, because
# the default compiler was the system g++ (GCC 15, no std::string::subview)
# while g++-16 sat installed and unused. The default now probes instead of
# assuming, and steps UP (never down — see the ABI note in the script).
#
# The probe must both compile AND run: compiling with a newer g++ proves nothing
# if the loader will hand the binary an older libstdc++. The stub compilers below
# make that distinction testable without a real toolchain.
# ---------------------------------------------------------------------------

# A stub `g++` at $TEST_BIN/$1 that compiles anything, writing a "binary" whose
# exit status is $2. Shell-script output is enough: cxx_can_build_source only
# executes it.
stub_cxx_prelude='
given_stub_cxx() {
    local name="$1" exit_status="$2" out=""
    mkdir -p "$TEST_BIN"
    cat > "$TEST_BIN/$name" <<STUB
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do
    case "\$1" in -o) out="\$2"; shift 2 ;; *) shift ;; esac
done
[ -n "\$out" ] || exit 1
printf "#!/bin/sh\nexit %s\n" "$exit_status" > "\$out"
chmod +x "\$out"
STUB
    chmod +x "$TEST_BIN/$name"
}
'

@test "cxx_can_build_source: a compiler that cannot compile the call is rejected" {
    probe "$stub_cxx_prelude"'
        mkdir -p "$TEST_BIN"
        printf "#!/bin/sh\nexit 1\n" > "$TEST_BIN/g++-nope"
        chmod +x "$TEST_BIN/g++-nope"
        rc=0; cxx_can_build_source "$TEST_BIN/g++-nope" || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "status=1" ]
}

@test "cxx_can_build_source: a compiler whose binary will not run is rejected" {
    probe "$stub_cxx_prelude"'
        given_stub_cxx "g++-abi" 1
        rc=0; cxx_can_build_source "$TEST_BIN/g++-abi" || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "status=1" ]
}

@test "cxx_can_build_source: a compiler that compiles and runs is accepted" {
    probe "$stub_cxx_prelude"'
        given_stub_cxx "g++-good" 0
        rc=0; cxx_can_build_source "$TEST_BIN/g++-good" || rc=$?
        echo "status=$rc"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "status=0" ]
}

@test "cxx_can_build_source: leaves no probe files behind in /tmp" {
    probe "$stub_cxx_prelude"'
        given_stub_cxx "g++-good" 0
        before=$(find /tmp -maxdepth 1 -name "hypr-cxx-probe-*" | wc -l)
        cxx_can_build_source "$TEST_BIN/g++-good"
        after=$(find /tmp -maxdepth 1 -name "hypr-cxx-probe-*" | wc -l)
        echo "before=$before after=$after"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"before=0 after=0"* ]]
}

@test "newer_gxx_majors: lists only NEWER g++ versions on PATH, newest first" {
    probe '
        mkdir -p "$TEST_BIN"
        for v in 13 14 16 20; do
            printf "#!/bin/sh\n" > "$TEST_BIN/g++-$v"; chmod +x "$TEST_BIN/g++-$v"
        done
        PATH="$TEST_BIN" newer_gxx_majors 15
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "20" ]
    [ "${lines[1]}" = "16" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "newer_gxx_majors: an unreadable compiler version yields no candidates" {
    probe '
        mkdir -p "$TEST_BIN"
        printf "#!/bin/sh\n" > "$TEST_BIN/g++-13"; chmod +x "$TEST_BIN/g++-13"
        PATH="$TEST_BIN" newer_gxx_majors ""
        PATH="$TEST_BIN" newer_gxx_majors "not-a-version"
        echo "done"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "done" ]
}

@test "newer_gxx_majors: ignores non-executable files and non-numeric suffixes" {
    probe '
        mkdir -p "$TEST_BIN"
        printf "#!/bin/sh\n" > "$TEST_BIN/g++-16"              # not chmod +x
        printf "#!/bin/sh\n" > "$TEST_BIN/g++-16.2"; chmod +x "$TEST_BIN/g++-16.2"
        printf "#!/bin/sh\n" > "$TEST_BIN/g++-trunk"; chmod +x "$TEST_BIN/g++-trunk"
        PATH="$TEST_BIN" newer_gxx_majors 15
        echo "done"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "done" ]
}

@test "compiler selection: the step-up runs only when no --cxx was given" {
    run grep -cE '^[[:space:]]*if \[ "\$CXX_EXPLICIT" = false \] && ! cxx_can_build_source "\$CXX"; then$' "$SETUP"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# ---------------------------------------------------------------------------
# stage_prefix / rollback_prefix — surviving a run that was KILLED
#
# The rollback covers every exit path the shell can see. SIGKILL is not one of
# them, so a killed run leaves a half-built $DEST beside an orphaned
# $DEST.rollback.<pid> that holds the real install. On 2026-11-05 the next run
# staged that wreckage aside as if it were the install, and reported the
# compositor "back in place" over a prefix with no binary in it — 0.57.0 stayed
# parked in /opt/hyprland.rollback.1375914. See docs/hyprland-status.md,
# incident 4.
# ---------------------------------------------------------------------------

@test "prefix_is_usable: a prefix is an install only if bin/Hyprland can run" {
    probe '
        given_installed_build
        prefix_is_usable "$DEST" && echo "installed=usable" || echo "installed=NOT"
        chmod -x "$DEST/bin/Hyprland"
        prefix_is_usable "$DEST" && echo "nonexec=usable" || echo "nonexec=NOT"
        rm -f "$DEST/bin/Hyprland"
        prefix_is_usable "$DEST" && echo "nobinary=usable" || echo "nobinary=NOT"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "installed=usable" ]
    [ "${lines[1]}" = "nonexec=NOT" ]
    [ "${lines[2]}" = "nobinary=NOT" ]
}

@test "stage_prefix: adopts the install a killed run orphaned" {
    probe '
        given_wreckage
        given_orphaned_backup 1375914 "REAL-INSTALL"
        stage_prefix >/dev/null
        show "staged" "$PREFIX_BACKUP/bin/Hyprland"
        echo "orphan_left=$([ -e "$DEST.rollback.1375914" ] && echo yes || echo no)"
        echo "fresh_dest_empty=$([ -e "$DEST/bin" ] && echo no || echo yes)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "staged=REAL-INSTALL" ]
    [ "${lines[1]}" = "orphan_left=no" ]
    [ "${lines[2]}" = "fresh_dest_empty=yes" ]
}

@test "stage_prefix: a usable prefix is never traded for an orphan" {
    probe '
        given_installed_build
        given_orphaned_backup 1375914 "STALE-ORPHAN"
        stage_prefix >/dev/null
        show "staged" "$PREFIX_BACKUP/bin/Hyprland"
        echo "orphan_left=$([ -e "$DEST.rollback.1375914" ] && echo yes || echo no)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "staged=GOOD-BUILD" ]
    [ "${lines[1]}" = "orphan_left=yes" ]
}

@test "stage_prefix: picks the NEWEST orphan when a run was killed twice" {
    probe '
        given_wreckage
        given_orphaned_backup 999 "OLDER-ORPHAN"
        touch -d "2026-10-01 12:00" "$DEST.rollback.999"
        given_orphaned_backup 111 "NEWER-ORPHAN"
        touch -d "2026-11-01 12:00" "$DEST.rollback.111"
        echo "glob_order=$(cd "$(dirname "$DEST")" && echo "$(basename "$DEST")".rollback.*)"
        stage_prefix >/dev/null
        show "staged" "$PREFIX_BACKUP/bin/Hyprland"
    '
    [ "$status" -eq 0 ]
    # Guard the guard: if the glob ever happens to list them newest-last, this
    # test stops proving anything about the mtime comparison.
    [ "${lines[0]}" = "glob_order=hyprland.rollback.111 hyprland.rollback.999" ]
    [ "${lines[1]}" = "staged=NEWER-ORPHAN" ]
}

@test "stage_prefix: an orphan with no runnable binary is not adopted" {
    probe '
        given_wreckage
        mkdir -p "$DEST.rollback.333/lib"
        echo "JUNK" > "$DEST.rollback.333/lib/libaquamarine.so.16"
        stage_prefix >/dev/null
        show "staged" "$PREFIX_BACKUP/lib/libaquamarine.so.16"
        echo "orphan_left=$([ -e "$DEST.rollback.333" ] && echo yes || echo no)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "staged=NEW-DEP" ]
    [ "${lines[1]}" = "orphan_left=yes" ]
}

@test "rollback_prefix: does not claim a compositor is back when none is there" {
    probe '
        given_wreckage
        stage_prefix >/dev/null
        rollback_prefix 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"back in place"* ]]
    [[ "$output" == *"NO runnable bin/Hyprland"* ]]
}

@test "rollback_prefix: still says back in place when the install really returns" {
    probe '
        given_installed_build
        stage_prefix >/dev/null
        rollback_prefix 2>&1
        show "restored" "$DEST/bin/Hyprland"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"back in place"* ]]
    [[ "$output" == *"restored=GOOD-BUILD"* ]]
}

@test "rollback_prefix: names the orphan holding the real install" {
    probe '
        given_wreckage
        given_orphaned_backup 1375914 "REAL-INSTALL"
        PREFIX_BACKUP="$DEST.staged"
        mkdir -p "$PREFIX_BACKUP/lib"
        rollback_prefix 2>&1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rollback.1375914"* ]]
    [[ "$output" == *"adopts it"* ]]
}

@test "arm_build_rollback: SIGHUP also unwinds the staging" {
    probe '
        given_installed_build
        arm_build_rollback
        trap -p HUP
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SIGHUP"* ]]
    [[ "$output" == *"exit 129"* ]]
}

@test "adopt_orphan_if_needed: leaves a usable prefix and a missing prefix alone" {
    probe '
        given_orphaned_backup 1375914 "REAL-INSTALL"
        given_installed_build
        adopt_orphan_if_needed >/dev/null
        show "usable_untouched" "$DEST/bin/Hyprland"
        rm -rf "$DEST"
        adopt_orphan_if_needed >/dev/null
        echo "absent_stays_absent=$([ -e "$DEST" ] && echo no || echo yes)"
        echo "orphan_left=$([ -e "$DEST.rollback.1375914" ] && echo yes || echo no)"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usable_untouched=GOOD-BUILD" ]
    [ "${lines[1]}" = "absent_stays_absent=yes" ]
    [ "${lines[2]}" = "orphan_left=yes" ]
}

@test "adopt_orphan_if_needed: the registration-only path calls it" {
    run grep -A2 -E '^if \[ "\$SKIP_BUILD" = true \]; then$' "$SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"adopt_orphan_if_needed"* ]]
}

@test "--skip-build: recovers a wrecked prefix instead of refusing to register" {
    # The dead end this closes: with $DEST holding no binary, the validation
    # below printed "not found or not executable" and exited 1, while the real
    # install sat in $DEST.rollback.*. Driving the whole script is not possible
    # here (root, /opt, update-alternatives), so assert the two facts that
    # decide it: the adoption runs BEFORE the validation that used to reject.
    adopt_line=$(grep -n '^if \[ "\$SKIP_BUILD" = true \]; then$' "$SETUP" | cut -d: -f1)
    check_line=$(grep -n '^if \[ ! -x "\$UP_HYPR" \]; then$' "$SETUP" | cut -d: -f1)
    [ -n "$adopt_line" ]
    [ -n "$check_line" ]
    [ "$adopt_line" -lt "$check_line" ]
}
