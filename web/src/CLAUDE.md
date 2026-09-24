# CLAUDE.md — web/src/

React 19 + TypeScript dashboard (Cyber-Terminal HUD). Entry point: `main.tsx`.

| File / Directory | Role |
| --- | --- |
| `App.tsx` | Sole state controller — WebSocket, run state, update inventory |
| `types.ts` | All shared interfaces (`UpdateItem`, `BackendRunSnapshot`, `SystemConfig`, …) |
| `summaryStatus.ts` | Pure CLI-status → card status/severity mapping (+ `summaryStatus.test.ts`) |
| `updateCard.ts` | Pure card affordances — which button, versions vs remediation (+ `updateCard.test.ts`) |
| `updateFilter.ts` | Pure list filtering — sidebar category + "hide up to date" toggle (+ `updateFilter.test.ts`) |
| `theme.ts` | Pure theme helpers — no component logic, no React imports |
| `theme.test.ts` | Vitest unit tests for theme helpers |
| `components/` | Subcomponents rendered by `App.tsx` |
| `data/mockData.ts` | `ScheduleTask` list and `SystemConfig` initial state (not yet live-wired) |

## Key rules for this directory

- `App.tsx` owns state, WebSocket lifecycle, and callbacks — not large JSX rendering blocks; extract panels into named components
- `App.tsx` over 400 lines is a warning sign that extraction is overdue
- `SUMMARY_ITEM_OVERRIDES` and `PACKAGE_MANAGER_SUMMARY_CONFIG` in `App.tsx` must stay in sync with `SNIPPET_ID` values in `scripts/upgrade_snippets/`
- Props must be typed with only the fields the component actually uses — not the full `BackendRunSnapshot`
- Every `useEffect` that opens a WebSocket, subscription, or timer must return a cleanup function
- All colors and glow classes come from `theme.ts` helpers — no inline hex values in JSX
- Card button/label/version-row decisions belong in `updateCard.ts`, not in JSX ternaries — they are unit-testable there, and there is no React test renderer in this project
- A `blocked` item must never render a retry affordance; show the CLI's `remediation` text instead of a version transition
- Mock data lives in `data/mockData.ts`, never inline in component bodies
- `ScheduleTask.command` is intended for `sysupdate --snippet <id>` but crontab wiring is not yet implemented
- `handleRunAll` in `App.tsx` is a stub — only individual snippet upgrades are wired to the live backend
- `shutdownState` in `App.tsx` swaps the whole tree for `components/ShutdownScreen.tsx` once the bridge confirms it is stopping (`POST /api/shutdown` from this tab, or a `bridge.shutdown` WebSocket message from another); `window.close()` is only attempted by the tab that asked
- `components/SudoPasswordModal.tsx` overlays the dashboard while `currentRun.sudoPrompt.status === 'requested'` (the CLI is blocked inside sudo); `App.tsx` answers via `POST /api/runs/sudo-password` and never keeps the password in state — the input clears on every new `requestId`, and `rejected: true` shows the "try again" line

## Run frontend type-check and lint

```bash
npx tsc --noEmit   # from web/
npm run lint       # from web/
npm run test       # Vitest unit tests
```

## Guides for this directory

- [REACT_GUIDE.md](../../docs/guides/REACT_GUIDE.md) — component extraction rules, props surface, effect cleanup, mock data placement
- [LLM_CONTEXT_GUIDE.md](../../docs/guides/LLM_CONTEXT_GUIDE.md) — App.tsx size warning, snippet pattern consistency
- [NAMING_GUIDE.md](../../docs/guides/NAMING_GUIDE.md) — TypeScript type names, component names, lookup map constants
- [ERROR_HANDLING_GUIDE.md](../../docs/guides/ERROR_HANDLING_GUIDE.md) — `status === 'failed'` rendering, WebSocket disconnection state
