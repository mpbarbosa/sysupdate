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
