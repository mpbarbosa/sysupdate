#!/usr/bin/env bats
#
# Tests for scripts/lib/upgrade_utils.sh npm-health helpers
# Covers: npm_output_indicates_corruption, npm_global_modules_dir

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    FIXTURES_DIR="$(dirname "$BATS_TEST_FILENAME")/fixtures"
    export NO_COLOR=1
    # upgrade_utils.sh sources core_lib.sh internally
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/upgrade_utils.sh"
}

# ---------------------------------------------------------------------------
# npm_output_indicates_corruption
# ---------------------------------------------------------------------------

@test "npm corruption: detects 'undefined' variant from real log fixture" {
    run npm_output_indicates_corruption "$(cat "$FIXTURES_DIR/npm_corrupt_stderr.txt")"
    [ "$status" -eq 0 ]
}

@test "npm corruption: detects '#<Object>' variant (mismatched major)" {
    run npm_output_indicates_corruption \
        "npm error TypeError: Class extends value #<Object> is not a constructor or null"
    [ "$status" -eq 0 ]
}

@test "npm corruption: detects signature regardless of surrounding noise" {
    run npm_output_indicates_corruption \
        "starting...
some other line
Class extends value undefined is not a constructor or null
trailing line"
    [ "$status" -eq 0 ]
}

@test "npm corruption: healthy npm output is not flagged" {
    run npm_output_indicates_corruption "Verified 1234 tarballs in cache"
    [ "$status" -ne 0 ]
}

@test "npm corruption: unrelated npm error is not flagged" {
    run npm_output_indicates_corruption \
        "npm error code E404
npm error 404 Not Found - GET https://registry.npmjs.org/nope"
    [ "$status" -ne 0 ]
}

@test "npm corruption: empty input is not flagged" {
    run npm_output_indicates_corruption ""
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# npm_global_modules_dir
# ---------------------------------------------------------------------------

@test "npm global dir: derives prefix/lib/node_modules from npm-cli.js path" {
    run npm_global_modules_dir "/opt/tools/lib/node_modules/npm/bin/npm-cli.js"
    [ "$status" -eq 0 ]
    [ "$output" = "/opt/tools/lib/node_modules" ]
}
