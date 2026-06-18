# CLAUDE.md — web/src/

React 19 + TypeScript dashboard (Cyber-Terminal HUD). Entry point: `main.tsx`.

| File / Directory | Role |
| --- | --- |
| `App.tsx` | Sole state controller — WebSocket, run state, update inventory |
| `types.ts` | All shared interfaces (`UpdateItem`, `BackendRunSnapshot`, `SystemConfig`, …) |
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
- Mock data lives in `data/mockData.ts`, never inline in component bodies
- `ScheduleTask.command` is intended for `sysupdate --snippet <id>` but crontab wiring is not yet implemented
- `handleRunAll` in `App.tsx` is a stub — only individual snippet upgrades are wired to the live backend

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
