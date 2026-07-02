#!/usr/bin/env bats
#
# Tests for scripts/lib/upgrade_utils.sh and scripts/lib/app_managers.sh
# Covers: extract_version, get_config, list_upgrade_snippets (snippet discovery)

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    FIXTURES_DIR="$(dirname "$BATS_TEST_FILENAME")/fixtures"
    export NO_COLOR=1
    # upgrade_utils.sh sources core_lib.sh internally
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/upgrade_utils.sh"
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/app_managers.sh"
    export CONFIG_FILE="$FIXTURES_DIR/sample.yaml"
}

# ---------------------------------------------------------------------------
# extract_version
# ---------------------------------------------------------------------------

@test "extract_version: extracts semver from rtk-style output" {
    run extract_version "rtk 0.42.0" 'rtk ([0-9]+\.[0-9]+\.[0-9]+)'
    [ "$status" -eq 0 ]
    [ "$output" = "0.42.0" ]
}

@test "extract_version: extracts version from node-style output" {
    run extract_version "v26.3.0" 'v([0-9]+\.[0-9]+\.[0-9]+)'
    [ "$output" = "26.3.0" ]
}

@test "extract_version: no match returns empty string" {
    run extract_version "no version here" '([0-9]+\.[0-9]+\.[0-9]+)'
    [ "$output" = "" ]
}

@test "extract_version: uses default pattern for two-part version" {
    run extract_version "tmux 3.4"
    [ "$output" = "3.4" ]
}

@test "extract_version: uses default pattern for version with alpha suffix" {
    run extract_version "app 2.6a"
    [ "$output" = "2.6a" ]
}

@test "extract_version: extracts first match when multiple numbers present" {
    run extract_version "app 1.2.3 (build 456)" '([0-9]+\.[0-9]+\.[0-9]+)'
    [ "$output" = "1.2.3" ]
}

# ---------------------------------------------------------------------------
# get_config
# ---------------------------------------------------------------------------

@test "get_config: reads a present string key" {
    run get_config "application.name"
    [ "$status" -eq 0 ]
    [ "$output" = "testapp" ]
}

@test "get_config: reads a nested key" {
    run get_config "version.source"
    [ "$status" -eq 0 ]
    [ "$output" = "github" ]
}

@test "get_config: reads a message string" {
    run get_config "messages.update_success"
    [ "$status" -eq 0 ]
    [ "$output" = "Test app updated" ]
}

