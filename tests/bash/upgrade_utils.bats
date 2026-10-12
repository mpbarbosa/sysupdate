#!/usr/bin/env bats
#
# Tests for scripts/lib/upgrade_utils.sh and scripts/lib/app_managers.sh
# Covers: extract_version, get_config, list_upgrade_snippets (snippet discovery)

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # These suites assert the headless code paths — the ones guarded by
    # `[ -t 0 ]`. bats does NOT detach stdin: launched from an interactive
    # shell, fd 0 is the operator's terminal and those branches invert. Pin it
    # so the result does not depend on how the suite was started.
    exec 0</dev/null
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
# select_highest_semver_tag (git ls-remote fallback tag parsing)
#
# The anonymous GitHub REST API is rate-limited during multi-snippet scans, so
# `source: github` snippets fall back to `git ls-remote --tags`. Repos with a
# mixed-prefix tag namespace must not leak a non-semver string as "latest".
# ---------------------------------------------------------------------------

@test "select_highest_semver_tag: mixed-prefix namespace picks highest bare semver" {
    # Squirreljetpack/matchmaker-style refs: per-package prefixes plus bare tags.
    input=$'abc123\trefs/tags/matchmaker-partial-v0.0.30
def456\trefs/tags/matchmaker-cli-v0.0.32
789abc\trefs/tags/matchmaker-lib-v0.0.28
012def\trefs/tags/v0.0.5
345678\trefs/tags/v0.1.3'
    run select_highest_semver_tag <<< "$input"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.3" ]
}

@test "select_highest_semver_tag: never returns a prefixed non-semver string" {
    input=$'abc123\trefs/tags/matchmaker-partial-v0.0.30
def456\trefs/tags/matchmaker-cli-v0.0.32'
    run select_highest_semver_tag <<< "$input"
    [ "$output" = "0.0.32" ]
    [[ "$output" != *matchmaker* ]]
}

@test "select_highest_semver_tag: strips leading v and dereference suffix" {
    input=$'abc123\trefs/tags/v1.2.3
def456\trefs/tags/v1.2.3^{}
789abc\trefs/tags/v1.10.0'
    run select_highest_semver_tag <<< "$input"
    [ "$output" = "1.10.0" ]
}

@test "select_highest_semver_tag: discards non-version tags" {
    input=$'abc123\trefs/tags/nightly
def456\trefs/tags/latest
789abc\trefs/tags/release-2024
012def\trefs/tags/v2.1.0'
    run select_highest_semver_tag <<< "$input"
    [ "$output" = "2.1.0" ]
}

