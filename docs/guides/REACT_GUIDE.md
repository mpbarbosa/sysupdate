# React Guide

This guide defines component design expectations for `web/src/` — the Cyber-
Terminal HUD dashboard for sysupdate. It uses React 19, TypeScript, Tailwind
CSS v4, and Vite.

## Current structure

```
web/src/
  App.tsx         — sole state controller; manages WebSocket, run state, update inventory
  types.ts        — shared interfaces (UpdateItem, BackendRunSnapshot, SystemConfig, …)
  theme.ts        — pure theme helpers (no component logic)
  theme.test.ts   — Vitest unit tests for theme helpers
  components/     — subcomponents rendered by App.tsx
  data/           — mockData.ts (schedule tasks and initial config — not yet wired live)
  index.css       — global styles
  main.tsx        — React root mount
```

## Goal

Keep `App.tsx` as a focused state controller and extract rendering concerns
into focused subcomponents — so that each piece of UI can be understood, tested,
and changed without reading the full 24KB entry point.

## Why it matters now

`App.tsx` currently owns state, WebSocket lifecycle, run control, update
inventory, theme rendering, and all sub-panel layout. This is the largest
context-load surface in the frontend. Extracting focused subcomponents makes
sessions smaller and changes safer.

## Required rules

### 1. `App.tsx` is a state controller, not a renderer

`App.tsx` should own:
- `GET /api/bootstrap` and run-start logic
- WebSocket connection and `snapshot` message handling
- `applyRunSnapshot` update inventory
- `SUMMARY_ITEM_OVERRIDES` and `PACKAGE_MANAGER_SUMMARY_CONFIG` lookup maps
- Callbacks passed down to subcomponents (`handleRunSnippet`, etc.)

`App.tsx` should not own large blocks of JSX that can be described as a
single UI panel (terminal output, update cards, schedule view, etc.). Extract
those into named components.

### 2. One component = one describable responsibility

Good split:
- `TerminalPanel` — renders the scrollable terminal output list
- `UpdateCard` — renders one `UpdateItem` with its status and action button
- `RunControls` — renders the check / upgrade / run-all buttons

Avoid:
- A single component that renders all panels and handles WebSocket state

### 3. Data flows down through typed props; events flow up

Props must be typed. Accept only what the component needs — not the entire
`BackendRunSnapshot` if only `status` and `exitCode` are used.

```tsx
interface RunStatusBadgeProps {
  status: BackendRunSnapshot['status'];
  exitCode: number | null;
}
```

### 4. Side effects in `useEffect` with cleanup

The current WebSocket connection in `App.tsx` is the canonical example:

```tsx
useEffect(() => {
  const ws = new WebSocket(wsUrl);
  ws.onmessage = handler;
  return () => ws.close();
}, [wsUrl]);
```

Every `useEffect` that opens a connection, subscription, or timer must return
a cleanup function. An effect that fires on a dependency change without cleanup
is a resource leak in long-lived dashboard sessions.

### 5. Theme stays in `theme.ts`

All color, glow class, severity color, and font-size helpers live in
`theme.ts`. Components must not hardcode hex values or Tailwind class strings
that correspond to theme tokens — call the helpers instead.

`theme.ts` is pure (no React imports). Its unit tests are in `theme.test.ts`.

### 6. Derived values are computed inline

`SUMMARY_ITEM_OVERRIDES` and `PACKAGE_MANAGER_SUMMARY_CONFIG` translate raw
CLI event names into typed `UpdateItem` objects. These maps are the derived
view of the CLI contract — they must not be duplicated into component state.
Compute display values from them at render time.

### 7. Mock data stays in `data/mockData.ts`

`ScheduleTask` list and `SystemConfig` initial state are mocked. Keep mock
data in `data/mockData.ts` and import from there — do not inline mock arrays
into component files. When live wiring is added, the mock can be swapped at
the import site.

## State management

`App.tsx` uses local `useState` for all dashboard state. This is correct for
now — all state is session-scoped and single-tree.

Lift state only when two sibling components need to read or write the same value.
Do not add global state management (Context, Zustand) unless `App.tsx` extraction
creates real sibling state that cannot be lifted to a shared ancestor.

## Component file conventions

```
web/src/
  components/
    TerminalPanel.tsx        — feature component
    UpdateCard.tsx           — feature component
    RunControls.tsx          — feature component
    TerminalPanel.test.tsx   — (when tests are added — co-locate)
  App.tsx
  App.test.tsx               — (when App-level tests are added — co-locate)
```

## Review heuristics

### Responsibility test

Can the component's purpose be described in one sentence? "Renders the
terminal output scroll panel" — yes. "Renders the whole dashboard" — split it.

### Props surface test

Does the component accept the entire `BackendRunSnapshot` when it only uses
`status`? If yes, narrow the props to the exact fields needed.

### Effect cleanup test

Does every `useEffect` that opens a WebSocket, subscribes to an event, or
starts a timer return a cleanup function? Long-lived dashboard sessions with
no cleanup will leak connections and event handlers.

### Mock boundary test

Are mock arrays or objects defined inline in a component file? If yes, move
them to `data/mockData.ts` and import from there.

## Positive signals

- Adding a new update panel does not require reading `App.tsx` start to finish.
- `theme.ts` is the only file a session needs to read to change a color.
- A failing Vitest test pinpoints one theme helper, not a rendering tree.
- `App.tsx` is shorter than 400 lines after subcomponent extraction.

## Warning signs

- A component file over 300 lines with no sub-component extraction.
- Tailwind hex values or color strings hardcoded in component JSX.
- A `useEffect` with no cleanup that opens a WebSocket or subscribes to events.
- Mock data arrays defined inside component bodies.
- Props typed as the full `BackendRunSnapshot` in a component that displays
  one field.

## Related guides

- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md) — component extraction
  follows the same single-responsibility principle as module extraction.
- [LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md) — small, focused components
  keep session context cost low when editing the frontend.
- [UNIT_TEST_GUIDE.md](./UNIT_TEST_GUIDE.md) — `theme.ts` pure helpers are the
  model for what is independently testable without rendering.

## Summary checklist

- [ ] `App.tsx` owns state; named subcomponents own rendering of distinct panels.
- [ ] Props are typed with only the fields the component actually needs.
- [ ] Data flows down through props; events flow up through callbacks.
- [ ] Every `useEffect` that allocates a resource has a cleanup function.
- [ ] Theme colors and classes come from `theme.ts` helpers, not inline strings.
- [ ] Mock data lives in `data/mockData.ts`, not inline in components.
- [ ] Derived values are computed from state/maps at render time, not stored
      as parallel state.
