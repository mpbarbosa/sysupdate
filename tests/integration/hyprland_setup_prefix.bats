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
        SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1 \
        bash -c 'source "$SETUP"
DEST="$TEST_DEST"
given_installed_build() {
    mkdir -p "$DEST/bin" "$DEST/lib"
    echo "GOOD-BUILD" > "$DEST/bin/Hyprland"
    echo "GOOD-LIB"   > "$DEST/lib/libaquamarine.so.13"
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

@test "build_one_dep: wayland-protocols routes to its own data-only builder" {
    probe '
        build_hypr_dep()          { echo "hyprwm name=$1 ref=${2:-<latest>}"; }
        build_wayland_protocols() { echo "wayland ref=${1:-<latest>}"; }
        build_one_dep "wayland-protocols@1.49"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "wayland ref=1.49" ]
}
