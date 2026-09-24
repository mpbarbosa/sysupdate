#!/usr/bin/env bats
#
# Tests for scripts/lib/core_lib.sh
# Covers: normalize_version_for_comparison, compare_versions

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # These suites assert the headless code paths — the ones guarded by
    # `[ -t 0 ]`. bats does NOT detach stdin: launched from an interactive
    # shell, fd 0 is the operator's terminal and those branches invert. Pin it
    # so the result does not depend on how the suite was started.
    exec 0</dev/null
    # Suppress color output so assertions match plain text
    export NO_COLOR=1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/core_lib.sh"
}

# ---------------------------------------------------------------------------
# normalize_version_for_comparison
# ---------------------------------------------------------------------------

@test "normalize_version: strips leading v" {
    run normalize_version_for_comparison "v1.2.3"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
}

@test "normalize_version: strips single trailing zero" {
    run normalize_version_for_comparison "1.2.0"
    [ "$output" = "1.2" ]
}

@test "normalize_version: strips multiple trailing zeros" {
    run normalize_version_for_comparison "1.0.0"
    [ "$output" = "1" ]
}

@test "normalize_version: keeps non-trailing zeros" {
    run normalize_version_for_comparison "1.2.3"
    [ "$output" = "1.2.3" ]
}

@test "normalize_version: keeps internal zeros" {
    run normalize_version_for_comparison "1.0.1"
    [ "$output" = "1.0.1" ]
}

@test "normalize_version: single zero stays as zero" {
    run normalize_version_for_comparison "0"
    [ "$output" = "0" ]
}

@test "normalize_version: non-numeric version returned as-is" {
    run normalize_version_for_comparison "1.2.3-ea"
    [ "$output" = "1.2.3-ea" ]
}

@test "normalize_version: strips leading whitespace" {
    run normalize_version_for_comparison "  1.2.3"
    [ "$output" = "1.2.3" ]
}

# ---------------------------------------------------------------------------
# compare_versions
# ---------------------------------------------------------------------------

