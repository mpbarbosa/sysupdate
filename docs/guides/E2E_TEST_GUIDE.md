# End-to-End Test Guide

This guide defines end-to-end testing expectations for `sysupdate`.

## Current repo reality

The repo does not yet have a checked-in, one-command E2E suite. The closest
current end-to-end validation is:

- running real CLI flows through `scripts/system_update.sh`
- running the local backend bridge with the real CLI
- validating the web dashboard against live backend data
- using temporary browser automation or manual browser checks when GUI behavior
  is the thing being changed

## Goal

Verify complete user-visible flows against the assembled system rather than
isolated helpers.

## E2E surfaces in this repo

### CLI flows

- full read-only update check
- single-snippet read-only run
- quiet/non-interactive behavior
- prompt/sudo behavior at the user boundary

### Web dashboard flows

- bootstrapping from `/api/bootstrap`
- rendering live terminal lines from the backend
- mapping `summary.updates` into update cards
- running a live snippet upgrade and then refreshing the displayed state
- surfacing errors from the backend instead of silently falling back to mock
  state

## Required rules

### 1. Drive the real interface

- For CLI E2E, invoke `./scripts/system_update.sh`.
- For web E2E, start the local backend bridge and use the browser-facing app.
- Do not bypass the entry point by calling internal helpers directly.

### 2. Use the assembled stack

- The Bash core, local backend bridge, and UI must all participate when testing
  a GUI flow.
- Do not mock your own CLI or backend inside an end-to-end scenario.

### 3. Assert user-visible outcomes

- terminal lines
- update card state
- visible logs
- returned HTTP payloads when the user surface is an API client
- actual installed version changes for upgrade flows

### 4. Keep flows deterministic

- Prefer `--check-only` for repeatable read-only scenarios.
- Use explicit starting conditions when a test needs a specific installed state.
- Avoid destructive privileged flows unless the environment is intentionally set
  up for them.

## Current practical E2E checks

| Flow | Practical check today |
| --- | --- |
| CLI read-only pass | `./scripts/system_update.sh --check-only --json-events` |
| Single live snippet pass | `./scripts/system_update.sh --check-only --json-events --snippet <id>` |
| Web bootstrap | start backend, load app, verify the terminal and cards come from live backend data |
| Web upgrade flow | trigger a live snippet upgrade, then verify a fresh check reflects the changed version |

## Guidance for future automation

When a checked-in browser E2E harness is added:

1. keep it separate from integration checks
2. name scenarios after user journeys, not components
3. use explicit waits for observable state instead of sleeps
4. cover only the critical flows — do not duplicate every lower-level test here

## Warning signs

- the page looks correct only because local React state was mutated
- a CLI flow is considered successful without checking the final observable
  version or summary
- fixed sleeps are used instead of waiting for visible terminal/output changes
- the same scenario is covered exhaustively here and in lower-level checks with
  no added confidence

## Related guides

- [INTEGRATION_TEST_GUIDE.md](./INTEGRATION_TEST_GUIDE.md)
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md)

