#!/usr/bin/env bats
#
# Tests for scripts/upgrade_snippets/update_bbcsdl.sh
#
# The guards that matter here are the destructive ones. The update replaces the
# installation directory wholesale, so two decisions have to be right or the
# snippet damages something: which directory is the installation, and whether
# the downloaded archive is actually newer than what is installed. Both have a
# test below that goes red when the guard is deleted.
#
# Nothing here touches the network or a real installation: curl and uname are
# shadowed on PATH, and every path is inside $BATS_TEST_TMPDIR.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    exec 0</dev/null
    FIXTURES_DIR="$(dirname "$BATS_TEST_FILENAME")/fixtures"
    export NO_COLOR=1
    QUIET_MODE=true
    CHECK_ONLY_MODE=true
    VERBOSE_MODE=false
}

# Load the snippet's functions without its trailing entry call, keeping its own
# `../lib` lookup working. The snippet turns on `set -u -o pipefail` for its own
# code; they are turned back off afterwards so they do not leak into BATS.
source_bbcsdl_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/pkg/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/pkg/lib"
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_bbcsdl.sh" \
        > "$snippets_dir/update_bbcsdl.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_bbcsdl.sh"
    set +u +o pipefail
    CONFIG_FILE="$REPO_ROOT/scripts/upgrade_snippets/bbcsdl.yaml"
    APP_DISPLAY_NAME="BBC BASIC for SDL 2.0"
}

# A file that passes the ELF magic check and carries the version banner the
# real build stamps into itself.
make_fake_bbcsdl() {
    local path="$1"
    local version="$2"
    mkdir -p "$(dirname "$path")"
    printf '\177ELF\002\001\001\000' > "$path"
    printf 'BBC BASIC for Linux version %s\000' "$version" >> "$path"
    chmod +x "$path"
}

# A complete installation tree: the executable plus the archive's own markers.
make_bbcsdl_install() {
    local dir="$1"
    local version="$2"
    make_fake_bbcsdl "$dir/bbcsdl" "$version"
    mkdir -p "$dir/lib"
    touch "$dir/bbcsdl.bbc"
}

stub_bin() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    PATH="$STUB_BIN:$PATH"
}

# curl that serves a local file instead of the vendor site.
stub_curl_with_file() {
    stub_bin
    cat > "$STUB_BIN/curl" <<STUB
#!/bin/bash
cat "$1"
STUB
    chmod +x "$STUB_BIN/curl"
}

stub_uname() {
    stub_bin
    cat > "$STUB_BIN/uname" <<STUB
#!/bin/bash
echo "$1"
STUB
    chmod +x "$STUB_BIN/uname"
}

# ---------------------------------------------------------------------------
# is_bbcsdl_install_dir / get_bbcsdl_install_dir
#
# This is the guard that decides what gets backed up and replaced. A stray copy
# of the executable in a bin directory must never make that directory look like
# an installation, or the update would replace the bin directory itself.
# ---------------------------------------------------------------------------

@test "is_bbcsdl_install_dir: a bin directory holding only the executable is refused" {
    source_bbcsdl_functions
    local bindir="$BATS_TEST_TMPDIR/usr-local-bin"
    make_fake_bbcsdl "$bindir/bbcsdl" "1.44a"
    touch "$bindir/ls" "$bindir/grep"

    if is_bbcsdl_install_dir "$bindir"; then
        echo "a plain bin directory was accepted as the installation directory"
        return 1
    fi
}

@test "is_bbcsdl_install_dir: the same directory is accepted once an archive marker is there" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt-bbcsdl"
    make_fake_bbcsdl "$dir/bbcsdl" "1.44a"

    if is_bbcsdl_install_dir "$dir"; then
        echo "accepted before any marker existed"
        return 1
    fi

    mkdir -p "$dir/lib"
    run is_bbcsdl_install_dir "$dir"
    [ "$status" -eq 0 ]
}

@test "is_bbcsdl_install_dir: bbcsdl.bbc alone is marker enough" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt-bbcsdl"
    make_fake_bbcsdl "$dir/bbcsdl" "1.44a"
    touch "$dir/bbcsdl.bbc"

    run is_bbcsdl_install_dir "$dir"
    [ "$status" -eq 0 ]
}

@test "is_bbcsdl_install_dir: markers without the executable are refused" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/not-an-install"
    mkdir -p "$dir/lib"
    touch "$dir/bbcsdl.bbc"

    if is_bbcsdl_install_dir "$dir"; then
        echo "accepted a directory with no bbcsdl executable"
        return 1
    fi
}