@test "select_highest_semver_tag: empty input yields empty output" {
    run select_highest_semver_tag <<< ""
    [ "$output" = "" ]
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
# get_remediation
# ---------------------------------------------------------------------------

@test "get_remediation: substitutes path, repo and branch placeholders" {
    run get_remediation "not_git_repo" "/opt/testapp"
    [ "$status" -eq 0 ]
    [ "$output" = "/opt/testapp is not a Git checkout — clone https://example.invalid/testapp.git (branch trunk) next to it" ]
}

@test "get_remediation: leaves a placeholder-free line untouched" {
    run get_remediation "no_placeholders" "/opt/testapp"
    [ "$output" = "Just do the thing" ]
}

# A snippet without a remediation block must not break the emit site — it
# reports an empty line and the dashboard falls back to its generic message.
@test "get_remediation: unknown key yields empty output and exit 0" {
    run get_remediation "does_not_exist" "/opt/testapp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_remediation: missing config file yields empty output and exit 0" {
    CONFIG_FILE="/nonexistent/path.yaml" run get_remediation "not_git_repo" "/opt/testapp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_remediation: never emits a multi-line string" {
    run get_remediation "not_git_repo" "/opt/testapp"
    [ "${#lines[@]}" -eq 1 ]
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

# ---------------------------------------------------------------------------
# download_with_progress
# ---------------------------------------------------------------------------

@test "download_with_progress: non-TTY stderr uses -nv, not --show-progress" {
    # Under bats, fd 2 is not a terminal — the piped-backend case. The progress
    # bar there degrades to per-chunk dot lines that flood the event stream, so
    # the quiet -nv path must be taken.
    local stubdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stubdir"
    cat > "$stubdir/wget" <<'STUB'
#!/bin/bash
printf '%s\n' "$*"
STUB
    chmod +x "$stubdir/wget"

    PATH="$stubdir:$PATH" run download_with_progress "http://example.test/pkg.deb" "/tmp/pkg.deb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-nv"* ]]
    [[ "$output" != *"--show-progress"* ]]
}

# ---------------------------------------------------------------------------
# dpkg_package_state / dpkg_package_needs_configure
#
# These exist because `command -v <app>` alone cannot tell "never installed"
# apart from "unpacked but never configured" — the latter leaves the binary on
# disk but no PATH symlink, and used to be reported as not_installed.
# ---------------------------------------------------------------------------

# Put a fake dpkg-query on PATH that reports $1's ${Status} triple.
stub_dpkg_query() {
    local status_line="$1"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    if [ "$status_line" = "__unknown__" ]; then
        printf '#!/bin/bash\nexit 1\n' > "$STUB_BIN/dpkg-query"
    else
        printf '#!/bin/bash\nprintf %%s "%s"\n' "$status_line" > "$STUB_BIN/dpkg-query"
    fi
    chmod +x "$STUB_BIN/dpkg-query"
    PATH="$STUB_BIN:$PATH"
}

@test "dpkg_package_state: reports the current-state word" {
    stub_dpkg_query "install ok unpacked"
    run dpkg_package_state somepkg
    [ "$output" = "unpacked" ]
}

@test "dpkg_package_state: empty for a package dpkg does not know" {
    stub_dpkg_query "__unknown__"
    run dpkg_package_state somepkg
    [ "$output" = "" ]
}

@test "dpkg_package_needs_configure: true for unpacked" {
    stub_dpkg_query "install ok unpacked"
    run dpkg_package_needs_configure somepkg
    [ "$status" -eq 0 ]
}

@test "dpkg_package_needs_configure: true for half-configured" {
    stub_dpkg_query "install ok half-configured"
    run dpkg_package_needs_configure somepkg
    [ "$status" -eq 0 ]
}

@test "dpkg_package_needs_configure: false for a fully installed package" {
    stub_dpkg_query "install ok installed"
    run dpkg_package_needs_configure somepkg
    [ "$status" -ne 0 ]
}

@test "dpkg_package_needs_configure: false for removed-but-not-purged" {
    stub_dpkg_query "deinstall ok config-files"
    run dpkg_package_needs_configure somepkg
    [ "$status" -ne 0 ]
}

@test "dpkg_package_needs_configure: false when dpkg does not know the package" {
    stub_dpkg_query "__unknown__"
    run dpkg_package_needs_configure somepkg
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# apt_repository_is_configured
# ---------------------------------------------------------------------------

# Build a fake /etc/apt tree and point the helper at it.
setup_apt_sources_tree() {
    APT_SOURCES_LIST_DIR="$BATS_TEST_TMPDIR/sources.list.d"
    APT_SOURCES_LIST_FILE="$BATS_TEST_TMPDIR/sources.list"
    mkdir -p "$APT_SOURCES_LIST_DIR"
    : > "$APT_SOURCES_LIST_FILE"
}

@test "apt_repository_is_configured: finds a one-line .list entry" {
    setup_apt_sources_tree
    echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -eq 0 ]
}

@test "apt_repository_is_configured: finds a deb822 .sources stanza" {
    setup_apt_sources_tree
    cat > "$APT_SOURCES_LIST_DIR/google-chrome.sources" <<'SOURCES'
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
SOURCES
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -eq 0 ]
}

# The exact shape this machine was in when the chrome snippet re-added a
# duplicate .list: the deb822 migration had parked the old entry as
# `.list.disabled`, which apt does not read and neither must we.
@test "apt_repository_is_configured: ignores .list.disabled and .save leftovers" {
    setup_apt_sources_tree
    echo '# deb http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list.disabled"
    echo 'deb http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list.save"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: ignores a commented-out .list line" {
    setup_apt_sources_tree
    echo '# deb http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: ignores a deb822 stanza disabled with Enabled: no" {
    setup_apt_sources_tree
    cat > "$APT_SOURCES_LIST_DIR/google-chrome.sources" <<'SOURCES'
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Enabled: no
SOURCES
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: finds an entry in the main sources.list" {
    setup_apt_sources_tree
    echo 'deb http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_FILE"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -eq 0 ]
}

@test "apt_repository_is_configured: false on an empty sources tree" {
    setup_apt_sources_tree
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: does not match another vendor's repository" {
    setup_apt_sources_tree
    echo 'deb https://packages.mozilla.org/apt mozilla main' \
        > "$APT_SOURCES_LIST_DIR/mozilla.list"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

# The substring is a URL, not a pattern: dots must not act as wildcards.
@test "apt_repository_is_configured: treats the URL substring literally" {
    setup_apt_sources_tree
    echo 'deb http://dlxgooglexcom/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/lookalike.list"
    run apt_repository_is_configured "dl.google.com/linux/chrome"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: false when given no URL substring" {
    setup_apt_sources_tree
    echo 'deb http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list"
    run apt_repository_is_configured ""
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# apt_package_is_repo_served
#
# Answers "could apt itself upgrade this package?" - the question a snippet
# must settle before treating the apt candidate as the latest version.
# ---------------------------------------------------------------------------

# Stub `apt-cache policy` with a canned version table.
stub_apt_cache_policy() {
    export STUB_APT_POLICY="$1"
    apt-cache() { printf '%s\n' "$STUB_APT_POLICY"; }
    export -f apt-cache
}

@test "apt_package_is_repo_served: true when a repository serves the package" {
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.19675.1
  Candidate: 2.19675.1
  Version table:
 *** 2.19675.1 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    run apt_package_is_repo_served "claude-desktop"
    [ "$status" -eq 0 ]
}

# A package installed from a hand-downloaded .deb still gets a Candidate - its
# own installed version - pinned only to /var/lib/dpkg/status. Reading that
# Candidate as "latest" would call it up to date forever, so the dpkg status
# pin must not count as a source.
@test "apt_package_is_repo_served: false when only the dpkg status pin exists" {
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.19675.1
  Candidate: 2.19675.1
  Version table:
 *** 2.19675.1 100
        100 /var/lib/dpkg/status"
    run apt_package_is_repo_served "claude-desktop"
    [ "$status" -ne 0 ]
}

@test "apt_package_is_repo_served: true for a non-http source scheme" {
    stub_apt_cache_policy "local-app:
  Installed: (none)
  Candidate: 1.2.3
  Version table:
     1.2.3 500
        500 file:/srv/local-repo ./ Packages"
    run apt_package_is_repo_served "local-app"
    [ "$status" -eq 0 ]
}

@test "apt_package_is_repo_served: false for an unknown package" {
    stub_apt_cache_policy "N: Unable to locate package nope"
    run apt_package_is_repo_served "nope"
    [ "$status" -ne 0 ]
}

@test "apt_package_is_repo_served: false when given no package name" {
    stub_apt_cache_policy "anything"
    run apt_package_is_repo_served ""
    [ "$status" -ne 0 ]
}

# The firefox snippet asks the same question about Mozilla's host, and hit the
# same wrong answer: it grepped `mozilla.list` alone, so a deb822-migrated
# machine read as unconfigured and the snippet appended a duplicate entry.

@test "apt_repository_is_configured: finds Mozilla's signed-by .list entry" {
    setup_apt_sources_tree
    echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
        > "$APT_SOURCES_LIST_DIR/mozilla.list"
    run apt_repository_is_configured "packages.mozilla.org"
    [ "$status" -eq 0 ]
}

@test "apt_repository_is_configured: finds Mozilla's deb822 mozilla.sources" {
    setup_apt_sources_tree
    cat > "$APT_SOURCES_LIST_DIR/mozilla.sources" <<'SOURCES'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
SOURCES
    run apt_repository_is_configured "packages.mozilla.org"
    [ "$status" -eq 0 ]
}

# Exactly what the deb822 migration leaves behind: the live source is the
# .sources file, the original .list is parked as .list.disabled. The old
# one-file grep saw "configured" here only by reading a file apt ignores.
@test "apt_repository_is_configured: true for a deb822-migrated Mozilla source with the .list parked" {
    setup_apt_sources_tree
    echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
        > "$APT_SOURCES_LIST_DIR/mozilla.list.disabled"
    cat > "$APT_SOURCES_LIST_DIR/mozilla.sources" <<'SOURCES'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
SOURCES
    run apt_repository_is_configured "packages.mozilla.org"
    [ "$status" -eq 0 ]
}

# A machine with Firefox from Ubuntu only: nothing serves Mozilla, so the
# snippet is right to set the repository up.
@test "apt_repository_is_configured: false when only Ubuntu's own sources are present" {
    setup_apt_sources_tree
    cat > "$APT_SOURCES_LIST_FILE" <<'LIST'
deb http://archive.ubuntu.com/ubuntu noble main restricted
deb http://security.ubuntu.com/ubuntu noble-security main restricted
LIST
    run apt_repository_is_configured "packages.mozilla.org"
    [ "$status" -ne 0 ]
}

@test "apt_repository_is_configured: does not match Mozilla's host against a Chrome-only tree" {
    setup_apt_sources_tree
    echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' \
        > "$APT_SOURCES_LIST_DIR/google-chrome.list"
    run apt_repository_is_configured "packages.mozilla.org"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# source_upgrade_snippets: shell-option isolation
# ---------------------------------------------------------------------------

# Snippets are sourced into the orchestrator's own shell, so a top-level
# `set -u` in one of them used to stay on for every snippet after it. A full
# run died that way inside the sdkman snippet.
write_snippet() {
    local name="$1"
    shift
    mkdir -p "$BATS_TEST_TMPDIR/snippets"
    {
        echo '#!/bin/bash'
        echo "# SNIPPET_ID: $name"
        echo "# SNIPPET_NAME: $name"
        printf '%s\n' "$@"
    } > "$BATS_TEST_TMPDIR/snippets/update_$name.sh"
}

@test "source_upgrade_snippets: a snippet's set -u does not leak to the caller" {
    write_snippet aaa 'set -u'
    SYSUPDATE_SNIPPETS_DIR="$BATS_TEST_TMPDIR/snippets"
    set +u
    source_upgrade_snippets
    [[ "$-" != *u* ]]
}

@test "source_upgrade_snippets: a snippet's set -e does not leak to the caller" {
    write_snippet aaa 'set -e'
    SYSUPDATE_SNIPPETS_DIR="$BATS_TEST_TMPDIR/snippets"
    set +e
    source_upgrade_snippets
    [[ "$-" != *e* ]]
}

@test "source_upgrade_snippets: a snippet's set -o pipefail does not leak to the caller" {
    write_snippet aaa 'set -o pipefail'
    SYSUPDATE_SNIPPETS_DIR="$BATS_TEST_TMPDIR/snippets"
    set +o pipefail
    source_upgrade_snippets
    [ "$(set -o | awk '$1 == "pipefail" { print $2 }')" = "off" ]
}

@test "source_upgrade_snippets: nounset the caller already had is kept" {
    write_snippet aaa 'true'
    SYSUPDATE_SNIPPETS_DIR="$BATS_TEST_TMPDIR/snippets"
    set -u
    source_upgrade_snippets
    local had_u=0
    [[ "$-" == *u* ]] || had_u=1
    set +u
    [ "$had_u" -eq 0 ]
}

# The exact sequence that killed the run: an earlier snippet turns nounset on,
# a later one reads an unset parameter the way SDKMAN's `sdk` function does.
@test "source_upgrade_snippets: a leaked set -u cannot kill a later snippet" {
    write_snippet aaa 'set -u'
    # Shaped like SDKMAN's own `sdk`: reads "$2", called with one argument.
    write_snippet zzz 'fake_sdk() { local qualifier="$2"; echo "qualifier=[$qualifier]"; }' \
        'fake_sdk selfupdate' \
        'echo reached-the-end'
    SYSUPDATE_SNIPPETS_DIR="$BATS_TEST_TMPDIR/snippets"
    run bash -c "
        set +u
        source '$REPO_ROOT/scripts/lib/upgrade_utils.sh'
        source '$REPO_ROOT/scripts/lib/app_managers.sh'
        SYSUPDATE_SNIPPETS_DIR='$BATS_TEST_TMPDIR/snippets'
        source_upgrade_snippets
        echo loader-returned
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached-the-end"* ]]
    [[ "$output" == *"loader-returned"* ]]
}

# ---------------------------------------------------------------------------
# sdkman_run (scripts/upgrade_snippets/update_sdkman.sh)
# ---------------------------------------------------------------------------

# The snippet self-executes when sourced, so write a copy without its trailing
# entry call and hand back the path.
sdkman_functions_file() {
    local copy="$BATS_TEST_TMPDIR/sdkman_functions.sh"
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_sdkman.sh" > "$copy"
    echo "$copy"
}

# `sdk` stands in for SDKMAN's own function, which opens with an unguarded "$2".
@test "sdkman_run: survives nounset when sdk reads an unset \$2" {
    local functions_file
    functions_file=$(sdkman_functions_file)
    run bash -c "
        source '$REPO_ROOT/scripts/lib/upgrade_utils.sh'
        source '$functions_file'
        set -u
        sdk() { local qualifier=\"\$2\"; echo \"ran=\$1 qualifier=[\$qualifier]\"; }
        sdkman_run selfupdate
        echo survived
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran=selfupdate"* ]]
    [[ "$output" == *"survived"* ]]
}

@test "sdkman_run: restores nounset after the call" {
    local functions_file
    functions_file=$(sdkman_functions_file)
    run bash -c "
        source '$REPO_ROOT/scripts/lib/upgrade_utils.sh'
        source '$functions_file'
        set -u
        sdk() { echo sdk-ran; }
        sdkman_run version
        case \"\$-\" in *u*) echo nounset-still-on ;; *) echo nounset-lost ;; esac
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"sdk-ran"* ]]
    [[ "$output" == *"nounset-still-on"* ]]
}

@test "sdkman_run: passes the sdk exit status through" {
    local functions_file
    functions_file=$(sdkman_functions_file)
    run bash -c "
        source '$REPO_ROOT/scripts/lib/upgrade_utils.sh'
        source '$functions_file'
        sdk() { return 3; }
        sdkman_run selfupdate
    "
    [ "$status" -eq 3 ]
}

# ---------------------------------------------------------------------------
# update_nodejs_app: the shipped template must not shout
# ---------------------------------------------------------------------------

# The snippet self-executes when sourced, so load a copy without its entry call
# and point CONFIG_FILE at a config we control.
# The copy keeps the snippet's own `../lib` lookup working, so it loads exactly
# as it does in a real run.
source_nodejs_app_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/pkg/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/pkg/lib"
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_nodejs_app.sh" \
        > "$snippets_dir/update_nodejs_app.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_nodejs_app.sh"
}

write_nodejs_app_config() {
    local directory="$1" name="$2"
    CONFIG_FILE="$BATS_TEST_TMPDIR/nodejs_app.yaml"
    cat > "$CONFIG_FILE" <<YAML
application:
  name: "$name"
  display_name: "My Node.js App"
  directory: "$directory"
dependencies:
  - name: "git"
    command: "git"
    help: "install git"
  - name: "npm"
    command: "npm"
    help: "install npm"
messages:
  install_help: "clone it somewhere"
YAML
}

@test "nodejs_app_config_is_template: true for the shipped placeholders" {
    source_nodejs_app_functions
    write_nodejs_app_config "/opt/my-nodejs-app" "my-nodejs-app"
    run nodejs_app_config_is_template
    [ "$status" -eq 0 ]
}

@test "nodejs_app_config_is_template: false once pointed at a real app" {
    source_nodejs_app_functions
    write_nodejs_app_config "$BATS_TEST_TMPDIR/some-app" "some-app"
    run nodejs_app_config_is_template
    [ "$status" -ne 0 ]
}

@test "update_nodejs_app: unconfigured template skips without an error" {
    source_nodejs_app_functions
    write_nodejs_app_config "/opt/my-nodejs-app" "my-nodejs-app"
    run update_nodejs_app
    [ "$status" -eq 0 ]
    [[ "$output" == *"not configured"* ]]
    [[ "$output" != *"ERROR"* ]]
    [[ "$output" != *"Application directory not found"* ]]
    # No clone instructions for an app nobody asked sysupdate to manage.
    [[ "$output" != *"clone it somewhere"* ]]
}

@test "update_nodejs_app: a configured but absent app reports not installed, not failure" {
    source_nodejs_app_functions
    write_nodejs_app_config "$BATS_TEST_TMPDIR/absent-app" "absent-app"
    run update_nodejs_app
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not installed at"* ]]
    [[ "$output" == *"clone it somewhere"* ]]
    [[ "$output" != *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# update_postman: resolving the latest version
# ---------------------------------------------------------------------------

# Load the snippet's functions without its trailing entry call, keeping its own
# `../lib` lookup working.
source_postman_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/pkg/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/pkg/lib"
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_postman.sh" \
        > "$snippets_dir/update_postman.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_postman.sh"
    CONFIG_FILE="$REPO_ROOT/scripts/upgrade_snippets/postman.yaml"
}

# Fake curl: prints $STUB_CURL_BODY for a plain fetch, and for a ranged request
# (-r) writes STUB_TARBALL_FOR_RANGE's bytes to the -o file, failing when the
# requested range is below STUB_TARBALL_MIN_RANGE.
stub_curl() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/bash
range=""
out=""
prev=""
for arg in "$@"; do
    case "$prev" in
        -r) range="$arg" ;;
        -o) out="$arg" ;;
    esac
    prev="$arg"
done

if [ -z "$range" ]; then
    [ "${STUB_CURL_API_FAILS:-false}" = true ] && exit 22
    printf '%s' "$STUB_CURL_BODY"
    exit 0
fi

requested=${range#0-}
if [ "$requested" -lt "${STUB_TARBALL_MIN_RANGE:-0}" ]; then
    : > "$out"
    exit 0
fi
cp "$STUB_TARBALL_FOR_RANGE" "$out"
STUB
    chmod +x "$STUB_BIN/curl"
    PATH="$STUB_BIN:$PATH"
}

# A real (tiny) tarball holding the member the fallback reads.
make_postman_tarball() {
    local version="$1"
    local root="$BATS_TEST_TMPDIR/tarball/Postman/app/resources/app"
    mkdir -p "$root"
    echo "{\"version\": \"$version\"}" > "$root/package.json"
    tar -czf "$BATS_TEST_TMPDIR/postman.tar.gz" -C "$BATS_TEST_TMPDIR/tarball" Postman
    echo "$BATS_TEST_TMPDIR/postman.tar.gz"
}

@test "parse_postman_api_version: reads the version out of the API body" {
    source_postman_functions
    run parse_postman_api_version '{"version":"12.29.1"}'
    [ "$status" -eq 0 ]
    [ "$output" = "12.29.1" ]
}

@test "parse_postman_api_version: rejects a body with no usable version" {
    source_postman_functions
    run parse_postman_api_version '{"error":"nope"}'
    [ -z "$output" ]
}

@test "parse_postman_api_version: rejects a non-numeric version" {
    source_postman_functions
    run parse_postman_api_version '{"version":"latest"}'
    [ -z "$output" ]
}

@test "get_latest_tarball_version: takes the API answer without downloading" {
    source_postman_functions
    stub_curl
    export STUB_CURL_BODY='{"version":"12.29.1"}'
    run get_latest_tarball_version
    [ "$status" -eq 0 ]
    [ "$output" = "12.29.1" ]
}

@test "get_latest_tarball_version: falls back to the tarball when the API fails" {
    source_postman_functions
    stub_curl
    export STUB_CURL_API_FAILS=true
    STUB_TARBALL_FOR_RANGE=$(make_postman_tarball "12.30.0")
    export STUB_TARBALL_FOR_RANGE STUB_TARBALL_MIN_RANGE=0
    run get_latest_tarball_version
    [ "$status" -eq 0 ]
    [ "$output" = "12.30.0" ]
}

# The bug: one fixed window that no longer reaches package.json made the whole
# check report "could not determine latest version".
@test "get_latest_tarball_version: widens the window until the member is reachable" {
    source_postman_functions
    stub_curl
    export STUB_CURL_API_FAILS=true
    STUB_TARBALL_FOR_RANGE=$(make_postman_tarball "12.31.0")
    # Only the second window (50331648) is large enough.
    export STUB_TARBALL_FOR_RANGE STUB_TARBALL_MIN_RANGE=30000000
    run get_latest_tarball_version
    [ "$status" -eq 0 ]
    [ "$output" = "12.31.0" ]
}

@test "get_latest_tarball_version: fails when neither source answers" {
    source_postman_functions
    stub_curl
    export STUB_CURL_API_FAILS=true
    STUB_TARBALL_FOR_RANGE=$(make_postman_tarball "12.32.0")
    # Larger than every window the snippet tries.
    export STUB_TARBALL_FOR_RANGE STUB_TARBALL_MIN_RANGE=999999999
    run get_latest_tarball_version
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# vscode-insiders: post-install verification reads the dpkg version
# ---------------------------------------------------------------------------
#
# The deb installer always ends with verify_configured_update_result, which
# needs version.command/regex in the snippet's YAML. vscode_insiders.yaml had
# neither, so a successful install was reported as "Failed to verify active
# version". These tests run the REAL yaml against a stubbed dpkg-query.

stub_vscode_dpkg_version() {
    local stubdir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stubdir"
    printf '#!/bin/sh\nprintf "%%s" "$STUB_DPKG_VERSION"\n' > "$stubdir/dpkg-query"
    chmod +x "$stubdir/dpkg-query"
    export PATH="$stubdir:$PATH"
    export CONFIG_FILE="$REPO_ROOT/scripts/upgrade_snippets/vscode_insiders.yaml"
    export APP_DISPLAY_NAME="VSCode Insiders"
}

@test "vscode-insiders: get_current_version_from_config returns the full dpkg version" {
    stub_vscode_dpkg_version
    export STUB_DPKG_VERSION="1.140.0-1790270607"
    run get_current_version_from_config
    [ "$status" -eq 0 ]
    # Not "0-1790270607": an unanchored regex lets extract_version's leading .* eat "1."
    [ "$output" = "1.140.0-1790270607" ]
}

@test "vscode-insiders: verification passes once the installed build reaches the latest" {
    stub_vscode_dpkg_version
    export STUB_DPKG_VERSION="1.140.0-1790270607"
    run verify_configured_update_result "1.140.0-1790227310" "1.140.0-1790270607" "update completed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verified version: 1.140.0-1790270607"* ]]
    [[ "$output" != *"Failed to verify"* ]]
}

@test "vscode-insiders: verification fails when the installed build is still behind" {
    stub_vscode_dpkg_version
    export STUB_DPKG_VERSION="1.140.0-1790227310"
    run verify_configured_update_result "1.140.0-1790227310" "1.140.0-1790270607" "update completed"
    [ "$status" -ne 0 ]
    [[ "$output" == *"did not reach the expected version"* ]]
}

# ---------------------------------------------------------------------------
# bash: an unreachable git.savannah.gnu.org must degrade, not shout
# ---------------------------------------------------------------------------
#
# Savannah has multi-day outages, and many networks block the git protocol's
# port 9418 outright. The lookup used to run a bare `git ls-remote`, so git's
# own "errno=No route to host" lines landed in the run output with nothing
# naming bash, and the check ended in a red error for what is a retryable
# network condition. These tests run the REAL snippet against stub binaries.

source_bash_snippet_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/bashsnip/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/bashsnip/lib"
    cp "$REPO_ROOT/scripts/upgrade_snippets/bash.yaml" "$snippets_dir/"
    # Drop the trailing invocation so the functions can be sourced on their own.
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_bash.sh" \
        > "$snippets_dir/update_bash.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_bash.sh"
}

