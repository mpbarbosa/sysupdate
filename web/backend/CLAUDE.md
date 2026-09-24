# CLAUDE.md — web/backend/

Two files implement the Node.js bridge between the CLI and the web dashboard:

| File | Role |
| --- | --- |
| `server.js` | Effectful: spawns child process, manages HTTP routes, WebSocket, in-memory state, sudo askpass relay |
| `utils.js` | Pure: `sanitizeSnippetId`, `mapTerminalType`, `stripAnsi`, `trimArray`, `isLoopbackHost`, `shellQuote`, `parseSudoPasswordRequest` |
| `sudo_askpass.mjs` | The `SUDO_ASKPASS` program sudo runs inside the child: forwards the prompt to `server.js` over a unix socket and prints the answer |

## Key rules for this directory

- Dependency direction: `server.js` → `utils.js`; never reverse
- `utils.js` must stay pure — no `node:fs`, no `node:child_process`, no `http` imports
- Every `catch` block in `server.js` must produce a signal: `sendJson`, `addTerminalLine`, or `broadcast`
- HTTP validation errors (bad snippetId) → 400; infrastructure errors → 500
- `readLogHistory` must handle missing file (return `[]`) and malformed JSONL (catch `JSON.parse` throws)
- JSON events come from **stderr** of the child process; stdout lines are raw terminal output
- `SYSUPDATE_SCRIPT_PATH` env var overrides the CLI path for test isolation
- `SYSUPDATE_WEB_HOST` / `SYSUPDATE_WEB_PORT` control the server bind address (default `127.0.0.1:4174`)
- `SYSUPDATE_LOG_FILE` / `SYSUPDATE_LOG_LIMIT` control log history
- `POST /api/shutdown` is the only route that ends the process: 409 while a run is active unless `{ force: true }`; it broadcasts `bridge.shutdown` before `shutdown()` runs, and `shutdown()` is idempotent with a 2s hard-exit cap for idle keep-alive connections
- Sudo askpass relay: the child has no TTY, so `server.js` sets `SUDO_ASKPASS` to a generated wrapper (0700 temp dir, one per bridge process) that runs `sudo_askpass.mjs`; the CLI's `enable_sudo_askpass_shim` makes every `sudo` call use it. A request surfaces as `run.sudoPrompt` (`requested` → `resolved` / `cancelled` / `expired`) in snapshots; `POST /api/runs/sudo-password` with `{ requestId, password }` or `{ requestId, cancel: true }` answers it (400 malformed, 404 no such pending prompt). The password lives only in the run's in-memory `sudo` state (never in snapshots, terminal lines or logs), is reused for later sudo invocations in the same run, and is wiped when the child exits. The same sudo pid asking twice means rejection → prompt again with `rejected: true`. Only enabled on a loopback `SYSUPDATE_WEB_HOST` (`SYSUPDATE_SUDO_RELAY=false` disables it); `bootstrap.backend.supports` then lists `sudo-askpass`

## Run backend tests

```bash
node --test tests/backend/server.test.mjs
```

## Guides for this directory

- [NODE_MODULE_GUIDE.md](../../docs/guides/NODE_MODULE_GUIDE.md) — pure/effectful split rules, the four exported utils functions
- [ERROR_HANDLING_GUIDE.md](../../docs/guides/ERROR_HANDLING_GUIDE.md) — child process error handling, swallow test, 400 vs 500
- [OBSERVABILITY_GUIDE.md](../../docs/guides/OBSERVABILITY_GUIDE.md) — JSON event schema the bridge parses from stderr
- [DEFENSIVE_CODING_GUIDE.md](../../docs/guides/DEFENSIVE_CODING_GUIDE.md) — validating HTTP request bodies at the route boundary (`sanitizeSnippetId` → 400), and file/JSONL reads (`readLogHistory`)
