# Clean Architecture Guide

Use clean architecture in `sysupdate` to keep the update engine stable while
entry points and GUI adapters evolve around it.

## Goal

Keep update logic and shared policy in the Bash core, and keep orchestration,
transport, and presentation details at the edges.

## What this means in `sysupdate`

`sysupdate` is not a four-layer enterprise app, but it does have clear stability
boundaries:

1. the stable core lives in `scripts/lib/`
2. package-manager and snippet workflows live in `scripts/lib/*.sh` and
   `scripts/upgrade_snippets/`
3. entry points and adapters live in `scripts/system_update.sh`,
   `scripts/system_summary.sh`, and `web/backend/server.js`
4. presentation clients live in `web/src/` and `quickshell/`

The key rule is still the same: volatile outer code depends on the core
contract; the core must not depend on a specific frontend.

## Layer reference for this repo

| Layer | Repository examples | Responsibility |
| --- | --- | --- |
| Core primitives | `scripts/lib/core_lib.sh`, `scripts/lib/upgrade_utils.sh` | Shared output, prompting, version comparison, JSON event emission, shared update helpers |
| Workflow logic | `scripts/lib/apt_manager.sh`, `scripts/lib/pacman_manager.sh`, `scripts/upgrade_snippets/*.sh` | Update decisions and snippet/package-manager-specific behavior |
| Entry points and adapters | `scripts/system_update.sh`, `scripts/system_summary.sh`, `web/backend/server.js` | Parse flags, spawn runs, translate process output, expose transport-specific APIs |
| Presentation | `web/src/`, `quickshell/` | Render terminal output, update inventory, logs, schedule UX |

## Required rules

1. `scripts/system_update.sh` stays a thin orchestrator. Do not move business
   rules into argument parsing or top-level execution flow.
2. Shared Bash behavior belongs in `scripts/lib/`, not copied across snippets.
3. Snippet-specific logic belongs in the snippet or in a shared helper if
   multiple snippets truly need it.
4. The local backend bridge translates CLI events; it must not reimplement
   update detection logic that already exists in Bash.
5. The web dashboard and QuickShell widget consume the CLI/backend contract; they
   must not become independent update engines.
6. Transport-specific shapes stay at the edge. For example, WebSocket payloads,
   REST responses, and UI state transformations should not leak back into
   `scripts/lib/`.
7. Configuration-driven snippet behavior should stay in YAML when possible, with
   generic orchestration in `upgrade_utils.sh`.

## Good fits in this repo

- adding a new shared version parser to `upgrade_utils.sh` instead of duplicating
  command parsing in several snippets
- keeping `web/backend/server.js` responsible for process spawning and event
  translation, while the Bash core owns update semantics
- letting `web/src/App.tsx` map live summaries into cards without embedding CLI
  process logic

## Warning signs

- `system_update.sh` grows new snippet-specific decision logic
- a snippet duplicates prompting, sudo handling, or JSON event behavior already
  in `core_lib.sh`
- the backend starts inferring update availability differently from the CLI
- frontend code hardcodes package-manager rules that already exist in Bash
- GUI-only assumptions leak into core CLI helpers

## Review heuristics

### Thin orchestrator test

If a change belongs to one package manager, one snippet family, or one shared
helper, it probably does not belong in `system_update.sh`.

### Edge translation test

If code exists only to reshape process output, HTTP payloads, or UI state, keep
it in the backend or frontend layer, not in the Bash core.

### Client reuse test

Could the same core CLI behavior still be used by both the web dashboard and
the QuickShell widget without rewriting it? If not, the boundary is drifting.

## Related guides

- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md)
- [LOW_COUPLING_GUIDE.md](./LOW_COUPLING_GUIDE.md)
- [DRY_GUIDE.md](./DRY_GUIDE.md)
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md)