@test "get_bbcsdl_install_dir: refuses a bin directory and accepts a real installation" {
    source_bbcsdl_functions
    local bindir="$BATS_TEST_TMPDIR/bin"
    make_fake_bbcsdl "$bindir/bbcsdl" "1.44a"

    if get_bbcsdl_install_dir "$bindir/bbcsdl"; then
        echo "resolved a bin directory as the installation directory"
        return 1
    fi

    local dir="$BATS_TEST_TMPDIR/install"
    make_bbcsdl_install "$dir" "1.44a"
    run get_bbcsdl_install_dir "$dir/bbcsdl"
    [ "$status" -eq 0 ]
    [ "$output" = "$dir" ]
}

# ---------------------------------------------------------------------------
# resolve_bbcsdl_binary
#
# bbcsdl loads lib/ relative to its own location, so what goes on PATH is
# normally a wrapper that execs the real executable. readlink does not see
# through one.
# ---------------------------------------------------------------------------

@test "resolve_bbcsdl_binary: follows a wrapper script to the real executable" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt/bbcsdl"
    make_bbcsdl_install "$dir" "1.44a"
    stub_bin
    printf '#!/bin/sh\nexec "%s/bbcsdl" "$@"\n' "$dir" > "$STUB_BIN/bbcsdl"
    chmod +x "$STUB_BIN/bbcsdl"

    run resolve_bbcsdl_binary
    [ "$status" -eq 0 ]
    [ "$output" = "$dir/bbcsdl" ]
}

@test "resolve_bbcsdl_binary: expands \$HOME in a wrapper script" {
    source_bbcsdl_functions
    HOME="$BATS_TEST_TMPDIR/home"
    local dir="$HOME/.local/opt/bbcsdl"
    make_bbcsdl_install "$dir" "1.44a"
    stub_bin
    printf '#!/bin/sh\nexec "$HOME/.local/opt/bbcsdl/bbcsdl" "$@"\n' > "$STUB_BIN/bbcsdl"
    chmod +x "$STUB_BIN/bbcsdl"

    run resolve_bbcsdl_binary
    [ "$status" -eq 0 ]
    [ "$output" = "$dir/bbcsdl" ]
}

@test "resolve_bbcsdl_binary: an executable already on PATH is used as-is" {
    source_bbcsdl_functions
    stub_bin
    make_fake_bbcsdl "$STUB_BIN/bbcsdl" "1.44a"

    run resolve_bbcsdl_binary
    [ "$status" -eq 0 ]
    [ "$output" = "$STUB_BIN/bbcsdl" ]
}