# Stub git and curl as real executables, NOT shell functions: the probes run
# under `timeout`, which execs the binary and would never see a function.
#
# The git stub answers for $STUB_GIT_OK_URL and fails like an unreachable host
# for everything else, writing the same shape of stderr git does.
stub_bash_remotes() {
    local stubdir="$BATS_TEST_TMPDIR/bashbin"
    mkdir -p "$stubdir"
    cat > "$stubdir/git" <<'STUB'
#!/bin/sh
url=$(eval echo "\${$#}")
if [ -n "$STUB_GIT_OK_URL" ] && [ "$url" = "$STUB_GIT_OK_URL" ]; then
    printf 'abc123\trefs/tags/bash-5.2\n'
    printf 'def456\trefs/tags/bash-5.3\n'
    printf 'def456\trefs/tags/bash-5.3^{}\n'
    exit 0
fi
echo "$url[0: 209.51.188.168]: errno=No route to host" >&2
echo "$url[1: 2001:470:142::168]: errno=Network is unreachable" >&2
echo "fatal: unable to connect to git.savannah.gnu.org:" >&2
exit 128
STUB
    cat > "$stubdir/curl" <<'STUB'
#!/bin/sh
if [ -n "$STUB_GNU_LISTING" ]; then
    cat "$STUB_GNU_LISTING"
    exit 0
fi
echo "curl: (28) Connection timed out" >&2
exit 28
STUB
    chmod +x "$stubdir/git" "$stubdir/curl"
    export PATH="$stubdir:$PATH"
}

