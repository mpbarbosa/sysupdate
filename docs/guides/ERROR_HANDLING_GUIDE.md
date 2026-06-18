# Error Handling Guide

Errors in `sysupdate` span three layers with different failure models: Bash
(exit codes + trap), Node.js backend bridge (try/catch + child process events),
and TypeScript frontend (component error states). This guide defines how each
layer handles failures so that errors are observable, not silent.

## Goal

Ensure every failure is classified, propagated with context, and produces an
observable signal — so that a run that fails for any reason is visible in the
dashboard, the log history, and the CLI output, not silently discarded.

## Error taxonomy for this repo

| Class | Definition | Where it occurs | Handling rule |
| --- | --- | --- | --- |
| Tool not found | Required binary (`snap`, `apt`, `curl`) absent | Snippet startup | `print_warning`, skip gracefully, emit `summary.updates/unknown` |
| Version check failure | Cannot determine current or latest version | Snippet `compare_and_report_versions` | `print_error`, emit `summary.updates/unknown`, return non-zero |
| Update failure | Update command returns non-zero | Snippet update callback | `print_error`, return non-zero from snippet, `run.failed` event eventually |
| Validation error | Bad user input (snippetId, prompt response) | `sanitizeSnippetId`, `prompt_input` | Reject at boundary; 400 from backend; fallback to default in Bash |
| Infrastructure error | Child process spawn failure, file I/O error | `server.js` `startRun`, log history read | Log via `addTerminalLine`, emit `bridge.error` WebSocket message |
| Programming error | Assertion violation, null dereference, type mismatch | Any layer | Fail fast; do not catch to recover |

## Bash layer

### Exit codes are the Bash error contract

`compare_and_report_versions` returns: `0` = up to date, `2` = update
available, non-zero for errors. `check_updates_available` and other
library functions return non-zero on failure. Callers must check exit codes
and propagate failures.

### Use `print_error` for observable failures

Do not use raw `echo` for error messages inside snippets. `print_error`
writes to stderr, emits a `terminal.line/error` JSON event when
`SYSUPDATE_JSON_EVENTS=true`, and ensures the bridge and dashboard see the
failure.

```bash
if ! command -v snap > /dev/null 2>&1; then
    print_warning "snap not found — skipping snap update"
    return 0
fi
```

```bash
if ! update_rtk_binary; then
    print_error "RTK update failed"
    return 1
fi
```

### Tool-not-found failures should be warnings, not errors

If an optional tool is absent, warn and return 0 — a missing tool is not a
fatal run failure. If a required tool is absent, error and return non-zero.

### Validation at prompt boundaries

`prompt_input` reads the `SYSUPDATE_PROMPT_INPUT` file and falls back to a
default. After reading a value that may have been fed from an outer context
(e.g., "y" from a yes/no prompt re-delivered to a method selector), validate
and fall back:

```bash
case "$method" in
    v|V|b|B|s|S|p|P) ;;
    *) method="$default" ;;  # fallback when SYSUPDATE_PROMPT_INPUT delivers wrong value
esac
```

## Node.js backend layer (web/backend/server.js)

### Child process error handling

`startRun` attaches both `error` (spawn failure) and `close` (exit code) event
handlers. Both must produce an observable signal:

```javascript
activeChild.on('error', (error) => {
    currentRun.status = 'failed';
    addTerminalLine(`Failed to start sysupdate: ${error.message}`, 'error', 'bridge');
    broadcast({ type: 'bridge.error', payload: { message: error.message } });
    broadcastSnapshot('bridge.error');
});

activeChild.on('close', (code) => {
    // code !== 0 → status already set to 'failed' by run.failed event,
    // or set here as fallback
});
```

Neither handler may silently swallow the failure.

### HTTP route error handling

Every route handler is inside a `try/catch`. The catch block calls `sendJson`
with status 500 — this is the correct infrastructure error boundary. Do not
let `readRequestJson`, `readLogHistory`, or `startRun` throw unhandled
exceptions.

