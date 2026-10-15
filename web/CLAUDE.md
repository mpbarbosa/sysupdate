# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`web/` is a browser-based "Cyber-Terminal HUD" dashboard for sysupdate, built with React 19, Vite, Tailwind CSS v4, and TypeScript. It has two processes: a Vite dev server (port 5173) and a Node.js local bridge server (port 4174).

## Running and validating

```bash
# Install dependencies (first time or after package changes)
npm install

# Start both processes (builds, launches backend + dev server, opens browser)
./run_app.sh

# Or manually in two terminals:
npm run backend   # Node bridge on port 4174
npm run dev       # Vite dev server on port 5173 (proxies /api and /ws to 4174)

# Type-check
npx tsc --noEmit

# Lint
npm run lint

# Production build
npm run build
```

No automated test suite exists. Validation is `tsc --noEmit`, `eslint .`, and manual browser testing.

## Architecture

### Two-process model

The backend bridge (`backend/server.js`) and the Vite dev server are independent processes. Vite's `vite.config.ts` proxies `/api` and `/ws` to the bridge (`SYSUPDATE_WEB_HOST`/`SYSUPDATE_WEB_PORT`, default `127.0.0.1:4174`), so the frontend always talks to a single origin and an alternative port set for one process is picked up by all three.

### Backend bridge (`backend/server.js`)

A plain Node.js HTTP + WebSocket server (no framework). It:

- Spawns `scripts/system_update.sh --json-events` (or with `--check-only`, `--snippet <id>`) as a child process.
- Reads JSON events from the CLI's **stderr** (the `--json-events` flag routes structured events there); stdout lines are forwarded as raw terminal output.
- Maintains an in-memory `currentRun` state machine: `starting → running → completed/failed`, with
  `paused` (suspended by the dashboard) and `stopped` (interrupted by the dashboard) as the two
  states the run controls add. `stopped` is deliberately distinct from `failed`: the run did what
  was asked of it.
- Broadcasts `snapshot` and `cli.event` WebSocket messages to all connected frontend clients on every event.
- Reads persisted log history from `~/.local/state/sysupdate/run-history.jsonl` (JSONL format).

Key env vars for the backend:
- `SYSUPDATE_WEB_HOST` / `SYSUPDATE_WEB_PORT` (default `127.0.0.1:4174`)
- `SYSUPDATE_LOG_FILE` — path to the JSONL run-history log
- `SYSUPDATE_LOG_LIMIT` — max log entries returned (default 50)

REST endpoints: `GET /api/health`, `GET /api/bootstrap`, `GET /api/logs`, `GET /api/runs/current`, `POST /api/runs/check-only`, `POST /api/runs/upgrade`, `POST /api/runs/pause`, `POST /api/runs/resume`, `POST /api/runs/stop`.

The run controls in the top bar drive the last three. The CLI is spawned `detached`, so it leads its
own process group and a signal reaches apt/sudo/make rather than only the Bash orchestrator: pause is
`SIGSTOP` to `-pid`, resume `SIGCONT`, stop `SIGTERM` escalating to `SIGKILL` after
`SYSUPDATE_STOP_GRACE_MS` (default 5000). Stopping a paused run wakes it first, because a suspended
process cannot act on `SIGTERM`.

`run_app.sh` reuses an existing server on either port only after verifying its identity, never on
occupancy alone: the app port must serve the `<meta name="sysupdate-app">` marker from
`index.html` (checked without the backend, which may still be starting), and the backend port must
answer `GET /api/health` with `"backend":"sysupdate-local-bridge"`. A foreign listener on either
port aborts the launch with a message naming the port and the override variable — adopting one
previously pointed the browser at another repo's Vite app while our backend sat unused. Under `-i`
the backend is restarted by killing the pid holding the verified port (`lsof`/`ss`), falling back to
`pkill -f backend/server.js` only when neither is installed. If you change the marker, change both
`index.html` and `APP_IDENTITY_MARKER` in `run_app.sh`.
`tests/integration/launcher_port_reuse.bats` covers these decisions — reuse, both abort paths, the
no-retry-on-a-served-answer rule, and the EXIT trap stopping a backend the aborted run had already
spawned. It reaches the probe helpers by sourcing the launcher with
`SYSUPDATE_RUN_APP_DEFINE_ONLY=1`, which returns before the trap and the build; that flag exists for
the suite and the launcher never sets it.

`POST /api/shutdown` stops the bridge process: it broadcasts a `bridge.shutdown` WebSocket message, answers `202 { shuttingDown: true }`, then closes the servers and exits 0. While a run is active it answers `409` unless the body carries `{ "force": true }`, which also SIGTERMs the child CLI. The top bar's power button uses it (after an inline confirmation), then calls `window.close()`; browsers only honour that for script-opened or single-history tabs, so `ShutdownScreen` is rendered as the fallback. `run_app.sh` watches the backend and stops the Vite dev server when it exits — a dev server started by hand stays up.

### Frontend (`src/`)

`App.tsx` is the sole state controller. On mount it calls `GET /api/bootstrap`, then immediately fires a check-only run if no active run exists. It opens a WebSocket to `/ws` and applies incoming `snapshot` messages via `applyRunSnapshot()`.

The two key lookup maps in `App.tsx` translate raw CLI event data into typed `UpdateItem`s:
- `SUMMARY_ITEM_OVERRIDES` — per-app name overrides (id, snippetId, category, etc.)
- `PACKAGE_MANAGER_SUMMARY_CONFIG` — one entry per package manager summary name (e.g. `apt_updates`, `npm_updates`)

These must be kept in sync with the snippet IDs in `../scripts/upgrade_snippets/`.

### Types (`src/types.ts`)

All shared interfaces live here. Notable:
- `UpdateItem` — a single update card (has optional `snippetId` mapping to the CLI snippet that handles it; `undefined` means no live upgrade is wired).
- `BackendRunSnapshot` — shape of the in-memory run state the bridge serializes.
- `BackendSummaryEvent` — typed subset of the `summary.updates` CLI JSON event.
- `SystemConfig.repositories` uses `{ apt, pacman, npm, pip, cargo }` — not `brew` (no macOS support).

### Theme (`src/theme.ts`)

Helper functions only — no component logic. Palette: Cyan `#00f3ff`, Magenta `#ffabf3`, Emerald `#39ff14`, Amber `#ffb800`.

### Data that is still mocked

`ScheduleTask` list and `SystemConfig` initial state come from `src/data/mockData.ts`. The schedule view does not yet manage real crontab entries. `handleRunAll` in `App.tsx` is also a stub — only individual snippet upgrades are wired to the live backend.

## Known design deviations

See `CONTEXT.md` for corrections to `DESIGN.md`. The most important:
- `SystemConfig.repositories` in `DESIGN.md` lists `brew`; the actual shape has `pacman` instead.
- `autoUpdate` in `SystemConfig` is redundant with schedule tasks; `ScheduleTask.enabled` is the real toggle.
- `ScheduleTask.command` is intended to invoke `sysupdate --snippet <id>` against the real crontab, but this is not yet implemented.