# A directory index the way ftp.gnu.org serves one.
write_gnu_bash_listing() {
    cat > "$BATS_TEST_TMPDIR/gnu-bash-index.html" <<'HTML'
<a href="bash-5.1.tar.gz">bash-5.1.tar.gz</a>
<a href="bash-5.2.tar.gz">bash-5.2.tar.gz</a>
<a href="bash-5.3.tar.gz">bash-5.3.tar.gz</a>
<a href="bash-5.3.tar.gz.sig">bash-5.3.tar.gz.sig</a>
HTML
    export STUB_GNU_LISTING="$BATS_TEST_TMPDIR/gnu-bash-index.html"
}

@test "bash: the git remote answers and the highest series wins" {
    stub_bash_remotes
    source_bash_snippet_functions
    export STUB_GIT_OK_URL="git://git.savannah.gnu.org/bash.git"

    # Called directly, not under `run`: the lookup reports through globals, and
    # a subshell would discard them - which is why the snippet must not call it
    # in a command substitution either.
    get_latest_bash_version
    [ "$BASH_LATEST_VERSION" = "5.3" ]
    [ -z "$BASH_VERSION_LOOKUP_ERROR" ]
}

# The point of the change: git's connection noise is captured, and the run
# reports one summarised reason instead.
@test "bash: git connection errors never leak into the run output" {
    stub_bash_remotes
    source_bash_snippet_functions
    export STUB_GIT_OK_URL=""
    export QUIET_MODE=true
    enable_json_events

    run bash_version_check
    [[ "$output" != *"errno=No route to host"* ]]
    [[ "$output" != *"Network is unreachable"* ]]
    [[ "$output" == *"Could not reach any bash release source"* ]]
}

# A network miss is retryable, so it reports "unknown" - not a verdict on the
# installed bash, and not a bare failure.
@test "bash: an unreachable Savannah reports unknown, not an error" {
    stub_bash_remotes
    source_bash_snippet_functions
    export STUB_GIT_OK_URL=""
    export QUIET_MODE=true
    enable_json_events

    run bash_version_check
    [[ "$output" == *'"status":"unknown"'* ]]
    [[ "$output" == *'"latest_version":"unknown"'* ]]
    [[ "$output" != *'"status":"update_available"'* ]]
    # The installed version is still known, and still reported.
    [[ "$output" != *'"current_version":"unknown"'* ]]
    # Reported as a warning: nothing is broken, the sources just did not answer.
    [[ "$output" != *"[ERROR]"* ]]
    [[ "$output" != *'"line_type":"error"'* ]]
}

