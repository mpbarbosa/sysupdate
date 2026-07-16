# CLAUDE.md — web/backend/

Two files implement the Node.js bridge between the CLI and the web dashboard:

| File | Role |
| --- | --- |
| `server.js` | Effectful: spawns child process, manages HTTP routes, WebSocket, in-memory state |
| `utils.js` | Pure: `sanitizeSnippetId`, `parseJsonEvent`, `formatUptime`, `buildBootstrapPayload` |

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

## Run backend tests

```bash
node --test tests/backend/server.test.mjs
```

## Guides for this directory

- [NODE_MODULE_GUIDE.md](../../docs/guides/NODE_MODULE_GUIDE.md) — pure/effectful split rules, the four exported utils functions
- [ERROR_HANDLING_GUIDE.md](../../docs/guides/ERROR_HANDLING_GUIDE.md) — child process error handling, swallow test, 400 vs 500
- [OBSERVABILITY_GUIDE.md](../../docs/guides/OBSERVABILITY_GUIDE.md) — JSON event schema the bridge parses from stderr
- [DEFENSIVE_CODING_GUIDE.md](../../docs/guides/DEFENSIVE_CODING_GUIDE.md) — validating HTTP request bodies at the route boundary (`sanitizeSnippetId` → 400), and file/JSONL reads (`readLogHistory`)
