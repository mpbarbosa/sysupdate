#!/bin/bash
# Stub sysupdate script for backend bridge integration tests.
# Emits a canned JSON event stream to stderr and exits cleanly.
# Ignores all arguments, except `--snippet slow`, which keeps the run alive
# for a few seconds so tests can observe an in-progress run.

cat >&2 <<'EOF'
{"event_type":"run.started","run_id":"stub-run-001","timestamp":"2026-01-01T00:00:00.000Z","sequence":1,"pid":12345,"module":"stub","function":"main","source":"stub:main"}
{"event_type":"terminal.line","line_type":"info","message":"Stub run","timestamp":"2026-01-01T00:00:00.001Z","sequence":2,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}
{"event_type":"summary.updates","summary_name":"version_check","target":"Stub App","status":"up_to_date","current_version":"1.0.0","latest_version":"1.0.0","timestamp":"2026-01-01T00:00:00.002Z","sequence":3,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}
EOF

if [[ " $* " == *" --snippet slow "* ]]; then
  sleep 5
fi

# Exercises the bridge's sudo askpass relay without sudo: call the helper the
# way sudo would (argv[1] = prompt, password on stdout, exit 1 = cancelled) and
# report what came back as terminal.line events.
emit_line() {
  printf '{"event_type":"terminal.line","line_type":"info","message":"%s","timestamp":"2026-01-01T00:00:00.010Z","sequence":10,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}\n' "$1" >&2
}

ask() {
  # Direct child (no subshell) so the helper's parent pid is this script's,
  # like repeated attempts inside one sudo invocation.
  local label="$1" out="$2"
  if "$SUDO_ASKPASS" "[sudo: authenticate] Password: " > "$out"; then
    emit_line "$label:$(cat "$out")"
  else
    emit_line "$label:cancelled"
  fi
}

if [[ " $* " == *" --snippet sudo "* ]]; then
  tmp=$(mktemp -d)
  ask askpass-1 "$tmp/pw1"
  # Same parent asks again: the bridge must treat the first answer as rejected.
  ask askpass-2 "$tmp/pw2"
  # A different parent (a new sudo invocation): answered from the cache, no prompt.
  bash -c '"$SUDO_ASKPASS" "[sudo: authenticate] Password: " > "$1"; true' _ "$tmp/pw3"
  emit_line "askpass-3:$(cat "$tmp/pw3")"
  rm -rf "$tmp"
fi

if [[ " $* " == *" --snippet sudo-cancel "* ]]; then
  tmp=$(mktemp -d)
  ask askpass-1 "$tmp/pw1"
  rm -rf "$tmp"
fi

echo '{"event_type":"run.completed","exit_code":0,"timestamp":"2026-01-01T00:00:00.003Z","sequence":4,"pid":12345,"run_id":"stub-run-001","module":"stub","function":"main","source":"stub:main"}' >&2

exit 0