@test "resolve_bbcsdl_binary: a wrapper pointing nowhere resolves to nothing" {
    source_bbcsdl_functions
    stub_bin
    printf '#!/bin/sh\nexec "/nonexistent/bbcsdl" "$@"\n' > "$STUB_BIN/bbcsdl"
    chmod +x "$STUB_BIN/bbcsdl"

    run resolve_bbcsdl_binary
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# get_current_bbcsdl_version
#
# bbcsdl has no --version flag, so the version is read out of the file rather
# than by running it.
# ---------------------------------------------------------------------------

@test "get_current_bbcsdl_version: reads the version banner out of the executable" {
    source_bbcsdl_functions
    make_fake_bbcsdl "$BATS_TEST_TMPDIR/bbcsdl" "1.44a"

    run get_current_bbcsdl_version "$BATS_TEST_TMPDIR/bbcsdl"
    [ "$status" -eq 0 ]
    [ "$output" = "1.44a" ]
}

@test "get_current_bbcsdl_version: keeps both digits of a two-digit minor" {
    source_bbcsdl_functions
    make_fake_bbcsdl "$BATS_TEST_TMPDIR/bbcsdl" "12.34b"

    run get_current_bbcsdl_version "$BATS_TEST_TMPDIR/bbcsdl"
    [ "$output" = "12.34b" ]
}

@test "get_current_bbcsdl_version: a file with no banner yields nothing" {
    source_bbcsdl_functions
    printf '\177ELF\002\001\001\000not this program at all' > "$BATS_TEST_TMPDIR/other"

    run get_current_bbcsdl_version "$BATS_TEST_TMPDIR/other"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "is_valid_bbcsdl_version: accepts a release version and rejects anything else" {
    source_bbcsdl_functions
    run is_valid_bbcsdl_version "1.44a"
    [ "$status" -eq 0 ]
    run is_valid_bbcsdl_version "1.44"
    [ "$status" -eq 0 ]

    local candidate
    for candidate in "1.44abc" "Mbytes" "" "21.6 Mbytes" "v1.44a"; do
        run is_valid_bbcsdl_version "$candidate"
        [ "$status" -ne 0 ]
    done
}

# ---------------------------------------------------------------------------
# get_latest_bbcsdl_version
#
# The vendor changelog is the version source, because the upstream repository
# publishes no releases or tags and its master branch runs ahead of the
# published archive.
# ---------------------------------------------------------------------------

@test "get_latest_bbcsdl_version: the fixture's first changelog row is NOT the newest release" {
    # Guards the test below: if the fixture were ever reordered into descending
    # order, "take the first row" and "take the highest" would agree and the
    # next test would stop proving anything.
    local first
    first=$(tr -d '\r' < "$FIXTURES_DIR/bbcsdl_changelog.html" \
        | grep -oE '<TD NOWRAP>(<A[^>]*>)?[0-9]+\.[0-9]+[a-z]?(</A>)?</TD>' \
        | grep -oE '[0-9]+\.[0-9]+[a-z]?' | head -1)
    [ "$first" = "1.43c" ]
}

@test "get_latest_bbcsdl_version: takes the highest changelog version, not the first row" {
    source_bbcsdl_functions
    stub_curl_with_file "$FIXTURES_DIR/bbcsdl_changelog.html"

    run get_latest_bbcsdl_version
    [ "$status" -eq 0 ]
    [ "$output" = "1.44a" ]
}

@test "get_latest_bbcsdl_version: download sizes in the same page are not mistaken for versions" {
    source_bbcsdl_functions
    stub_curl_with_file "$FIXTURES_DIR/bbcsdl_changelog.html"

    run get_latest_bbcsdl_version
    [ "$output" != "28.6" ]
    [ "$output" != "21.6" ]
}

@test "get_latest_bbcsdl_version: a page with no changelog table yields nothing" {
    source_bbcsdl_functions
    echo "<HTML><BODY>site is down for maintenance</BODY></HTML>" > "$BATS_TEST_TMPDIR/empty.html"
    stub_curl_with_file "$BATS_TEST_TMPDIR/empty.html"

    run get_latest_bbcsdl_version
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# verify_staged_bbcsdl_version
#
# The download URL is a fixed "current edition" path, so the archive behind it
# and the version the changelog announces refresh independently.
# ---------------------------------------------------------------------------

@test "verify_staged_bbcsdl_version: refuses an archive no newer than what is installed" {
    source_bbcsdl_functions
    local stage="$BATS_TEST_TMPDIR/stage"
    make_fake_bbcsdl "$stage/bbcsdl" "1.44a"
    CURRENT_VERSION="1.44a"
    LATEST_VERSION="1.45a"

    run verify_staged_bbcsdl_version "$stage"
    [ "$status" -ne 0 ]
    [[ "$output" == *"has not refreshed the download yet"* ]]
}

@test "verify_staged_bbcsdl_version: refuses an archive older than what is installed" {
    source_bbcsdl_functions
    local stage="$BATS_TEST_TMPDIR/stage"
    make_fake_bbcsdl "$stage/bbcsdl" "1.43c"
    CURRENT_VERSION="1.44a"
    LATEST_VERSION="1.45a"

    run verify_staged_bbcsdl_version "$stage"
    [ "$status" -ne 0 ]
}

@test "verify_staged_bbcsdl_version: accepts a genuine upgrade" {
    source_bbcsdl_functions
    local stage="$BATS_TEST_TMPDIR/stage"
    make_fake_bbcsdl "$stage/bbcsdl" "1.44a"
    CURRENT_VERSION="1.43c"
    LATEST_VERSION="1.44a"

    run verify_staged_bbcsdl_version "$stage"
    [ "$status" -eq 0 ]
}

@test "verify_staged_bbcsdl_version: warns when the archive lags the announcement but still upgrades" {
    source_bbcsdl_functions
    local stage="$BATS_TEST_TMPDIR/stage"
    make_fake_bbcsdl "$stage/bbcsdl" "1.44a"
    CURRENT_VERSION="1.43c"
    LATEST_VERSION="1.45a"

    run verify_staged_bbcsdl_version "$stage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"while the vendor announced 1.45a"* ]]
}

@test "verify_staged_bbcsdl_version: refuses an archive whose version cannot be read" {
    source_bbcsdl_functions
    local stage="$BATS_TEST_TMPDIR/stage"
    mkdir -p "$stage"
    printf '\177ELF\002\001\001\000nothing useful here' > "$stage/bbcsdl"
    CURRENT_VERSION="1.43c"
    LATEST_VERSION="1.44a"

    run verify_staged_bbcsdl_version "$stage"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# get_bbcsdl_asset_url
# ---------------------------------------------------------------------------

@test "get_bbcsdl_asset_url: maps each supported CPU to its published edition" {
    source_bbcsdl_functions

    stub_uname "x86_64"
    run get_bbcsdl_asset_url
    [ "$output" = "https://www.bbcbasic.co.uk/bbcsdl/bbclinux.zip" ]

    stub_uname "i686"
    run get_bbcsdl_asset_url
    [ "$output" = "https://www.bbcbasic.co.uk/bbcsdl/bbclinux32.zip" ]

    stub_uname "aarch64"
    run get_bbcsdl_asset_url
    [ "$output" = "https://www.bbcbasic.co.uk/bbcsdl/bbc-rpi64.zip" ]

    stub_uname "armv7l"
    run get_bbcsdl_asset_url
    [ "$output" = "https://www.bbcbasic.co.uk/bbcsdl/bbc-rpi.zip" ]
}

@test "get_bbcsdl_asset_url: a CPU with no published edition fails rather than guessing" {
    source_bbcsdl_functions
    stub_uname "riscv64"

    run get_bbcsdl_asset_url
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# Privileges and bounded backups
# ---------------------------------------------------------------------------

@test "get_bbcsdl_privilege_prefix: an installation the user owns needs no sudo" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt/bbcsdl"
    make_bbcsdl_install "$dir" "1.44a"

    run get_bbcsdl_privilege_prefix "$dir"
    [ "$output" = "" ]
}

@test "get_bbcsdl_privilege_prefix: an installation under a read-only parent uses sudo" {
    source_bbcsdl_functions
    local parent="$BATS_TEST_TMPDIR/readonly"
    mkdir -p "$parent/bbcsdl"
    chmod 0555 "$parent"

    run get_bbcsdl_privilege_prefix "$parent/bbcsdl"
    [ "$output" = "run_with_sudo" ]

    chmod 0755 "$parent"
}

@test "prune_bbcsdl_backups: keeps the newest generations without invoking sudo" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt/bbcsdl"
    make_bbcsdl_install "$dir" "1.44a"

    # Created in an order that disagrees with their timestamps, so an
    # implementation trusting creation order or mtime would pick differently.
    local stamp
    for stamp in 20260303_000000 20260101_000000 20260404_000000 20260202_000000; do
        mkdir -p "$dir.backup.$stamp/lib"
    done
    mkdir -p "$dir.backup.keepme"

    local sudo_log="$BATS_TEST_TMPDIR/sudo.log"
    : > "$sudo_log"
    run_with_sudo() { echo "$*" >> "$sudo_log"; command "$@"; }

    prune_bbcsdl_backups "$dir" "$dir.backup.20260404_000000"

    [ ! -s "$sudo_log" ]
    [ -d "$dir.backup.20260404_000000" ]
    [ -d "$dir.backup.20260303_000000" ]
    [ ! -d "$dir.backup.20260202_000000" ]
    [ ! -d "$dir.backup.20260101_000000" ]
    [ -d "$dir.backup.keepme" ]
}

@test "prune_bbcsdl_backups: never removes the backup for the run in flight" {
    source_bbcsdl_functions
    local dir="$BATS_TEST_TMPDIR/opt/bbcsdl"
    make_bbcsdl_install "$dir" "1.44a"

    # Retention 0 would otherwise take every one of them.
    local config="$BATS_TEST_TMPDIR/bbcsdl-retention.yaml"
    printf 'update:\n  backup_retention: 0\n' > "$config"
    CONFIG_FILE="$config"

    local stamp
    for stamp in 20260101_000000 20260202_000000; do
        mkdir -p "$dir.backup.$stamp"
    done

    prune_bbcsdl_backups "$dir" "$dir.backup.20260202_000000"

    [ -d "$dir.backup.20260202_000000" ]
    [ ! -d "$dir.backup.20260101_000000" ]
}

@test "get_bbcsdl_backup_retention: falls back to 2 when the config says nothing usable" {
    source_bbcsdl_functions
    local config="$BATS_TEST_TMPDIR/bbcsdl-empty.yaml"
    printf 'update:\n  backup_retention: "many"\n' > "$config"
    CONFIG_FILE="$config"

    run get_bbcsdl_backup_retention
    [ "$output" = "2" ]
}

# ---------------------------------------------------------------------------
# Shipped configuration
# ---------------------------------------------------------------------------

@test "bbcsdl.yaml: the shipped config carries the keys the snippet reads" {
    source_bbcsdl_functions

    run get_config "application.display_name"
    [ "$output" = "BBC BASIC for SDL 2.0" ]

    local key
    for key in version.binary_regex version.binary_version_regex version.version_regex \
        version.changelog_url version.changelog_cell_regex update.install_dir_markers \
        update.executables update.default_install_dir update.backup_retention; do
        run get_config "$key"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
    done
}

@test "bbcsdl.yaml: the version source is the vendor site, not the upstream repository" {
    # include/version.h on rtrussell/BBCSDL master tracks the development head
    # and runs ahead of the published archive, so checking against it would
    # report an update the download channel cannot deliver.
    source_bbcsdl_functions

    run get_config "version.changelog_url"
    [[ "$output" == https://www.bbcbasic.co.uk/* ]]

    run get_config "version.source"
    [ "$output" = "vendor_changelog" ]
}