@test "get_config: missing key returns empty and exits 1" {
    run get_config "does.not.exist"
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "get_config: empty key returns empty and exits 1" {
    run get_config ""
    [ "$status" -eq 1 ]
}

@test "get_config: missing file returns empty and exits 1" {
    run get_config "application.name" "/nonexistent/path.yaml"
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "get_config: null yaml value returns empty and exits 1" {
    run get_config "null_key"
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "get_config: explicit config_file arg takes precedence over CONFIG_FILE" {
    run get_config "application.name" "$FIXTURES_DIR/sample.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "testapp" ]
}

# ---------------------------------------------------------------------------
# list_upgrade_snippets (snippet discovery)
# ---------------------------------------------------------------------------

@test "list_upgrade_snippets: rtk snippet is discovered" {
    run list_upgrade_snippets
    [[ "$output" == *"rtk"* ]]
}

@test "list_upgrade_snippets: claude snippet is discovered" {
    run list_upgrade_snippets
    [[ "$output" == *"claude"* ]]
}

@test "list_upgrade_snippets: nodejs snippet is discovered" {
    run list_upgrade_snippets
    [[ "$output" == *"nodejs"* ]]
}

@test "list_upgrade_snippets: output contains ID and NAME columns" {
    run list_upgrade_snippets
    [[ "$output" == *"ID"* ]]
    [[ "$output" == *"NAME"* ]]
}

# ---------------------------------------------------------------------------
# perform_configured_installer_script_update (sudo pre-flight)
#
# A wget_sudo_installer needs root. In a non-interactive context with no cached
# credentials (bats stdin is not a TTY) it must bail BEFORE downloading rather
# than fetching the installer and then failing on sudo.
# ---------------------------------------------------------------------------

@test "installer update: bails before download when sudo unavailable" {
    export CONFIG_FILE="$FIXTURES_DIR/installer.yaml"
    export APP_DISPLAY_NAME="Test Installer App"
    # No cached creds; never reach the real sudo invocation.
    sudo() { return 1; }
    # Sentinel: wget must NOT be called on the pre-flight bail path.
    export WGET_MARKER="$BATS_TEST_TMPDIR/wget-was-called"
    wget() { : > "$WGET_MARKER"; return 0; }
    export -f sudo wget

    run perform_configured_installer_script_update
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sudo credentials required"* ]]
    [ ! -f "$WGET_MARKER" ]
}

@test "installer update: proceeds to download when sudo credentials cached" {
    export CONFIG_FILE="$FIXTURES_DIR/installer.yaml"
    export APP_DISPLAY_NAME="Test Installer App"
    # `sudo -n true` succeeds -> creds cached; real `sudo sh <script>` is a no-op.
    sudo() { if [ "$1" = "-n" ]; then return 0; fi; return 0; }
    export WGET_MARKER="$BATS_TEST_TMPDIR/wget-was-called"
    wget() { : > "$WGET_MARKER"; return 0; }
    # Stop after the install step so the test doesn't probe a real version.
    verify_configured_update_result() { return 0; }
    export -f sudo wget verify_configured_update_result

    run perform_configured_installer_script_update
    [ "$status" -eq 0 ]
    [ -f "$WGET_MARKER" ]
}

# ---------------------------------------------------------------------------
# perform_configured_installer_script_update (curl_bash_installer method)
#
# Some official installers (e.g. Oh My Posh) are bash scripts targeting a
# user-writable dir. This method must download via curl, run with bash (NOT sh),
# and never invoke sudo.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# perform_configured_deb_package_update (sudo pre-flight)
#
# Installing a .deb needs root (dpkg -i + apt-get -f). In a non-interactive
# context with no cached credentials it must bail BEFORE downloading the
# package rather than fetching a large .deb and then failing on sudo.
# ---------------------------------------------------------------------------

@test "deb update: bails before download when sudo unavailable" {
    export CONFIG_FILE="$FIXTURES_DIR/deb_package.yaml"
    export APP_DISPLAY_NAME="Test Deb App"
    # No cached creds; never reach the real sudo invocation.
    sudo() { return 1; }
    # Sentinels: neither curl (URL resolve) nor wget (download) must run.
    export CURL_MARKER="$BATS_TEST_TMPDIR/curl-was-called"
    export WGET_MARKER="$BATS_TEST_TMPDIR/wget-was-called"
    curl() { : > "$CURL_MARKER"; return 0; }
    wget() { : > "$WGET_MARKER"; return 0; }
    export -f sudo curl wget

    run perform_configured_deb_package_update
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sudo credentials required"* ]]
    [ ! -f "$CURL_MARKER" ]
    [ ! -f "$WGET_MARKER" ]
}

@test "deb update: proceeds to download when sudo credentials cached" {
    export CONFIG_FILE="$FIXTURES_DIR/deb_package.yaml"
    export APP_DISPLAY_NAME="Test Deb App"
    # `sudo -n true` succeeds -> creds cached; real sudo dpkg/apt-get are no-ops.
    sudo() { if [ "$1" = "-n" ]; then return 0; fi; return 0; }
    export WGET_MARKER="$BATS_TEST_TMPDIR/wget-was-called"
    # curl resolves the effective URL; wget downloads the package.
    curl() { echo "https://example.com/latest.deb"; return 0; }
    wget() { : > "$WGET_MARKER"; return 0; }
    verify_configured_update_result() { return 0; }
    export -f sudo curl wget verify_configured_update_result

    run perform_configured_deb_package_update
    [ "$status" -eq 0 ]
    [ -f "$WGET_MARKER" ]
}

@test "curl_bash_installer: downloads with curl and runs with bash, no sudo" {
    export CONFIG_FILE="$FIXTURES_DIR/installer_bash.yaml"
    export APP_DISPLAY_NAME="Test Bash Installer App"
    export CURL_MARKER="$BATS_TEST_TMPDIR/curl-was-called"
    export BASH_MARKER="$BATS_TEST_TMPDIR/bash-was-called"
    export SH_MARKER="$BATS_TEST_TMPDIR/sh-was-called"
    export SUDO_MARKER="$BATS_TEST_TMPDIR/sudo-was-called"
    # curl writes the requested output file ($4 = path after -o) so mktemp's file exists.
    curl() { : > "$CURL_MARKER"; [ -n "$4" ] && : > "$4"; return 0; }
    bash() { : > "$BASH_MARKER"; return 0; }
    sh()   { : > "$SH_MARKER"; return 0; }
    sudo() { : > "$SUDO_MARKER"; return 0; }
    verify_configured_update_result() { return 0; }
    export -f curl bash sh sudo verify_configured_update_result

    run perform_configured_installer_script_update
    [ "$status" -eq 0 ]
    [ -f "$CURL_MARKER" ]      # downloaded via curl
    [ -f "$BASH_MARKER" ]      # ran with bash
    [ ! -f "$SH_MARKER" ]      # NOT run with sh
    [ ! -f "$SUDO_MARKER" ]    # no sudo
}