@test "compare_versions: equal versions returns 0" {
    run compare_versions "1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}

@test "compare_versions: v1 greater returns 1" {
    run compare_versions "2.0.0" "1.9.9"
    [ "$status" -eq 1 ]
}

@test "compare_versions: v1 lesser returns 2" {
    run compare_versions "1.9.9" "2.0.0"
    [ "$status" -eq 2 ]
}

@test "compare_versions: minor segment correctly ordered (1.10 > 1.9)" {
    run compare_versions "1.10.0" "1.9.0"
    [ "$status" -eq 1 ]
}

@test "compare_versions: patch-level update detected (26.3.0 < 26.3.1)" {
    run compare_versions "26.3.0" "26.3.1"
    [ "$status" -eq 2 ]
}

@test "compare_versions: leading v stripped before comparing" {
    run compare_versions "v1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}

@test "compare_versions: trailing zeros normalized (1.2.0 == 1.2)" {
    run compare_versions "1.2.0" "1.2"
    [ "$status" -eq 0 ]
}

@test "compare_versions: stable release newer than alpha-suffixed pre-release" {
    run compare_versions "3.6" "3.6a"
    [ "$status" -eq 1 ]
}

@test "compare_versions: pre-release older than stable release" {
    run compare_versions "3.6a" "3.6"
    [ "$status" -eq 2 ]
}

@test "compare_versions: identical alpha-suffixed versions are equal" {
    run compare_versions "3.6a" "3.6a"
    [ "$status" -eq 0 ]
}

@test "compare_versions: major version bump detected" {
    run compare_versions "0.42.0" "1.0.0"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# ensure_user_paths
#
# Per-user install dirs (e.g. ~/.local/bin for the Claude Code native installer)
# must be on PATH so `command -v <tool>` does not misreport installed tools as
# missing. Tests use a fake HOME so they never touch the real environment.
# ---------------------------------------------------------------------------

@test "ensure_user_paths: prepends existing ~/.local/bin when absent" {
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
    PATH="/usr/bin:/bin"
    ensure_user_paths
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]
}

@test "ensure_user_paths: does not add a missing directory" {
    HOME="$BATS_TEST_TMPDIR/home-empty"
    mkdir -p "$HOME"   # no .local/bin, no bin
    PATH="/usr/bin:/bin"
    ensure_user_paths
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]
}

@test "ensure_user_paths: is idempotent (no duplicate entries)" {
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
    PATH="/usr/bin:/bin"
    ensure_user_paths
    local once="$PATH"
    ensure_user_paths
    [ "$PATH" = "$once" ]
}

# ---------------------------------------------------------------------------
# sudo_can_run
#
# bats runs with stdin that is not a TTY, so [ -t 0 ] is false here. That lets
# us exercise the non-interactive path deterministically by stubbing `sudo` to
# control whether credentials are reported as cached.
# ---------------------------------------------------------------------------

@test "sudo_can_run: false when no cached creds and no TTY" {
    sudo() { return 1; }  # `sudo -n true` fails -> creds not cached
    export -f sudo
    run sudo_can_run
    [ "$status" -ne 0 ]
}

@test "sudo_can_run: true when credentials are cached" {
    sudo() { return 0; }  # `sudo -n true` succeeds -> creds cached
    export -f sudo
    run sudo_can_run
    [ "$status" -eq 0 ]
}

@test "sudo_can_run: true when SUDO_ASKPASS names an executable helper" {
    sudo() { return 1; }  # creds not cached, no TTY: only the helper can save it
    export -f sudo
    export SUDO_ASKPASS="$BATS_TEST_TMPDIR/askpass"
    printf '#!/bin/sh\necho secret\n' > "$SUDO_ASKPASS"
    chmod +x "$SUDO_ASKPASS"
    run sudo_can_run
    [ "$status" -eq 0 ]
}

@test "sudo_can_run: false when SUDO_ASKPASS is set but not executable" {
    sudo() { return 1; }
    export -f sudo
    export SUDO_ASKPASS="$BATS_TEST_TMPDIR/askpass"
    printf '#!/bin/sh\necho secret\n' > "$SUDO_ASKPASS"
    run sudo_can_run
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# enable_sudo_askpass_shim
# ---------------------------------------------------------------------------

@test "askpass shim: puts a sudo wrapper on PATH that adds -A" {
    export SYSUPDATE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export SUDO_ASKPASS="$BATS_TEST_TMPDIR/askpass"
    printf '#!/bin/sh\necho secret\n' > "$SUDO_ASKPASS"
    chmod +x "$SUDO_ASKPASS"
    # A fake "real" sudo that just reports how it was called.
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho "real-sudo:$*"\n' > "$BATS_TEST_TMPDIR/bin/sudo"
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    enable_sudo_askpass_shim
    [ "${PATH%%:*}" = "$SYSUPDATE_STATE_DIR/askpass-shim" ]
    [ -x "$SYSUPDATE_STATE_DIR/askpass-shim/sudo" ]

    run sudo apt-get install -y foo
    [ "$status" -eq 0 ]
    [ "$output" = "real-sudo:-A apt-get install -y foo" ]
}

@test "askpass shim: idempotent, PATH gains the shim dir once" {
    export SYSUPDATE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export SUDO_ASKPASS="$BATS_TEST_TMPDIR/askpass"
    printf '#!/bin/sh\necho secret\n' > "$SUDO_ASKPASS"
    chmod +x "$SUDO_ASKPASS"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho "real-sudo:$*"\n' > "$BATS_TEST_TMPDIR/bin/sudo"
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    enable_sudo_askpass_shim
    local once="$PATH"
    enable_sudo_askpass_shim
    [ "$PATH" = "$once" ]
    # The regenerated shim still targets the real binary, not itself.
    run sudo -n true
    [ "$output" = "real-sudo:-A -n true" ]
}

@test "askpass shim: no-op without SUDO_ASKPASS" {
    export SYSUPDATE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    unset SUDO_ASKPASS
    local before="$PATH"
    enable_sudo_askpass_shim
    [ "$PATH" = "$before" ]
    [ ! -e "$SYSUPDATE_STATE_DIR/askpass-shim/sudo" ]
}

# ---------------------------------------------------------------------------
# run_with_sudo
# ---------------------------------------------------------------------------

@test "run_with_sudo: fails without running command when no creds and no TTY" {
    sudo() { return 1; }  # creds not cached; never reach the real invocation
    export -f sudo
    # Sentinel: the wrapped command must never execute on the bail path.
    export RAN_MARKER="$BATS_TEST_TMPDIR/cmd-ran"
    run run_with_sudo touch "$RAN_MARKER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sudo credentials required"* ]]
    [ ! -f "$RAN_MARKER" ]
}

@test "run_with_sudo: runs command when credentials are cached" {
    # `sudo -n true` (5 args) -> creds cached; the real call passes args through
    sudo() { if [ "$1" = "-n" ]; then return 0; fi; "${@}"; }
    export -f sudo
    run run_with_sudo echo ran-ok
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-ok"* ]]
}
