# Node.js Module Guide

This guide defines module structure expectations for `web/backend/` — the
local backend bridge between the CLI and the web dashboard.

## Current backend structure

```
web/backend/
  server.js    — HTTP + WebSocket server; orchestrates runs, routes events
  utils.js     — pure utility functions; no I/O, no side effects
  utils.test.js — Vitest unit tests for utils.js
```

`server.js` is the entry point and the only module with side effects. `utils.js`
is a pure utility layer imported by `server.js` and independently testable.

## Goal

Keep the backend bridge organized so that:
- pure logic is testable without starting the HTTP server
- `server.js` responsibilities (spawning, routing, WebSocket broadcast) are
  distinct from utility logic (parsing, sanitizing, transforming)
- adding a new route or event handler does not require understanding unrelated utilities

## Required rules

### 1. `utils.js` must stay pure

`utils.js` exports four pure functions:

| Function | What it does |
| --- | --- |
| `mapTerminalType(lineType)` | Maps CLI `line_type` string to dashboard display type |
| `stripAnsi(text)` | Removes ANSI escape codes from a string |
| `trimArray(items, limit)` | Returns last N items from an array |
| `sanitizeSnippetId(value)` | Validates and sanitizes a snippet ID string |

None of these may import from `node:fs`, `node:child_process`, `node:http`, or
any module with side effects. If a function candidate for `utils.js` needs I/O,
it belongs in `server.js` or a new dedicated module.

### 2. `server.js` orchestrates; `utils.js` transforms

`server.js` owns: spawning the CLI process, maintaining run state, routing HTTP
requests, managing WebSocket connections, reading log history, and writing
prompt-input temp files.

`utils.js` owns: stateless transformations that `server.js` needs but that have
no reason to touch I/O.

Do not add stateful logic to `utils.js`. Do not add pure transformation
functions directly into `server.js` if they are independently testable.

### 3. Named exports only

`utils.js` uses named exports. `server.js` has no exports (it is the entry
point). Do not switch to default exports — named imports make the origin of
each function traceable in `server.js`.

### 4. No side effects at import time

Importing `utils.js` must trigger nothing: no timers, no file reads, no network
calls. `server.js` initializes the HTTP server at the bottom of the file, not
at the top-level of the module — this is correct behavior and must stay that
way.

### 5. Module scope for sensitive constants

`SCRIPT_PATH`, `LOG_FILE`, `PORT`, and `HOST` are read once from env vars or
computed from `REPO_ROOT` at module load time in `server.js`. These are not
passed through function parameters to avoid threading constants through every
call. The exception is `SYSUPDATE_SCRIPT_PATH` and similar overrides used by
tests — these are the correct mechanism for test isolation.

## Dependency direction

```
server.js  →  utils.js  (one-way; utils never imports server)
utils.js   →  (nothing)
```

Adding a dependency from `utils.js` to `server.js` is a layer violation. If a
utility function needs server-level state, pass the state as a parameter instead.

## When to add a new module

Add a new module to `web/backend/` when:
- a concern in `server.js` becomes large enough to unit-test in isolation
- a group of pure functions accumulates that is clearly distinct from the
  current `utils.js` responsibilities

Good candidates: a dedicated JSONL log parser, a run-state machine extractor,
a WebSocket broadcast helper. Each would let `server.js` shrink.

Do not create modules named `helpers.js`, `common.js`, or `shared.js` without
a qualifying domain noun.

## Review heuristics

### Pure core test

Can all four functions in `utils.js` be tested by passing inputs and asserting
outputs with `npm run test`, no server running, no environment variables set?
If not, a side effect has leaked into the utility layer.

### Module focus test

Can the purpose of `utils.js` be described in one sentence? ("Pure stateless
helpers for the backend bridge.") Can `server.js`? ("Runs the HTTP + WebSocket
bridge that spawns the CLI and routes its JSON event stream.") If either
requires "and … and", the module should be split.

### Import direction test

Does `utils.js` import from `server.js`? (It must not.) Does `utils.js` import
from any Node.js built-in module? (It must not.)

## Positive signals

- `npm run test` tests `utils.js` completely without starting the server.
- A new backend contributor can locate any route handler in `server.js` without
  reading `utils.js` first.
- `utils.js` exports show no changes when HTTP routes are added or changed.
- A session adding a new route only needs to read `server.js`.

## Warning signs

- `utils.js` grows an `import { readFile }` or `import { spawn }` line.
- A route handler in `server.js` contains a large inline transformation that
  could be extracted and unit-tested.
- `server.js` exceeds 600 lines with no extraction.
- A function in `utils.js` reads from `process.env` directly.

## Related guides

- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md) — `server.js`
  is the adapter layer; `utils.js` is the utility layer.
- [UNIT_TEST_GUIDE.md](./UNIT_TEST_GUIDE.md) — `utils.js` purity makes its
  functions the canonical Vitest unit test targets.
- [LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md) — `utils.js`'s bounded scope
  keeps its context cost low.

## Summary checklist

- [ ] `utils.js` exports only pure functions with no I/O or side effects.
- [ ] `server.js` is the sole module with side effects.
- [ ] `utils.js` does not import from `server.js` or any Node.js built-in.
- [ ] Named exports are used throughout `utils.js`.
- [ ] Importing `utils.js` produces no observable side effects.
- [ ] New pure transformation logic goes in `utils.js`; I/O logic stays in
      `server.js`.
- [ ] Any new module added to `web/backend/` has a qualifying name (not
      `helpers.js`).
