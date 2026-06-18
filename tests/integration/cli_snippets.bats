#!/usr/bin/env bats
#
# Integration tests: snippet discovery and SYSUPDATE_SNIPPETS_DIR override

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURE_SNIPPETS="$(dirname "$BATS_TEST_FILENAME")/fixtures/snippets"
SYSUPDATE="$REPO_ROOT/scripts/system_update.sh"

# ---------------------------------------------------------------------------
# --list-snippets with SYSUPDATE_SNIPPETS_DIR override
# ---------------------------------------------------------------------------

@test "--list-snippets discovers fixture snippets via env override" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --list-snippets"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "fixture-current"
    echo "$output" | grep -q "fixture-outdated"
}

@test "--list-snippets shows snippet names alongside IDs" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --list-snippets"
    echo "$output" | grep -q "Fixture (Current)"
    echo "$output" | grep -q "Fixture (Outdated)"
}

@test "--list-snippets does not list real snippets when env override is set" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --list-snippets"
    # The real snippet directory contains 'rtk', 'firefox', etc.
    # With the override pointing to fixtures, none of those should appear.
    [[ "$output" != *"rtk"* ]]
}

# ---------------------------------------------------------------------------
# --snippet filter with SYSUPDATE_SNIPPETS_DIR override
# ---------------------------------------------------------------------------

@test "--snippet fixture-current only runs that snippet" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet fixture-current --check-only --json-events 2>&1 1>/dev/null"
    # fixture-current event present
    echo "$output" | grep -q '"target":"Fixture Current"'
    # fixture-outdated event absent
    [[ "$output" != *'"target":"Fixture Outdated"'* ]]
}

@test "--snippet fixture-outdated only runs that snippet" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet fixture-outdated --check-only --json-events 2>&1 1>/dev/null"
    echo "$output" | grep -q '"target":"Fixture Outdated"'
    [[ "$output" != *'"target":"Fixture Current"'* ]]
}

@test "exit code is 0 for fixture-current in check-only mode" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet fixture-current --check-only 2>/dev/null"
    [ "$status" -eq 0 ]
}
