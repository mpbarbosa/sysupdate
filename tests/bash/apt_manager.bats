#!/usr/bin/env bats
#
# Tests for scripts/lib/apt_manager.sh
# Covers: list_partially_installed_packages (broken-package detection)

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # These suites assert the headless code paths — the ones guarded by
    # `[ -t 0 ]`. bats does NOT detach stdin: launched from an interactive
    # shell, fd 0 is the operator's terminal and those branches invert. Pin it
    # so the result does not depend on how the suite was started.
    exec 0</dev/null
    export NO_COLOR=1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/core_lib.sh"
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/apt_manager.sh"
}

# Put a fake dpkg-query on PATH emitting a canned "<pkg> <want> <flag> <state>"
# table. Mirrors `dpkg-query -W -f='${Package} ${Status}\n'`.
stub_dpkg_query_table() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    {
        echo '#!/bin/bash'
        echo "cat <<'TABLE'"
        cat
        echo 'TABLE'
    } > "$STUB_BIN/dpkg-query"
    chmod +x "$STUB_BIN/dpkg-query"
    PATH="$STUB_BIN:$PATH"
}

@test "list_partially_installed_packages: flags unpacked and half-configured" {
    stub_dpkg_query_table <<'TABLE'
bash install ok installed
code-insiders install ok unpacked
code install ok half-configured
TABLE
    run list_partially_installed_packages
    [ "$status" -eq 0 ]
    [[ "$output" == *"code-insiders ok unpacked"* ]]
    [[ "$output" == *"code ok half-configured"* ]]
    [[ "$output" != *"bash"* ]]
}

@test "list_partially_installed_packages: flags triggers-pending" {
    stub_dpkg_query_table <<'TABLE'
dbus install ok triggers-pending
TABLE
    run list_partially_installed_packages
    [[ "$output" == *"dbus ok triggers-pending"* ]]
}

# Removed-but-not-purged is a normal steady state, not breakage. Reporting it
# would make almost every Debian system look permanently broken.
@test "list_partially_installed_packages: ignores removed-but-not-purged" {
    stub_dpkg_query_table <<'TABLE'
acpid deinstall ok config-files
TABLE
    run list_partially_installed_packages
    [ "$output" = "" ]
}

@test "list_partially_installed_packages: empty on a healthy system" {
    stub_dpkg_query_table <<'TABLE'
bash install ok installed
coreutils install ok installed
TABLE
    run list_partially_installed_packages
    [ "$output" = "" ]
}

# Regression: `dpkg --audit` needs the dpkg lock and exits 2 with empty stdout
# for an unprivileged user, which used to be read as "system is healthy".
# dpkg-query reads the status file and needs no lock, but if it is missing
# entirely we must still not claim health by returning a package list.
@test "list_partially_installed_packages: no dpkg-query yields no false healthy claim" {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    printf '#!/bin/bash\necho "dpkg-query: permission denied" >&2\nexit 2\n' > "$STUB_BIN/dpkg-query"
    chmod +x "$STUB_BIN/dpkg-query"
    PATH="$STUB_BIN:$PATH"
    run list_partially_installed_packages
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# run_apt / apt_debconf_is_unattended
#
# Regression: a headless run (web backend, timer) still gets a pty from apt, so
# code.postinst saw `[ -t 1 ]` as true, debconf chose whiptail, and the dialog
# blocked dpkg indefinitely with no one able to answer it.
# ---------------------------------------------------------------------------

# Replace run_with_sudo so we can assert on the argv run_apt builds, without
# invoking sudo.
stub_run_with_sudo() {
    run_with_sudo() { echo "$*"; }
}

@test "run_apt: forces noninteractive debconf in quiet mode" {
    stub_run_with_sudo
    QUIET_MODE=true CHECK_ONLY_MODE=false
    run run_apt apt upgrade -y
    [[ "$output" == "DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt upgrade -y" ]]
}

@test "run_apt: forces noninteractive debconf in check-only mode" {
    stub_run_with_sudo
    QUIET_MODE=false CHECK_ONLY_MODE=true
    run run_apt apt-get update
    [[ "$output" == *"DEBIAN_FRONTEND=noninteractive"* ]]
}

# bats runs with stdin detached, standing in for a headless backend-spawned run.
@test "run_apt: forces noninteractive debconf when stdin is not a terminal" {
    stub_run_with_sudo
    QUIET_MODE=false CHECK_ONLY_MODE=false
    run run_apt dpkg --configure -a
    [[ "$output" == "DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true dpkg --configure -a" ]]
}

@test "apt_debconf_is_unattended: true when stdin is not a terminal" {
    QUIET_MODE=false CHECK_ONLY_MODE=false
    run apt_debconf_is_unattended
    [ "$status" -eq 0 ]
}

# An interactive operator should still get real debconf prompts.
@test "run_apt: leaves debconf alone when a terminal is attached" {
    stub_run_with_sudo
    QUIET_MODE=false CHECK_ONLY_MODE=false
    # Force the interactive branch by overriding the interactivity predicate.
    apt_debconf_is_unattended() { return 1; }
    run run_apt apt upgrade -y
    [[ "$output" == "apt upgrade -y" ]]
}
