# Integration Test Guide

This guide defines integration-testing expectations for `sysupdate`.

## Current repo reality

The Bash core does **not** currently have a checked-in automated integration
test harness. For now, integration confidence comes from repeatable command
checks against real boundaries.

That still counts as integration validation when the run crosses a real seam and
the environment is controlled.

## Goal

Verify that collaborating components work together across real boundaries:

- orchestrator ↔ package-manager module
- orchestrator ↔ snippet
- backend bridge ↔ CLI JSON event stream
- frontend ↔ backend snapshot and summary contract
- snippet ↔ real local tool metadata (for example `snap`, `apt-cache`, `npm`)

## What counts as an integration check here

Examples that fit this repo:

1. `./scripts/system_update.sh --check-only --json-events --snippet <id>`
2. sourcing a library module and running one real function in isolation
3. starting `web/backend/server.js` and reading `/api/health` or
   `/api/bootstrap`
4. checking that backend snapshots reflect real `summary.updates` events
5. verifying that a GUI-triggered backend route actually changes the live CLI
   result instead of only local UI state

## Required rules

### 1. Use real boundaries

- Prefer real local commands and real repo code paths.
- Do not mock the CLI and call it an integration test.
- If a boundary is too destructive, use `--check-only` rather than replacing it
  with a fake.

### 2. Keep the environment controlled

- Run against the local repo and local backend bridge.
- Use read-only modes where possible.
- Be explicit about environment assumptions such as installed tools, local
  package state, or required ports.

### 3. Assert observable boundary behavior

- Check terminal output, summary events, log entries, HTTP payloads, or version
  changes the caller actually depends on.
- Do not stop at "the command exited 0" if the boundary can report false
  success.

### 4. Cover failure paths at the seam

- Non-TTY prompt behavior
- sudo refusal in non-interactive contexts
- version parsing failures
- backend route conflicts or stale snapshots
- check-only paths accidentally mutating state

## Current preferred checks

| Surface | Preferred validation |
| --- | --- |
| Bash snippet behavior | `./scripts/system_update.sh --check-only --json-events --snippet <id>` |
| Shared Bash helper behavior | `source scripts/lib/core_lib.sh` + targeted helper invocation |
| Package-manager workflow | `source scripts/lib/<manager>.sh` + focused function call |
| Web/backend bridge | `cd web && npm run backend`, then `GET /api/health` or `GET /api/bootstrap` |
| Backend snapshot correctness | trigger a run, then read `/api/runs/current` and inspect summaries |

## Warning signs

- a GUI issue is "fixed" without rechecking the emitted CLI summary
- a snippet prints success after a failed privileged command
- a check-only run still performs `snap`, `apt`, or installer mutations
- backend responses are validated only against mocked frontend state

## Future direction

When a dedicated automated integration suite is added, keep it separate from
unit and end-to-end suites and organize it around the boundaries above.

## Related guides

- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md)
- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md)
- [E2E_TEST_GUIDE.md](./E2E_TEST_GUIDE.md)

