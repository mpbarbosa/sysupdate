# sysupdate Web Dashboard

A browser-based "Cyber-Terminal HUD" front-end for sysupdate, built with React 19, Vite, and
Tailwind CSS v4. The terminal console and logs can now be backed by the local bridge, while
update cards and schedule/settings views still retain mock/prototype data. See
[DESIGN.md](./DESIGN.md) and [CONTEXT.md](./CONTEXT.md) for scope and known gaps.

## Run

```bash
npm install
npm run dev
```

## Local backend bridge

The first real-data backend slice now lives in `backend/server.js`. Run it in a second terminal:

```bash
npm run backend
```

It binds to `127.0.0.1:4174` and exposes:

- `GET /api/health` — backend status and current run snapshot
- `GET /api/bootstrap` — current run snapshot plus persisted logs
- `GET /api/logs?limit=50` — parsed JSONL run history
- `GET /api/runs/current` — current in-memory CLI run state
- `POST /api/runs/check-only` — starts `system_update.sh --check-only --json-events`
- `WS /ws` — live CLI event stream and snapshot updates

The Vite dev server proxies `/api` and `/ws` to the local backend automatically.

If you want the full startup sequence in one command, use:

```bash
./run_app.sh
```

That script runs `npm run build`, starts `npm run backend` in the background, and then runs
`npm run dev -- --host 127.0.0.1 --port 5173 --strictPort`. Once the frontend is reachable, it
opens the app in your browser at `http://127.0.0.1:5173` by default. You can override the frontend
binding and browser URL with `SYSUPDATE_WEB_APP_HOST`, `SYSUPDATE_WEB_APP_PORT`, and
`SYSUPDATE_WEB_APP_URL`.

## Build

```bash
npm run build
```

## Structure

- `src/types.ts` — `UpdateItem`, `TerminalLine`, `LogEntry`, `ScheduleTask`, `SystemConfig`.
- `src/data/mockData.ts` — mock data backing all views.
- `src/theme.ts` — theme color / severity color helpers (Cyber-Terminal HUD palette).
- `src/components/` — `Sidebar`, `TopAppBar`, `DashboardView`, `LogsView`, `ScheduleView`,
  `SettingsView`.
- `src/App.tsx` — core state controller, including the `schedulePrint` terminal simulator
  from `DESIGN.md` §4.
- `backend/server.js` — local-only Node bridge for persisted logs and live CLI JSON events.
