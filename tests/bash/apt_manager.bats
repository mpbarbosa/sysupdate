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

# ---------------------------------------------------------------------------
# apt_classify_upgrade_failure / apt_recover_from_dependency_failure
#
# Regression: apt exits 100 for every failure, so a solver failure
# ("libudev-dev : Depends: libudev1 (= 259.9) but 259.5 is installed") was
# retried twice with --fix-missing. --fix-missing only skips archives that
# could not be fetched; with nothing to fetch the retries reproduced the same
# error and the run ended on a message about network problems.
# ---------------------------------------------------------------------------

@test "apt_classify_upgrade_failure: unmet dependencies classify as dependency" {
    run apt_classify_upgrade_failure "$(cat <<'OUT'
Reading package lists...
You might want to run 'apt --fix-broken install' to correct these.
Unsatisfied dependencies:
 libudev-dev : Depends: libudev1 (= 259.9-0ubuntu0.1) but 259.5-0ubuntu3.4 is installed
Error: Unmet dependencies. Try 'apt --fix-broken install' with no packages (or specify a solution).
OUT
)"
    [ "$output" = "dependency" ]
}

@test "apt_classify_upgrade_failure: held broken packages classify as dependency" {
    run apt_classify_upgrade_failure "E: Unable to correct problems, you have held broken packages."
    [ "$output" = "dependency" ]
}

@test "apt_classify_upgrade_failure: fetch errors stay on the --fix-missing path" {
    run apt_classify_upgrade_failure "E: Failed to fetch http://archive.ubuntu.com/pool/f.deb  Connection failed"
    [ "$output" = "fetch" ]
}

@test "apt_classify_upgrade_failure: unrecognised failures fall back to unknown" {
    run apt_classify_upgrade_failure "E: Sub-process /usr/bin/dpkg returned an error code (1)"
    [ "$output" = "unknown" ]
}

@test "apt_extract_unmet_dependency_lines: names the blocking package" {
    run apt_extract_unmet_dependency_lines "$(cat <<'OUT'
Unsatisfied dependencies:
 libudev-dev : Depends: libudev1 (= 259.9-0ubuntu0.1) but 259.5-0ubuntu3.4 is installed
 foo : Conflicts: bar
OUT
)"
    [[ "$output" == *"libudev-dev : Depends: libudev1"* ]]
    [[ "$output" == *"foo : Conflicts: bar"* ]]
    [[ "$output" != *"Unsatisfied dependencies:"* ]]
}

# Record the apt invocations the recovery makes, so the test asserts on the
# commands rather than on printed prose.
stub_run_apt_recorder() {
    APT_CALLS="$BATS_TEST_TMPDIR/apt_calls"
    : > "$APT_CALLS"
    run_apt() {
        echo "$*" >> "$APT_CALLS"
        case "$*" in
            *"--fix-broken install"*) return "${FIX_BROKEN_RC:-0}" ;;
            *) return "${UPGRADE_RETRY_RC:-0}" ;;
        esac
    }
}

@test "apt_recover_from_dependency_failure: fixes broken deps then re-runs the upgrade" {
    stub_run_apt_recorder
    run_recover() { apt_recover_from_dependency_failure "libudev-dev : Depends: libudev1" 100; }
    run run_recover
    [ "$status" -eq 0 ]
    [[ "$(sed -n 1p "$APT_CALLS")" == *"apt-get --fix-broken install -y"* ]]
    [[ "$(sed -n 2p "$APT_CALLS")" == *"apt upgrade -y"* ]]
    # A routine upgrade removes nothing, so neither may its repair.
    grep -q -- "--no-remove" "$APT_CALLS"
    # --fix-missing is for unfetchable archives; it must not appear here.
    ! grep -q -- "--fix-missing" "$APT_CALLS"
}

@test "apt_recover_from_dependency_failure: reports failure when --fix-broken cannot help" {
    stub_run_apt_recorder
    FIX_BROKEN_RC=100
    run_recover() { apt_recover_from_dependency_failure "libudev-dev : Depends: libudev1 (= 259.9) but 259.5 is installed" 100; }
    run run_recover
    [ "$status" -eq 1 ]
    [[ "$output" == *"libudev-dev : Depends: libudev1"* ]]
    [[ "$output" == *"dist-upgrade"* ]]
    [ "$(wc -l < "$APT_CALLS")" -eq 1 ]
}

@test "apt_recover_from_dependency_failure: reports failure when the re-run still fails" {
    stub_run_apt_recorder
    UPGRADE_RETRY_RC=100
    run_recover() { apt_recover_from_dependency_failure "unmet deps" 100; }
    run run_recover
    [ "$status" -eq 1 ]
    [ "$(wc -l < "$APT_CALLS")" -eq 2 ]
}

# The wiring itself: a dependency failure inside upgrade_packages must reach
# the fix-broken path, never the --fix-missing retries.
stub_upgrade_packages_env() {
    QUIET_MODE=true
    CHECK_ONLY_MODE=false
    SUDO_UNAVAILABLE=false
    ask_continue() { :; }
    check_updates_available() { return 0; }
    APT_CALLS="$BATS_TEST_TMPDIR/apt_calls"
    : > "$APT_CALLS"
    run_apt() {
        echo "$*" >> "$APT_CALLS"
        case "$*" in
            *"--fix-broken install"*) return 0 ;;
            *"apt upgrade"*)
                if [ "$(grep -c "apt upgrade" "$APT_CALLS")" -eq 1 ]; then
                    cat <<'OUT'
Unsatisfied dependencies:
 libudev-dev : Depends: libudev1 (= 259.9-0ubuntu0.1) but 259.5-0ubuntu3.4 is installed
Error: Unmet dependencies. Try 'apt --fix-broken install' with no packages (or specify a solution).
OUT
                    return 100
                fi
                echo "0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."
                return 0
                ;;
        esac
        return 0
    }
}

@test "upgrade_packages: routes an unmet-dependency failure to --fix-broken" {
    stub_upgrade_packages_env
    run upgrade_packages
    [ "$status" -eq 0 ]
    [[ "$(sed -n 2p "$APT_CALLS")" == *"apt-get --fix-broken install -y"* ]]
    [[ "$output" == *"not a transient fetch error"* ]]
    ! grep -q -- "--fix-missing" "$APT_CALLS"
}

@test "upgrade_packages: still retries a fetch failure with --fix-missing" {
    stub_upgrade_packages_env
    run_apt() {
        echo "$*" >> "$APT_CALLS"
        case "$*" in
            *"--fix-missing"*) echo "Fetched 1 B"; return 0 ;;
            *) echo "E: Failed to fetch http://archive.ubuntu.com/pool/f.deb  Connection failed"; return 100 ;;
        esac
    }
    run upgrade_packages
    [ "$status" -eq 0 ]
    grep -q -- "--fix-missing" "$APT_CALLS"
    ! grep -q -- "--fix-broken" "$APT_CALLS"
}