# Port 9418 blocked but 443 open: the same repository over https still answers.
@test "bash: falls back to https when the git protocol cannot connect" {
    stub_bash_remotes
    source_bash_snippet_functions
    export STUB_GIT_OK_URL="https://git.savannah.gnu.org/git/bash.git"

    get_latest_bash_version
    [ "$BASH_LATEST_VERSION" = "5.3" ]
}

# Savannah down altogether: the GNU release listing is on another host.
@test "bash: falls back to the GNU release listing when Savannah is down" {
    stub_bash_remotes
    write_gnu_bash_listing
    source_bash_snippet_functions
    export STUB_GIT_OK_URL=""

    get_latest_bash_version
    [ "$BASH_LATEST_VERSION" = "5.3" ]
}

@test "bash: with every source down the failure names the last reason" {
    stub_bash_remotes
    source_bash_snippet_functions
    export STUB_GIT_OK_URL=""

    ! get_latest_bash_version
    [ -z "$BASH_LATEST_VERSION" ]
    [[ "$BASH_VERSION_LOOKUP_ERROR" == *"ftp.gnu.org"* ]]
}

# An unreachable host that drops packets instead of refusing would otherwise
# hold the whole run; every probe runs under a timeout.
@test "bash: a hanging git remote is bounded by the probe timeout" {
    local stubdir="$BATS_TEST_TMPDIR/hangbin"
    mkdir -p "$stubdir"
    printf '#!/bin/sh\nsleep 30\n' > "$stubdir/git"
    chmod +x "$stubdir/git"
    export PATH="$stubdir:$PATH"
    source_bash_snippet_functions
    export SYSUPDATE_BASH_REMOTE_TIMEOUT=1
    # A missing function would "fail" the probe instantly and pass the timing
    # assertion below for the wrong reason.
    declare -F fetch_bash_version_from_git_remote

    local started=$SECONDS
    run fetch_bash_version_from_git_remote "git://git.savannah.gnu.org/bash.git"
    [ "$status" -ne 0 ]
    [ $((SECONDS - started)) -lt 10 ]
}

# ---------------------------------------------------------------------------
# claude-desktop: the version source must follow the install channel
# ---------------------------------------------------------------------------
#
# Claude Desktop now ships from Anthropic's own apt repository as well as from
# the community packaging on GitHub, whose releases trail it. Checking an
# apt-installed package against GitHub reported the installed version as
# "newer than latest release" on the dashboard. These tests run the REAL
# snippet against a stubbed dpkg/apt and a stubbed GitHub API.

source_claude_desktop_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/cd/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/cd/lib"
    cp "$REPO_ROOT/scripts/upgrade_snippets/claude_desktop.yaml" "$snippets_dir/"
    # Drop the trailing invocation so the functions can be sourced on their own.
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_claude_desktop.sh" \
        > "$snippets_dir/update_claude_desktop.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_claude_desktop.sh"

    # Pin apt index freshness. With a fresh index the apt candidate is the
    # authority and no repository index is fetched, which is what the
    # apt-channel tests below are about. Left pointing at the host's real
    # /var/lib/apt/lists, whether these tests reach the network would depend on
    # when the machine last ran `apt-get update`.
    stub_apt_lists 10
}

# dpkg reports $1 installed for claude-desktop, on amd64, maintained by $2
# (Anthropic's own build unless told otherwise).
#
# The format string matters: the snippet asks dpkg-query for ${Version} to get
# the installed version and for ${Maintainer} to tell Anthropic's build from
# the community packaging, and answering both with the same string would decide
# the channel by accident.
stub_claude_desktop_dpkg() {
    export STUB_CD_VERSION="$1"
    export STUB_CD_MAINTAINER="${2:-Anthropic PBC <support@anthropic.com>}"
    dpkg-query() {
        local arg fmt="" pkg=""
        for arg in "$@"; do
            case "$arg" in
                -f=*) fmt="${arg#-f=}" ;;
                -*) ;;
                *) pkg="$arg" ;;
            esac
        done
        [ "$pkg" = "claude-desktop" ] || return 1
        case "$fmt" in
            *Maintainer*) printf '%s' "$STUB_CD_MAINTAINER" ;;
            *) printf '%s' "$STUB_CD_VERSION" ;;
        esac
    }
    # --compare-versions must reach the real dpkg: stubbing it to a bare
    # `return 0` would make every version comparison answer "true".
    dpkg() {
        case "$1" in
            --print-architecture) echo "amd64" ;;
            *) command dpkg "$@" ;;
        esac
    }
}

# An Anthropic Packages index for the pool, listing $@ as published versions.
stub_claude_desktop_pool_index() {
    local versions=("$@")
    local body="" v
    for v in "${versions[@]}"; do
        body+="Package: claude-desktop
Version: $v
Filename: pool/main/c/claude-desktop/claude-desktop_${v}_amd64.deb

"
    done
    export STUB_CD_POOL_INDEX="$body"
    fetch_debian_repo_index() { printf '%s\n' "$STUB_CD_POOL_INDEX"; }
}

# A release carrying the community .deb for $1, the way the API returns it.
stub_claude_desktop_github() {
    export STUB_CD_RELEASE_VERSION="$1"
    curl() {
        printf '{"tag_name": "v3.3.4+claude%s", "assets": [{"browser_download_url": "https://github.com/aaddrick/claude-desktop-debian/releases/download/v3.3.4/claude-desktop_%s_amd64.deb"}]}' \
            "$STUB_CD_RELEASE_VERSION" "$STUB_CD_RELEASE_VERSION"
    }
}

@test "claude-desktop: an apt-served package is checked against the apt candidate" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.19675.1"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.19675.1
  Candidate: 2.19675.1
  Version table:
 *** 2.19675.1 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    # The community release trails Anthropic's repository; it must not be
    # consulted at all, let alone compared against.
    export CURL_MARKER="$BATS_TEST_TMPDIR/curl-was-called"
    curl() { : > "$CURL_MARKER"; return 1; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"up_to_date"'* ]]
    [[ "$output" == *'"latest_version":"2.19675.1"'* ]]
    [ ! -f "$CURL_MARKER" ]
}

# The regression itself: GitHub's newest .deb (2.9939.4) is numerically behind
# the apt-installed build (2.19675.1), which rendered as "newer than latest
# release" for a machine that was simply up to date.
@test "claude-desktop: an apt-served package is never reported ahead of GitHub" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.19675.1"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.19675.1
  Candidate: 2.19675.1
  Version table:
 *** 2.19675.1 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    stub_claude_desktop_github "2.9939.4"
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" != *'"status":"self_managed"'* ]]
    [[ "$output" != *"newer than latest"* ]]
}

@test "claude-desktop: an apt-served package behind the candidate needs an update" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.9939.4"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.9939.4
  Candidate: 2.19675.1
  Version table:
     2.19675.1 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
 *** 2.9939.4 500
        100 /var/lib/dpkg/status"
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"latest_version":"2.19675.1"'* ]]
}

# No apt source carries it -> it came from the community .deb, and that is the
# channel to compare against and install from.
@test "claude-desktop: a hand-installed community .deb still checks the GitHub release" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.7032.0" "aaddrick <packaging@example.invalid>"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.7032.0
  Candidate: 2.7032.0
  Version table:
 *** 2.7032.0 100
        100 /var/lib/dpkg/status"
    stub_claude_desktop_github "2.9939.4"
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"latest_version":"2.9939.4"'* ]]
}

