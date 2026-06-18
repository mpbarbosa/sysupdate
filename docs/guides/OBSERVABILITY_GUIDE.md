# Observability Guide

Observability in `sysupdate` means every CLI run emits a structured, queryable
JSON event stream that the backend bridge, log history, and dashboard can
consume without re-running or re-attaching.

## Goal

Ensure every significant state transition, prompt, version check result, and
failure is captured in the structured JSON event stream — so that the web
dashboard, CI runs, and log history can reconstruct exactly what happened
during any run without access to the running process.

## How the event system works in this repo

The CLI emits structured JSON to **stderr** when `SYSUPDATE_JSON_EVENTS=true`
(set by `--json-events` or by the backend bridge via `SYSUPDATE_JSON_EVENTS`
env var). Every JSON line is emitted by `emit_event` in `scripts/lib/core_lib.sh`.

```
CLI (stderr) → backend bridge (web/backend/server.js)
             → parses each stderr line as JSON
             → broadcasts snapshot via WebSocket to web/src/App.tsx
             → writes run.completed to ~/.local/state/sysupdate/run-history.jsonl
```

The `run_id` field is the correlation ID: it is generated once at run start and
included in every event for that run.

## Event schema

Every event has these base fields:

| Field | Description |
| --- | --- |
| `event_type` | Dot-namespaced type: `run.started`, `terminal.line`, `summary.updates`, `prompt.requested`, `run.completed`, `run.failed`, `log.entry` |
| `timestamp` | ISO 8601 with timezone offset |
| `sequence` | Integer, monotonically increasing within a run |
| `pid` | Process ID of the CLI process |
| `run_id` | Correlation ID for the run — present on every event |
| `module` | Script file name (`update_firefox.sh`, `apt_manager.sh`, …) |
| `function` | Calling function name |
| `source` | `module:function` shorthand |

Additional fields are added per event type. The `summary.updates` event adds
`summary_name`, `target`, `status`, `current_version`, `latest_version`.
The `terminal.line` event adds `line_type` and `message`.

## Emitting events in Bash

Use these helpers from `core_lib.sh`:

```bash
# General-purpose structured event
emit_event "event_type_here" "key1" "value1" "key2" "value2"

# Version check result (wraps emit_event with standard summary fields)
emit_summary_event "version_check" \
    "target" "Firefox" \
    "status" "update_available" \
    "current_version" "$CURRENT_VERSION" \
    "latest_version" "$LATEST_VERSION"
```

`compare_and_report_versions` in `upgrade_utils.sh` calls `emit_summary_event`
automatically — snippets that use it get observability for free.

`print_status`, `print_success`, `print_warning`, and `print_error` each call
`emit_event` with `event_type: terminal.line` automatically when
`SYSUPDATE_JSON_EVENTS=true`.

## Required rules

### 1. Every version check emits a `summary.updates` event

All snippets that check for updates must emit a `summary.updates` event with
`status` set to one of `up_to_date`, `update_available`, `ahead_of_latest`,
or `unknown`. Use `compare_and_report_versions` — it handles this automatically.

Do not write a snippet that prints version info to stdout only. The backend
bridge reads only stderr; the web dashboard depends on `summary.updates` to
populate the update inventory.

### 2. `run_id` must be present on every event

`emit_event` adds `run_id` automatically from the `RUN_ID` global. Do not
call `emit_event` before `RUN_ID` is set (it is set in `system_update.sh`
at run start). Snippets sourced by `source_upgrade_snippets` inherit it.

### 3. Every snippet failure emits an observable signal

If a snippet exits non-zero or catches an error, the run eventually emits
`run.failed` with `exit_code`. But within a snippet, if an update step fails,
use `print_error` — this emits a `terminal.line` event with `line_type: error`
so the dashboard shows it in the correct color and the log records it.

Do not use `echo` for error messages inside snippets — it goes to stdout and
bypasses the event stream.

### 4. No sensitive data in events

Do not emit passwords, tokens, API keys, or user credentials in any event
field. The log history file is world-readable by the local user.

### 5. Backend bridge must not re-implement event logic

`web/backend/server.js` reads and routes events — it must not duplicate
version-check logic or emit fake events. If a new event type is needed,
add it to `core_lib.sh`, not to the bridge.

## `terminal.line` line types

The `line_type` field controls color and icon in the dashboard:

| `line_type` | Bash helper | Dashboard appearance |
| --- | --- | --- |
| `info` | `print_status` | Cyan info icon |
| `success` | `print_success` | Emerald check |
| `warning` | `print_warning` | Amber warning |
| `error` | `print_error` | Magenta error |
| `section_header` | `print_section_header` | Bold section divider |
| `operation_header` | `print_operation_header` | Dimmer sub-header |

## Review heuristics

### Event coverage test

Does every new snippet call `compare_and_report_versions`? If a snippet
determines whether something needs updating but never calls this function,
the version check result is invisible to the dashboard and run history.

### Correlation test

Does every event in the run share the same `run_id`? If a snippet generates
its own ad-hoc `run_id` or omits it, the bridge will still parse the event
but the log history correlations break.

### Sensitive data test

Do any event fields contain values that came from a credential file, an API
response with auth tokens, or environment variables like `AWS_SECRET_KEY`?
Review snippet code that calls external APIs or reads config files.

### Backend bridge test

Does `server.js` modify `event_type` values or add new event types that the
CLI never emits? It should not. The bridge routes events; it does not invent them.

## Positive signals

- Every snippet produces at least one `summary.updates` event per run.
- `run_id` appears in every JSON line in the event stream.
- The dashboard's update inventory populates without manual configuration.
- `emit_summary_event` status values (`up_to_date`, `update_available`) are
  consistent across all snippets.
- A new snippet added by an LLM uses `compare_and_report_versions` and
  inherits observability automatically.

## Warning signs

- A snippet that prints version info with `echo` instead of `print_status`.
- A snippet that exits without calling `compare_and_report_versions` or
  `emit_summary_event` — the dashboard shows nothing for that tool.
- `web/backend/server.js` constructing synthetic events with hardcoded
  `event_type` strings.
- Events with fields containing file paths from `~/.config/` that could
  expose local directory structure unnecessarily.

## Related guides

- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md) — the event
  emission belongs in the Bash core and snippet layer; the bridge is the
  adapter that routes events outward.
- [INTEGRATION_TEST_GUIDE.md](./INTEGRATION_TEST_GUIDE.md) — `tests/integration/`
  uses `--json-events` to verify that events are emitted correctly at real
  boundaries.
- [ERROR_HANDLING_GUIDE.md](./ERROR_HANDLING_GUIDE.md) — every snippet error
  should use `print_error`, which produces a `terminal.line/error` event.

## Summary checklist

- [ ] Every snippet calls `compare_and_report_versions` (or `emit_summary_event`)
      to emit a `summary.updates` event.
- [ ] All events include `run_id`.
- [ ] `print_error` (not raw `echo`) is used for error output inside snippets.
- [ ] No sensitive data appears in any event field.
- [ ] The backend bridge does not invent event types that the CLI does not emit.
- [ ] `line_type` values match the available set from `core_lib.sh`.
- [ ] New snippets are tested with `--json-events` to confirm correct events.
