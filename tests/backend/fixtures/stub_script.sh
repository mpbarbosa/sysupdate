#!/bin/bash
# Stub sysupdate script for backend bridge integration tests.
# Emits a canned JSON event stream to stderr and exits cleanly.
# Ignores all arguments.

cat >&2 <<'EOF'
{"event_type":"run.started","run_id":"stub-run-001","timestamp":"2026-01-01T00:00:00.000Z","sequence":1,"pid":12345,"module":"stub","function":"main","source":"stub:main"}
{"event_type":"terminal.line","line_type":"info","message":"Stub run","timestamp":"2026-01-01T00:00:00.001Z","sequence":2,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}
{"event_type":"summary.updates","summary_name":"version_check","target":"Stub App","status":"up_to_date","current_version":"1.0.0","latest_version":"1.0.0","timestamp":"2026-01-01T00:00:00.002Z","sequence":3,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}
{"event_type":"run.completed","exit_code":0,"timestamp":"2026-01-01T00:00:00.003Z","sequence":4,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}
EOF

exit 0