# Installing the community .deb over an apt-managed install would swap the
# machine onto the other channel, and apt would overwrite it again next run.
@test "claude-desktop: the apt channel upgrades through apt, not dpkg -i" {
    source_claude_desktop_functions
    export APT_MARKER="$BATS_TEST_TMPDIR/apt-was-called"
    export WGET_MARKER="$BATS_TEST_TMPDIR/wget-was-called"
    CLAUDE_DESKTOP_CHANNEL="apt"
    CLAUDE_DESKTOP_PKG="claude-desktop"
    CLAUDE_DESKTOP_DEB_URL=""
    LATEST_VERSION="2.19675.1"
    APP_DISPLAY_NAME="Claude Desktop"
    sudo_can_run() { return 0; }
    update_via_package_manager() { : > "$APT_MARKER"; return 0; }
    wget() { : > "$WGET_MARKER"; return 0; }
    detect_installed_claude_desktop() { CLAUDE_DESKTOP_VERSION="2.19675.1"; return 0; }

    run perform_claude_desktop_update
    [ "$status" -eq 0 ]
    [ -f "$APT_MARKER" ]
    [ ! -f "$WGET_MARKER" ]
}

# ---------------------------------------------------------------------------
# claude-desktop: a stale apt index must not pass for an answer
# ---------------------------------------------------------------------------
#
# The regression: `apt-cache policy` is only as fresh as the last
# `apt-get update`, and --check-only and --snippet deliberately never run one.
# A machine five days past its last apt update reported an installed
# 2.26454.2 as "up to date" while the repository already published 2.31226.1.

@test "claude-desktop: a stale apt index is answered from the repository index" {
    source_claude_desktop_functions
    stub_apt_lists 86400
    stub_claude_desktop_dpkg "2.26454.2"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.26454.2
  Candidate: 2.26454.2
  Version table:
 *** 2.26454.2 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    claude_desktop_published_version() { echo "2.31226.1"; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"latest_version":"2.31226.1"'* ]]
}

# The published version is only ever allowed to move the answer forward. A
# candidate ahead of the index means another source serves the package too,
# and that is the version apt would install.
@test "claude-desktop: a candidate ahead of the repository index is kept" {
    source_claude_desktop_functions
    stub_apt_lists 86400
    stub_claude_desktop_dpkg "2.26454.2"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.26454.2
  Candidate: 2.40000.0
  Version table:
     2.40000.0 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
 *** 2.26454.2 500
        100 /var/lib/dpkg/status"
    claude_desktop_published_version() { echo "2.31226.1"; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"latest_version":"2.40000.0"'* ]]
}

# A held package could not be upgraded even if we reported the newer version,
# and this snippet never reports an update it cannot apply.
@test "claude-desktop: a held package is reported against the held candidate" {
    source_claude_desktop_functions
    stub_apt_lists 86400
    stub_claude_desktop_dpkg "2.26454.2"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.26454.2
  Candidate: 2.26454.2
  Version table:
 *** 2.26454.2 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    apt_package_is_held() { return 0; }
    claude_desktop_published_version() { echo "2.31226.1"; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"up_to_date"'* ]]
    [[ "$output" == *'"latest_version":"2.26454.2"'* ]]
}

# Unreachable repository: fall back to the candidate rather than reporting
# "unknown", but say out loud that it may be out of date.
@test "claude-desktop: an unreachable repository falls back to the candidate" {
    source_claude_desktop_functions
    stub_apt_lists 86400
    stub_claude_desktop_dpkg "2.26454.2"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.26454.2
  Candidate: 2.26454.2
  Version table:
 *** 2.26454.2 500
        500 https://downloads.claude.ai/claude-desktop/apt/stable stable/main amd64 Packages
        100 /var/lib/dpkg/status"
    claude_desktop_published_version() { return 1; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"latest_version":"2.26454.2"'* ]]
    [[ "$output" == *"may be out of date"* ]]
}

# ---------------------------------------------------------------------------
# claude-desktop: the apt-pool channel
# ---------------------------------------------------------------------------
#
# Anthropic documents installing the .deb without registering the repository
# (/etc/default/claude-desktop with CLAUDE_DESKTOP_ADD_REPO="false"). No apt
# source then serves the package, and the snippet used to fall through to the
# community GitHub packaging - whose releases trail the official repository by
# a whole major version, so an official 2.x build rendered as "newer than
# latest release" instead of an answer.

@test "claude-desktop: an official package with no apt source uses the pool" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2" "Anthropic PBC <support@anthropic.com>"
    stub_apt_cache_policy "claude-desktop:
  Installed: 2.26454.2
  Candidate: 2.26454.2
  Version table:
 *** 2.26454.2 100
        100 /var/lib/dpkg/status"
    stub_claude_desktop_pool_index "2.26454.2" "2.31226.1"
    # The community channel must not be consulted for an official build.
    export CURL_MARKER="$BATS_TEST_TMPDIR/curl-was-called"
    curl() { : > "$CURL_MARKER"; return 1; }
    export QUIET_MODE=true
    enable_json_events

    run update_claude_desktop
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"latest_version":"2.31226.1"'* ]]
    [ ! -f "$CURL_MARKER" ]
}

@test "claude_desktop_pool_asset: builds the pool download URL for the highest version" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2"
    CLAUDE_DESKTOP_PKG="claude-desktop"
    stub_claude_desktop_pool_index "2.26454.2" "2.31226.1" "2.19675.1"

    run claude_desktop_pool_asset "amd64"
    [ "$status" -eq 0 ]
    [ "$output" = "2.31226.1 https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_2.31226.1_amd64.deb" ]
}

# The Filename field is external input that becomes a download URL we then
# install as root. An index that aims it off the pool must be ignored, not
# followed (see DEFENSIVE_CODING_GUIDE).
@test "claude_desktop_pool_asset: rejects a Filename outside the pool" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2"
    CLAUDE_DESKTOP_PKG="claude-desktop"
    export STUB_CD_POOL_INDEX='Package: claude-desktop
Version: 9.9.9
Filename: https://evil.invalid/claude-desktop_9.9.9_amd64.deb

Package: claude-desktop
Version: 2.26454.2
Filename: pool/main/c/claude-desktop/claude-desktop_2.26454.2_amd64.deb
'
    fetch_debian_repo_index() { printf '%s\n' "$STUB_CD_POOL_INDEX"; }

    run claude_desktop_pool_asset "amd64"
    [ "$status" -eq 0 ]
    [[ "$output" == "2.26454.2 "* ]]
    [[ "$output" != *"evil.invalid"* ]]
}

@test "claude_desktop_pool_asset: rejects a Filename that walks out of the pool" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2"
    CLAUDE_DESKTOP_PKG="claude-desktop"
    export STUB_CD_POOL_INDEX='Package: claude-desktop
Version: 9.9.9
Filename: pool/../../../etc/claude-desktop_9.9.9_amd64.deb
'
    fetch_debian_repo_index() { printf '%s\n' "$STUB_CD_POOL_INDEX"; }

    run claude_desktop_pool_asset "amd64"
    [ "$status" -ne 0 ]
}

# A pool listing the other packaging variant must not be mistaken for ours.
@test "claude_desktop_pool_asset: ignores a different package in the pool" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2"
    CLAUDE_DESKTOP_PKG="claude-desktop"
    export STUB_CD_POOL_INDEX='Package: claude-desktop-unofficial
Version: 9.9.9
Filename: pool/main/c/claude-desktop/claude-desktop-unofficial_9.9.9_amd64.deb
'
    fetch_debian_repo_index() { printf '%s\n' "$STUB_CD_POOL_INDEX"; }

    run claude_desktop_pool_asset "amd64"
    [ "$status" -ne 0 ]
}

@test "claude_desktop_pool_asset: non-zero when the pool index is unreachable" {
    source_claude_desktop_functions
    CLAUDE_DESKTOP_PKG="claude-desktop"
    fetch_debian_repo_index() { return 1; }

    run claude_desktop_pool_asset "amd64"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# claude_desktop_package_is_official
# ---------------------------------------------------------------------------

@test "claude_desktop_package_is_official: true for Anthropic's own build" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2" "Anthropic PBC <support@anthropic.com>"
    run claude_desktop_package_is_official "claude-desktop"
    [ "$status" -eq 0 ]
}

