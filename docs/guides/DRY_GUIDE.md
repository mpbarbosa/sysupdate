# DRY Guide

Use DRY in `sysupdate` so each update rule, config value, and documentation
statement has one authoritative home.

## Goal

A change to one fact should require one edit.

## What this means in `sysupdate`

The repo already has natural single-source-of-truth locations:

- shared shell behavior in `scripts/lib/core_lib.sh`
- shared snippet behavior in `scripts/lib/upgrade_utils.sh`
- snippet-specific config in `scripts/upgrade_snippets/*.yaml`
- frontend/backend contract types in `web/src/types.ts`
- project architecture and validation commands in `CLAUDE.md`

Prefer extending those sources over copying logic into a new layer.

## Required rules

1. Reuse shared Bash helpers before adding bespoke copies.
2. Keep repeated snippet config in YAML or shared helpers, not duplicated shell
   branches.
3. Keep event names and payload shapes aligned between the CLI, backend, and UI.
4. Do not duplicate version parsing or prompt handling if a shared helper can
   own it.
5. Write engineering guidance once and cross-link to it from related docs.

## Positive signals

- a new version-comparison rule is added once in shared code
- several snippets reuse one helper instead of maintaining parallel fixes
- a backend/UI contract change is represented once in typed definitions
- docs point back to one guide instead of restating it

## Warning signs

- comments like "keep in sync" guard duplicated script logic
- the same message or status mapping is copied in Bash, backend, and UI
- two docs explain the same convention in different words
- changing one snippet rule requires grep-driven edits across many files

## Repo-specific examples

### Prefer

- `emit_summary_event` over per-snippet custom event formatting
- `run_with_sudo` over direct scattered `sudo` handling
- `get_config` + YAML over hard-coded repeated strings
- a shared frontend summary mapping over card-by-card special cases when the
  rule is actually generic

### Avoid

- duplicating package-manager update semantics in the web client
- re-copying install-method detection into several snippets
- restating validation commands in many docs when one source can be referenced

## Related guides

- [LOW_COUPLING_GUIDE.md](./LOW_COUPLING_GUIDE.md)
- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md)
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md)

