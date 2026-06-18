#!/usr/bin/env bats
#
# Integration tests: CLI JSON event stream
#
# Runs system_update.sh with fixture snippets (no network, no system mutations)
# and verifies the JSON event protocol on stderr.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURE_SNIPPETS="$(dirname "$BATS_TEST_FILENAME")/fixtures/snippets"
SYSUPDATE="$REPO_ROOT/scripts/system_update.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run sysupdate against a fixture snippet and capture stderr as JSON events.
# Sets $output to stderr only (stdout suppressed).
run_snippet_events() {
    local id="$1"
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet '$id' --check-only --json-events 2>&1 1>/dev/null"
}

# Assert that $1 is a parseable JSON object (via stdin to avoid argv quoting).
is_valid_json() {
    echo "$1" | python3 -c "import json,sys; o=json.loads(sys.stdin.read()); assert isinstance(o,dict)" 2>/dev/null
}

# ---------------------------------------------------------------------------
# run.started event
# ---------------------------------------------------------------------------

@test "run.started event is emitted" {
    run_snippet_events "fixture-current"
    echo "$output" | grep -q '"event_type":"run.started"'
}

@test "run.started event is valid JSON" {
    run_snippet_events "fixture-current"
    local started_line
    started_line=$(echo "$output" | grep '"event_type":"run.started"' | head -1)
    [ -n "$started_line" ]
    is_valid_json "$started_line"
}

@test "run.started event has run_id and timestamp fields" {
    run_snippet_events "fixture-current"
    local started_line
    started_line=$(echo "$output" | grep '"event_type":"run.started"' | head -1)
    echo "$started_line" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'run_id' in d, 'missing run_id'
assert 'timestamp' in d, 'missing timestamp'
assert d['run_id'], 'run_id is empty'
"
}

# ---------------------------------------------------------------------------
# All JSON-looking lines on stderr are parseable
# (Non-JSON lines — colored section headers, etc. — are allowed on stderr.)
# ---------------------------------------------------------------------------

@test "every JSON-looking stderr line is parseable" {
    run_snippet_events "fixture-current"
    while IFS= read -r line; do
        [[ "$line" == "{"* ]] || continue
        is_valid_json "$line"
    done <<< "$output"
}

# ---------------------------------------------------------------------------
# summary.updates event — fixture-current (up to date)
# ---------------------------------------------------------------------------

@test "fixture-current emits summary.updates with status=up_to_date" {
    run_snippet_events "fixture-current"
    local summary_line
    summary_line=$(echo "$output" | grep '"event_type":"summary.updates"' | head -1)
    [ -n "$summary_line" ]
    echo "$summary_line" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('status') == 'up_to_date', f'expected up_to_date, got {d.get(\"status\")}'
"
}

@test "summary.updates has target, current_version, latest_version fields" {
    run_snippet_events "fixture-current"
    local summary_line
    summary_line=$(echo "$output" | grep '"event_type":"summary.updates"' | head -1)
    echo "$summary_line" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
for field in ('target', 'current_version', 'latest_version', 'status'):
    assert field in d, f'missing field: {field}'
"
}

# ---------------------------------------------------------------------------
# summary.updates event — fixture-outdated (update available)
# ---------------------------------------------------------------------------

@test "fixture-outdated emits summary.updates with status=update_available" {
    run_snippet_events "fixture-outdated"
    local summary_line
    summary_line=$(echo "$output" | grep '"event_type":"summary.updates"' | head -1)
    [ -n "$summary_line" ]
    echo "$summary_line" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('status') == 'update_available', f'expected update_available, got {d.get(\"status\")}'
"
}

@test "fixture-outdated reports correct version delta" {
    run_snippet_events "fixture-outdated"
    local summary_line
    summary_line=$(echo "$output" | grep '"event_type":"summary.updates"' | head -1)
    echo "$summary_line" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('current_version') == '1.0.0', f'unexpected current: {d.get(\"current_version\")}'
assert d.get('latest_version') == '2.0.0', f'unexpected latest: {d.get(\"latest_version\")}'
"
}

# ---------------------------------------------------------------------------
# CHECK_ONLY_MODE must not invoke the update callback
# ---------------------------------------------------------------------------

@test "check-only mode does not invoke update callback for outdated fixture" {
    # Redirect stderr to /dev/null so only stdout is captured; the update
    # callback (echo FIXTURE_UPDATE_CALLED) writes to stdout.
    run bash -c "SYSUPDATE_SNIPPETS_DIR='$FIXTURE_SNIPPETS' '$SYSUPDATE' --snippet fixture-outdated --check-only --json-events 2>/dev/null"
    [[ "$output" != *"FIXTURE_UPDATE_CALLED"* ]]
}