@test "claude_desktop_package_is_official: false for the community packaging" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2" "aaddrick <packaging@example.invalid>"
    run claude_desktop_package_is_official "claude-desktop"
    [ "$status" -ne 0 ]
}

@test "claude_desktop_package_is_official: false when dpkg knows no such package" {
    source_claude_desktop_functions
    stub_claude_desktop_dpkg "2.26454.2"
    run claude_desktop_package_is_official "not-installed"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# android-studio: the installed build is compared against Google's feed
# ---------------------------------------------------------------------------
#
# The snippet used to report `self_managed` unconditionally with no latest
# version, on the premise that Google publishes no machine-readable feed. It
# does — updates.xml, the one the IDE's own updater polls — so a build a full
# release behind rendered on the dashboard as an INFO card with nothing to
# compare. These tests run the REAL snippet against a stubbed curl and a
# stubbed /opt install.

source_android_studio_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/as/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/as/lib"
    # Drop the trailing invocation so the functions can be sourced on their own.
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_android_studio.sh" \
        > "$snippets_dir/update_android_studio.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_android_studio.sh"
}

# A feed shaped like the real one: the newest release build is NOT first, a
# canary channel carries a higher number, and one release build number is
# malformed.
write_android_studio_feed() {
    cat > "$BATS_TEST_TMPDIR/updates.xml" <<'XML'
<?xml version='1.0' encoding='ASCII'?>
<products>
  <product name="Android Studio">
    <code>AI</code>
    <channel id="AI-1-release" majorVersion="1" name="Android Studio updates" status="release">
      <build apiVersion="AI-261.26222.65" number="AI-261.26222.65.2613.15948027" version="Quail 3">
        <message><![CDATA[<html>number="AI-999.999.999.999.999999999" in prose</html>]]></message>
      </build>
      <build apiVersion="AI-261.26222.65" number="AI-261.26222.65.2614.16379836" version="Quail 4 Patch 1"/>
      <build apiVersion="AI-261.26222.65" number="AI-truncated" version="Malformed"/>
    </channel>
    <channel id="AI-1-canary" majorVersion="1" name="Android Studio canary" status="eap">
      <build apiVersion="AI-262.10315.125" number="AI-262.10315.125.2622.16434108" version="Rabbit 2 Canary 2"/>
    </channel>
  </product>
</products>
XML
    export ANDROID_STUDIO_UPDATES_URL="$BATS_TEST_TMPDIR/updates.xml"
}

# Fake curl that serves the fixture feed, or fails like a network miss.
stub_android_studio_curl() {
    local stubdir="$BATS_TEST_TMPDIR/asbin"
    mkdir -p "$stubdir"
    cat > "$stubdir/curl" <<'STUB'
#!/bin/sh
[ "${STUB_AS_CURL_FAILS:-false}" = true ] && exit 22
cat "$ANDROID_STUDIO_UPDATES_URL"
STUB
    chmod +x "$stubdir/curl"
    export PATH="$stubdir:$PATH"
}

# A /opt/android-studio whose product-info.json reports build $1.
install_fake_android_studio() {
    local home="$BATS_TEST_TMPDIR/android-studio"
    mkdir -p "$home"
    printf '{\n  "name": "Android Studio",\n  "version": "%s",\n  "productCode": "AI"\n}\n' "$1" \
        > "$home/product-info.json"
    export ANDROID_STUDIO_HOME="$home"
}

@test "android-studio: latest build comes from the release channel, not canary" {
    write_android_studio_feed
    stub_android_studio_curl
    source_android_studio_functions
    run get_android_studio_latest_build
    [ "$status" -eq 0 ]
    # The canary build (262.x) is higher but belongs to another channel.
    [ "$output" = "AI-261.26222.65.2614.16379836" ]
}

@test "android-studio: the highest build wins regardless of feed order" {
    write_android_studio_feed
    stub_android_studio_curl
    source_android_studio_functions
    run extract_android_studio_channel_builds release < "$BATS_TEST_TMPDIR/updates.xml"
    [ "$status" -eq 0 ]
    # Listed second in the feed, and it must still be the one selected above.
    [[ "$output" == *"AI-261.26222.65.2614.16379836"* ]]
    # Prose inside <message> is not a build element.
    [[ "$output" != *"AI-999.999.999.999.999999999"* ]]
}

@test "android-studio: a malformed build number cannot become the latest" {
    write_android_studio_feed
    stub_android_studio_curl
    source_android_studio_functions
    run get_android_studio_latest_build
    [ "$output" != "AI-truncated" ]
    [[ "$output" =~ ^AI-[0-9]+(\.[0-9]+)+$ ]]
}

@test "android-studio: a newer build reports self_managed with both versions" {
    write_android_studio_feed
    stub_android_studio_curl
    install_fake_android_studio "AI-251.25410.109.2511.13752376"
    source_android_studio_functions
    export QUIET_MODE=true
    enable_json_events
    run update_android_studio
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"self_managed"'* ]]
    [[ "$output" == *'"current_version":"AI-251.25410.109.2511.13752376"'* ]]
    # The whole point of the change: a real latest, not "unknown".
    [[ "$output" == *'"latest_version":"AI-261.26222.65.2614.16379836"'* ]]
}

@test "android-studio: an installed build at the channel head reports up_to_date" {
    write_android_studio_feed
    stub_android_studio_curl
    install_fake_android_studio "AI-261.26222.65.2614.16379836"
    source_android_studio_functions
    export QUIET_MODE=true
    enable_json_events
    run update_android_studio
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"up_to_date"'* ]]
    [[ "$output" != *'"status":"self_managed"'* ]]
}

@test "android-studio: a build ahead of the channel is not reported as behind" {
    write_android_studio_feed
    stub_android_studio_curl
    # Someone running canary is ahead of the stable channel, not behind it.
    install_fake_android_studio "AI-262.10315.125.2622.16434108"
    source_android_studio_functions
    export QUIET_MODE=true
    enable_json_events
    run update_android_studio
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"up_to_date"'* ]]
}

@test "android-studio: an unreachable feed reports unknown, not a verdict" {
    write_android_studio_feed
    stub_android_studio_curl
    install_fake_android_studio "AI-251.25410.109.2511.13752376"
    source_android_studio_functions
    export QUIET_MODE=true STUB_AS_CURL_FAILS=true
    enable_json_events
    run update_android_studio
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"unknown"'* ]]
    [[ "$output" == *'"latest_version":"unknown"'* ]]
}

@test "android-studio: a missing install still reports not_installed" {
    write_android_studio_feed
    stub_android_studio_curl
    export ANDROID_STUDIO_HOME="$BATS_TEST_TMPDIR/absent"
    source_android_studio_functions
    export QUIET_MODE=true
    enable_json_events
    run update_android_studio
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"not_installed"'* ]]
}

# ---------------------------------------------------------------------------
# select_highest_dpkg_version
#
# dpkg's ordering, not sort -V's: the apt channel compares repository versions
# against an installed dpkg version, and sort -V gets "~" pre-releases and
# epochs wrong in exactly that comparison.
# ---------------------------------------------------------------------------

@test "select_highest_dpkg_version: picks the highest of several versions" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' 2.26454.2 2.31226.1 2.19675.1 2.31226.0)"
    [ "$status" -eq 0 ]
    [ "$output" = "2.31226.1" ]
}

@test "select_highest_dpkg_version: a tilde pre-release sorts below the release" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' '1.0~rc1' '1.0')"
    [ "$status" -eq 0 ]
    [ "$output" = "1.0" ]
}

@test "select_highest_dpkg_version: honours a Debian revision" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' '1.2.3-1' '1.2.3-2')"
    [ "$output" = "1.2.3-2" ]
}

@test "select_highest_dpkg_version: an epoch outranks a higher plain version" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' '9.9.9' '1:1.0')"
    [ "$output" = "1:1.0" ]
}

# The index is fetched from a remote repository, so anything that is not a
# plausible dpkg version is dropped rather than handed to dpkg.
@test "select_highest_dpkg_version: drops lines that are not versions" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' 'not a version' '$(touch /tmp/pwned)' '1.0' '')"
    [ "$status" -eq 0 ]
    [ "$output" = "1.0" ]
}

