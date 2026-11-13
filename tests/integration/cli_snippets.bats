#!/usr/bin/env bats
#
# Integration tests: snippet discovery and SYSUPDATE_SNIPPETS_DIR override

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURE_SNIPPETS="$(dirname "$BATS_TEST_FILENAME")/fixtures/snippets"
# Holds update_fixture_failing.sh (returns 1) and update_fixture_next.sh
# (succeeds, and sorts after it), kept out of FIXTURE_SNIPPETS so the other
# suites never run a deliberately failing snippet.
FAILING_SNIPPETS="$(dirname "$BATS_TEST_FILENAME")/fixtures/snippets_failing"
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

# ---------------------------------------------------------------------------
# summary events carry the producing snippet's id
# ---------------------------------------------------------------------------
#
# Consumers need the id to re-run exactly one snippet (`--snippet <id>`). No
# snippet passes it: source_snippet_isolated sets SYSUPDATE_CURRENT_SNIPPET_ID
# from each file's own `# SNIPPET_ID:` header, and emit_summary_event attaches
# it. The fixtures below never mention snippet_id, which is the point.

@test "version_check summaries carry the snippet id that produced them" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --check-only --json-events -q 2>&1 1>/dev/null"
    echo "$output" | grep -q '"snippet_id":"fixture-outdated","target":"Fixture Outdated"'
    echo "$output" | grep -q '"snippet_id":"fixture-current","target":"Fixture Current"'
}

@test "each summary carries its own snippet id, not the previously sourced one" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --check-only --json-events -q 2>&1 1>/dev/null"
    # Snippets are sourced into the orchestrator's own shell, so a leaked id
    # would tag every later snippet's summary with the first one's id.
    [[ "$output" != *'"snippet_id":"fixture-blocked","target":"Fixture Current"'* ]]
    [[ "$output" != *'"snippet_id":"fixture-current","target":"Fixture Outdated"'* ]]
}

@test "a filtered run tags the summary with the filtered snippet id" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet fixture-outdated --check-only --json-events 2>&1 1>/dev/null"
    echo "$output" | grep -q '"snippet_id":"fixture-outdated"'
}

# ---------------------------------------------------------------------------
# a snippet whose update fails must reach the exit code
# ---------------------------------------------------------------------------
#
# The bug, found after a real Postman update failed at its sudo backup step:
# source_upgrade_snippets threw away each snippet's status (the print_status
# after it became the function's return value) and every snippet call site
# ended in a hardcoded `exit 0`. The failed run exited 0 and handle_run_exit
# wrote it to run-history as "success", so the dashboard and the log both read
# a green result for an update that had not happened.

@test "a snippet whose update fails makes the filtered run exit non-zero" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --snippet fixture-failing -q 2>&1"
    [ "$status" -ne 0 ]
}

@test "a snippet that succeeds still exits 0" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --snippet fixture-next -q 2>&1"
    [ "$status" -eq 0 ]
}

@test "a failing snippet names itself instead of failing silently" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --snippet fixture-failing -q 2>&1"
    echo "$output" | grep -q "fixture-failing"
}

# A failure must not abort the pass: the remaining snippets still run, and the
# non-zero status is reported once at the end. update_fixture_next.sh sorts
# after update_fixture_failing.sh in the directory glob, so its event is only
# present if the loop carried on.
@test "a failing snippet does not stop the snippets after it" {
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --check-only --json-events -q 2>&1 1>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q '"target":"Fixture Next"'
}

@test "run history records a failed snippet run as failed, not success" {
    local log="$BATS_TEST_TMPDIR/run-history.jsonl"
    run bash -c "SYSUPDATE_STATE_DIR='$BATS_TEST_TMPDIR/state' SYSUPDATE_LOG_FILE='$log' SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --snippet fixture-failing -q >/dev/null 2>&1"
    [ "$status" -ne 0 ]
    [ -f "$log" ]
    grep -q '"status":"failed"' "$log"
    [[ "$(cat "$log")" != *'"status":"success"'* ]]
}

@test "run history still records a successful snippet run as success" {
    local log="$BATS_TEST_TMPDIR/run-history.jsonl"
    run bash -c "SYSUPDATE_STATE_DIR='$BATS_TEST_TMPDIR/state' SYSUPDATE_LOG_FILE='$log' SYSUPDATE_SNIPPETS_DIR='$FAILING_SNIPPETS' '$SYSUPDATE' --snippet fixture-next -q >/dev/null 2>&1"
    [ "$status" -eq 0 ]
    grep -q '"status":"success"' "$log"
}
