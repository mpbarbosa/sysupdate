# Code Quality Control Guide

This guide defines implementation-quality expectations for `sysupdate`,
especially for changes that cross the Bash core, the local backend bridge, and
GUI clients.

## Source of truth

Use this guide together with:

- [Clean Architecture Guide](./CLEAN_ARCHITECTURE_GUIDE.md)
- [High Cohesion Guide](./HIGH_COHESION_GUIDE.md)
- [Low Coupling Guide](./LOW_COUPLING_GUIDE.md)
- [DRY Guide](./DRY_GUIDE.md)
- [Integration Test Guide](./INTEGRATION_TEST_GUIDE.md)
- [End-to-End Test Guide](./E2E_TEST_GUIDE.md)
- [`CLAUDE.md`](../../CLAUDE.md)

## Goal

Catch regressions early by checking that new code:

1. lands in the correct module boundary
2. reuses existing helpers instead of duplicating script logic
3. keeps CLI, backend, and UI contracts aligned
4. validates behavior with the commands that already exist in this repo

## Quality gates

### 1. Responsibility gate

- Keep `system_update.sh` focused on orchestration.
- Keep each snippet focused on one tool, package manager, or application.
- Keep backend code focused on process spawning, event parsing, and transport.
- Keep frontend code focused on rendering and UI state derived from live data.

### 2. Boundary gate

- Core Bash logic owns update semantics.
- The backend bridge owns process execution and event translation.
- Frontends own presentation only.
- Do not fix a CLI data problem by adding a frontend-only heuristic unless the
  CLI contract is intentionally unchanged and documented.

### 3. Reuse gate

- Prefer `print_*`, `prompt_*`, `run_with_sudo`, `emit_summary_event`,
  `compare_versions`, and `upgrade_utils.sh` helpers over bespoke copies.
- Prefer YAML-driven snippet configuration where the existing snippet framework
  already supports the behavior.
- Prefer updating shared mappings once rather than patching several UI branches.

### 4. Side-effect gate

- Keep parsing, normalization, and comparison helpers separate from command
  execution where practical.
- Do not report success after a privileged command, installer, or updater unless
  the real active version or observable outcome was rechecked when the boundary
  is failure-prone.
- In `--check-only` mode, never perform live mutations.

### 5. Documentation gate

- Update project docs when behavior, command usage, or architecture expectations
  change.
- Cross-link to the most specific guide instead of duplicating its rules.
- If a new engineering convention is intended to last, document it once in
  `docs/guides/` or `CLAUDE.md`.

### 6. Validation gate

Run the repository validation commands that match the touched surface.

**Bash core or snippet changes**

1. `bash -n scripts/system_update.sh scripts/lib/*.sh scripts/upgrade_snippets/*.sh`
2. `shellcheck scripts/system_update.sh scripts/lib/*.sh scripts/upgrade_snippets/*.sh`
3. targeted live checks such as:
   - `./scripts/system_update.sh --check-only --json-events --snippet <id>`
   - `source scripts/lib/core_lib.sh && source scripts/lib/apt_manager.sh && QUIET_MODE=true && check_updates_available`

**Web/backend changes**

1. `cd web && npm run build`
2. start the local bridge and verify endpoints such as `/api/health`,
   `/api/bootstrap`, or `/api/runs/current`
3. verify the affected UI flow against live backend data, not mock terminal
   output

### 7. Test-strategy gate

- This repo currently has no checked-in automated unit test harness for the Bash
  core.
- Integration and end-to-end confidence therefore come from targeted command
  runs, local backend checks, and UI flow verification.
- When adding automated tests in the future, keep them separated by level and
  independently runnable.

## Positive signals

- A change touches the smallest reasonable number of files.
- A snippet fix reuses shared helpers instead of inventing a new framework.
- The backend and GUI reflect the same `summary.updates` truth as the CLI.
- Validation commands target the exact changed boundary.
- Docs and code agree on the current contract.

## Warning signs

- Success is inferred from a command pipeline without checking the real active
  result.
- `--check-only` still mutates state.
- The GUI appears fixed only because frontend state was changed locally.
- A snippet duplicates prompting, sudo handling, or version parsing already
  available elsewhere.
- Docs still describe a pre-refactor layout after behavior has moved.

## Summary checklist

- [ ] The change belongs to the correct layer or module.
- [ ] Existing helpers were reused before adding new logic.
- [ ] `--check-only` remains read-only.
- [ ] Live CLI, backend, and GUI contracts still agree.
- [ ] The relevant repository validation commands were run.
- [ ] Public or architectural behavior changes were documented.