@test "select_highest_dpkg_version: returns non-zero when nothing is a version" {
    run select_highest_dpkg_version <<< "garbage"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "select_highest_dpkg_version: tolerates surrounding whitespace" {
    run select_highest_dpkg_version <<< "$(printf '%s\n' '  1.0  ' '2.0')"
    [ "$output" = "2.0" ]
}

# ---------------------------------------------------------------------------
# apt_index_age_seconds / apt_index_is_stale
#
# The freshness question behind the whole apt-channel fix: --check-only and
# --snippet never run `apt-get update`, so the cached index - and the candidate
# read from it - can be arbitrarily old.
# ---------------------------------------------------------------------------

# A fake /var/lib/apt/lists holding one cached index, aged by `touch -d`.
stub_apt_lists() {
    local age_seconds="${1:-0}"
    export APT_LISTS_DIR="$BATS_TEST_TMPDIR/lists"
    mkdir -p "$APT_LISTS_DIR"
    local f="$APT_LISTS_DIR/downloads.claude.ai_claude-desktop_apt_stable_dists_stable_main_binary-amd64_Packages"
    : > "$f"
    touch -d "@$(( $(date +%s) - age_seconds ))" "$f"
}

@test "apt_index_age_seconds: reports the age of a cached index" {
    stub_apt_lists 7200
    run apt_index_age_seconds "downloads.claude.ai"
    [ "$status" -eq 0 ]
    [ "$output" -ge 7190 ]
    [ "$output" -le 7210 ]
}

@test "apt_index_age_seconds: non-zero when no index for that host was fetched" {
    stub_apt_lists 0
    run apt_index_age_seconds "packages.mozilla.org"
    [ "$status" -ne 0 ]
}

@test "apt_index_age_seconds: non-zero when given no host" {
    stub_apt_lists 0
    run apt_index_age_seconds ""
    [ "$status" -ne 0 ]
}

@test "apt_index_is_stale: a just-fetched index is fresh" {
    stub_apt_lists 10
    run apt_index_is_stale "downloads.claude.ai" 3600
    [ "$status" -ne 0 ]
}

@test "apt_index_is_stale: an index past max-age is stale" {
    stub_apt_lists 7200
    run apt_index_is_stale "downloads.claude.ai" 3600
    [ "$status" -eq 0 ]
}

# A never-fetched index is the state in which the candidate deserves the least
# trust, so it must count as stale rather than as fresh.
@test "apt_index_is_stale: a never-fetched index counts as stale" {
    stub_apt_lists 10
    run apt_index_is_stale "downloads.claude.ai.other" 3600
    [ "$status" -eq 0 ]
}

@test "apt_index_is_stale: a non-numeric max-age falls back to the default" {
    stub_apt_lists 10
    run apt_index_is_stale "downloads.claude.ai" "not-a-number"
    [ "$status" -ne 0 ]
}

@test "apt_index_is_stale: defaults max-age when none is given" {
    stub_apt_lists 86400
    run apt_index_is_stale "downloads.claude.ai"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# apt_package_is_held
# ---------------------------------------------------------------------------

stub_apt_mark() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    printf '#!/bin/bash\nprintf "%%s\\n" %s\n' "$1" > "$STUB_BIN/apt-mark"
    chmod +x "$STUB_BIN/apt-mark"
    PATH="$STUB_BIN:$PATH"
}

@test "apt_package_is_held: true when apt-mark lists the package" {
    stub_apt_mark "'claude-desktop' 'other-pkg'"
    PATH="$STUB_BIN:$PATH" run apt_package_is_held "claude-desktop"
    [ "$status" -eq 0 ]
}

@test "apt_package_is_held: false when apt-mark lists nothing" {
    stub_apt_mark "''"
    PATH="$STUB_BIN:$PATH" run apt_package_is_held "claude-desktop"
    [ "$status" -ne 0 ]
}

# A substring match would read "claude-desktop-unofficial" as a hold on
# "claude-desktop" and silently stop reporting its updates.
@test "apt_package_is_held: false for a package whose name is only a prefix" {
    stub_apt_mark "'claude-desktop-unofficial'"
    PATH="$STUB_BIN:$PATH" run apt_package_is_held "claude-desktop"
    [ "$status" -ne 0 ]
}

@test "apt_package_is_held: false when given no package name" {
    stub_apt_mark "'claude-desktop'"
    PATH="$STUB_BIN:$PATH" run apt_package_is_held ""
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# fetch_debian_repo_index / fetch_debian_repo_latest_version
#
# Reading the repository's own index over HTTPS is what lets a read-only scan
# answer correctly without sudo and without `apt-get update`.
# ---------------------------------------------------------------------------

# Fake curl serving a Packages body for the plain URL, the gzipped one, or
# neither, per STUB_INDEX_MODE.
stub_index_curl() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/bash
url="${!#}"
case "${STUB_INDEX_MODE:-plain}" in
    plain)  case "$url" in *.gz) exit 22 ;; esac ;;
    gz)     case "$url" in *.gz) ;; *) exit 22 ;; esac ;;
    none)   exit 22 ;;
esac
if [ "${url##*.}" = "gz" ]; then
    printf '%s' "$STUB_INDEX_BODY" | gzip -c
else
    printf '%s' "$STUB_INDEX_BODY"
fi
STUB
    chmod +x "$STUB_BIN/curl"
    export STUB_INDEX_BODY='Package: claude-desktop
Version: 2.26454.2
Filename: pool/main/c/claude-desktop/claude-desktop_2.26454.2_amd64.deb

Package: claude-desktop
Version: 2.31226.1
Filename: pool/main/c/claude-desktop/claude-desktop_2.31226.1_amd64.deb
'
}

@test "fetch_debian_repo_index: returns the plain Packages body" {
    stub_index_curl
    STUB_INDEX_MODE=plain PATH="$STUB_BIN:$PATH" run fetch_debian_repo_index \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main amd64
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version: 2.31226.1"* ]]
}

@test "fetch_debian_repo_index: falls back to the gzipped index" {
    stub_index_curl
    STUB_INDEX_MODE=gz PATH="$STUB_BIN:$PATH" run fetch_debian_repo_index \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main amd64
    [ "$status" -eq 0 ]
    [[ "$output" == *"Version: 2.31226.1"* ]]
}

@test "fetch_debian_repo_index: non-zero when the repository is unreachable" {
    stub_index_curl
    STUB_INDEX_MODE=none PATH="$STUB_BIN:$PATH" run fetch_debian_repo_index \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main amd64
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "fetch_debian_repo_index: non-zero when a coordinate is missing" {
    stub_index_curl
    PATH="$STUB_BIN:$PATH" run fetch_debian_repo_index \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main ""
    [ "$status" -ne 0 ]
}

@test "fetch_debian_repo_latest_version: highest version the index publishes" {
    stub_index_curl
    STUB_INDEX_MODE=plain PATH="$STUB_BIN:$PATH" run fetch_debian_repo_latest_version \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main amd64
    [ "$status" -eq 0 ]
    [ "$output" = "2.31226.1" ]
}

@test "fetch_debian_repo_latest_version: non-zero when the index cannot be read" {
    stub_index_curl
    STUB_INDEX_MODE=none PATH="$STUB_BIN:$PATH" run fetch_debian_repo_latest_version \
        "https://downloads.claude.ai/claude-desktop/apt/stable" stable main amd64
    [ "$status" -ne 0 ]
}

# A trailing slash on the base URL must not produce a "//dists" path.
@test "fetch_debian_repo_index: tolerates a trailing slash on the base URL" {
    stub_index_curl
    cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/bash
printf '%s' "${!#}"
STUB
    chmod +x "$STUB_BIN/curl"
    PATH="$STUB_BIN:$PATH" run fetch_debian_repo_index \
        "https://downloads.claude.ai/claude-desktop/apt/stable/" stable main amd64
    [ "$output" = "https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages" ]
}