Validation errors (bad `snippetId`) are 400 responses — not 500. They are
expected failures at the input boundary, not infrastructure failures.

### Log history read failure

`readLogHistory` returns an empty array if the log file does not exist
(`existsSync` check). If the file is malformed (bad JSON), the `map(JSON.parse)`
will throw — this must be caught at the route handler level and return an empty
`logs` array rather than a 500.

## TypeScript frontend layer (web/src/)

### Run status error states

`BackendRunSnapshot.status` includes `'failed'`. The UI must render a distinct
error state when `status === 'failed'`, not silently show the last good state.

### WebSocket disconnection

If the WebSocket closes unexpectedly, the UI should reflect a "disconnected"
state rather than showing stale data. Reconnection logic or a visible stale
indicator prevents silent data gaps.

### No silent swallows in event handlers

`ws.onmessage = (event) => { ... }` — if JSON parsing fails or the message
shape is unexpected, log to console and continue. Do not let a bad message
crash the message handler and leave the WebSocket unresponsive.

## Review heuristics

### Swallow test

Does every `catch` block in `server.js` call `sendJson`, `addTerminalLine`, or
`broadcast`? Any catch that returns silently is a swallow.

### Observable failure test

If a snippet fails (returns non-zero), does the dashboard show a `failed` or
`error` state? Run `bash scripts/system_update.sh --snippet rtk --check-only`
with `rtk` not installed and verify the terminal output shows the error.

### Validation boundary test

Does `POST /api/runs/check-only` with `{ snippetId: "bad snippet!" }` return
400 with an error message? Does it return 400 for `"../etc/passwd"`?
Run `node --test tests/backend/server.test.mjs` to confirm.

### Tool-absent test

Does a snippet that requires an optional tool (`snap`, `cargo`, `npm`) handle
the case where that tool is not installed — without crashing the entire run?

## Positive signals

- A snippet run on a machine without the target tool prints a warning and exits
  0, not a crash.
- `run.failed` events appear in the log history for genuinely failed runs.
- `POST /api/runs/check-only` with invalid input returns 400, not 500.
- Every `catch` block in `server.js` produces a log line or broadcasts an error.
- The dashboard renders a visible error state when `status === 'failed'`.

## Warning signs

- A snippet that uses `command -v foo` but does not check its exit code.
- A catch block in `server.js`: `catch (e) { }` with no sendJson or broadcast.
- `readLogHistory` without a try/catch around `JSON.parse`.
- A `useEffect` error handler in `App.tsx` that calls `console.log` and then
  does nothing.
- A tool-not-found condition that throws instead of returning non-zero.

## Related guides

- [OBSERVABILITY_GUIDE.md](./OBSERVABILITY_GUIDE.md) — every error that is
  not re-thrown must produce a structured signal (`print_error` or
  `addTerminalLine`).
- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md) — infrastructure
  errors (child process, file I/O) are wrapped at the backend bridge adapter
  layer and do not surface to the frontend as raw Node.js error types.
- [UNIT_TEST_GUIDE.md](./UNIT_TEST_GUIDE.md) — every declared validation error
  case in `sanitizeSnippetId` has a corresponding Vitest test.
- [INTEGRATION_TEST_GUIDE.md](./INTEGRATION_TEST_GUIDE.md) — backend bridge
  integration tests verify the 400 responses for invalid input.

## Summary checklist

- [ ] Every Bash error uses `print_error` (not `echo`) so it enters the event
      stream.
- [ ] Tool-not-found in a snippet produces a `print_warning` and returns 0.
- [ ] `prompt_input` results are validated before use when the value is
      consumed in a different context than intended.
- [ ] Every `catch` block in `server.js` produces a signal — no silent swallows.
- [ ] HTTP validation errors return 400; infrastructure errors return 500.
- [ ] The frontend renders a visible error state when `status === 'failed'`.
- [ ] `readLogHistory` handles malformed JSONL without a 500 response.
