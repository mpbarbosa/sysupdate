# Low Coupling Guide

Use low coupling in `sysupdate` so the Bash core, backend bridge, and GUI
clients can evolve without rewriting each other.

## Goal

Keep dependencies explicit, narrow, and aligned with the repo's intended
architecture.

## What this means in `sysupdate`

`sysupdate` has several important boundaries:

1. package-manager modules should depend on shared core helpers, not on each
   other
2. snippets should reuse shared helpers without depending on frontend code
3. the backend bridge should depend on the CLI event contract, not on
   hard-coded UI assumptions
4. frontend clients should depend on backend snapshots and summaries, not on
   shell-specific implementation details beyond the published contract

## Required rules

1. Keep shared conventions in `core_lib.sh`, `upgrade_utils.sh`, YAML config, or
   typed frontend contracts instead of scattered copies.
2. Do not let one package-manager module import behavior from another.
3. Do not let frontend code become the canonical source of update truth.
4. Keep transport reshaping in adapters:
   - CLI event emission in Bash
   - process/event translation in `web/backend/server.js`
   - UI mapping in `web/src/`
5. Prefer cross-links over duplicated rule text in docs.

## Positive signals

- A snippet fix does not require coordinated edits across many unrelated files.
- UI clients can change visuals without touching the Bash core.
- Backend routes can change transport details without redefining snippet logic.
- Shared config values and message contracts have one authoritative home.

## Warning signs

- frontend code hardcodes package-manager or snippet semantics
- backend code invents its own version comparison rules
- snippets rely on implicit globals beyond the established core helpers
- the same CLI-to-UI mapping rule is copied in several places
- docs repeat the same architecture rule in multiple files without links

## Review heuristics

### Dependency trace test

Can you tell what a component depends on from local imports, sourced helpers, or
typed contracts?

### Change-radius test

If one collaborator changes, does the fix stay near that boundary or spread
across the repo?

### Replacement test

Could the web dashboard and the QuickShell widget both keep consuming the same
CLI contract after the change?

## Related guides

- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md)
- [DRY_GUIDE.md](./DRY_GUIDE.md)
- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md)

