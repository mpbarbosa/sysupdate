# Incremental Change Guide

Most development in this repo is AI-assisted. This guide defines how to
structure Claude Code sessions so that each change is small enough to verify
before the next one begins.

## Goal

Decompose every development task into a named sequence of single-concern
changes — each with an explicit verification condition — before generating any
code. This keeps errors at the smallest possible scope and makes every diff
independently reviewable.

## What incremental change means here

Each change targets one concern: one snippet, one library function, one test
suite, one route, one CI job. A change is complete when its verification
condition passes. The next change does not begin until the current one is
committed.

It does **not** mean one function per commit. A snippet file + its YAML config
+ its BATS fixture is one concern — write them together. One concern that
happens to touch two files is still one change if both files serve the same
behavioral unit.

## The stacked change pattern for this repo

| Stage | Output | Verification condition |
| --- | --- | --- |
| 1. Interface | JSON event schema, YAML config keys, TypeScript types | A reviewer can write a consumer without reading any implementation |
| 2. Tests | BATS or Vitest tests — failing | `bats tests/bash/` or `npm run test` runs and fails for the right reason |
| 3. Implementation | Bash function, snippet, backend route, React component | Tests pass; `bash -n`; `tsc --noEmit`; `shellcheck` |
| 4. Observability | `emit_summary_event` call, `print_error` coverage | `--json-events` output shows the expected events |

Do not begin stage 3 until stage 2 is committed. Do not begin stage 4 until
stage 3 passes verification.

## Verification conditions for this repo

| Layer | Verification command |
| --- | --- |
| Bash syntax | `bash -n scripts/lib/*.sh scripts/upgrade_snippets/*.sh` |
| Bash lint | `shellcheck --severity=error --exclude=SC1091,SC2034 …` |
| Bash unit tests | `bats tests/bash/` |
| CLI integration | `bats tests/integration/` |
| TypeScript types | `npx tsc --noEmit` (from `web/`) |
| Web lint | `npm run lint` (from `web/`) |
| JS unit tests | `npm run test` (from `web/`) |
| Backend integration | `node --test tests/backend/server.test.mjs` |
| Full CI | Push to `main` — all three GitHub Actions workflows |

A change is verified when all commands relevant to the files it touches pass.

## Decomposing before starting a session

Before opening Claude Code for a feature, write the sequence of changes as
a list. For example, adding a new snippet:

1. Draft `<name>.yaml` config — verify `yq` can parse it
2. Write `update_<name>.sh` skeleton with `SNIPPET_ID`/`SNIPPET_NAME` headers
3. Add BATS fixture test — verify test fails
4. Implement the snippet body — verify test passes + shellcheck clean
5. Add `SUMMARY_ITEM_OVERRIDES` entry in `App.tsx`
6. Manual smoke test: `./scripts/system_update.sh --snippet <id> --check-only --json-events`

This sequence prevents the most common failure mode: implementing a snippet
and then discovering that the YAML key naming is inconsistent with existing
snippets, requiring a rewrite of both.

## Session scope rules

1. One prompt per concern. A prompt that says "write the snippet, its YAML,
   its tests, and update the dashboard" produces a diff that cannot be
   reviewed independently per concern.

2. Include the relevant interface in the prompt context. When asking for a
   new backend route, include the `startRun` function signature. When writing
   a snippet, include one existing config-driven snippet as the reference
   pattern.

3. Verify before extending. If a snippet's `compare_and_report_versions` call
   is generating wrong output, fix it before adding the `handle_update_prompt`
   logic that depends on it.

## Commit granularity

Each commit message should name one concern without "and":

```
# Good
feat: add RTK snippet with github version check
test: add BATS unit tests for compare_versions edge cases
fix: nodejs snippet invalid-option fallback for SYSUPDATE_PROMPT_INPUT
ci: add Phase 3 integration test workflow

# Too broad — split these
feat: add RTK snippet and update dashboard and fix nodejs bug
```

The Phase 1/2/3 CI/CD rollout in this repo was an example of correct phase
decomposition: each phase had a clear verification condition (lint passing,
unit tests passing, integration tests passing) before the next phase began.

## Review heuristics

### Concern count test

Does this diff address more than one behavioral concern? A diff that adds a
new snippet, updates the dashboard lookup maps, and fixes a bug in an existing
snippet is three concerns. Split it.

### Verification gate test

Was the previous change verified before this one was started? Check git log —
if two changes appear in sequence with no "tests pass" evidence between them,
the verification gate was skipped.

### Diff size test

Can the diff be summarized in one sentence? "Add `compare_and_report_versions`
call to the Kotlin snippet" — yes. "Various fixes and improvements" — no.

## Warning signs

- A commit message that requires "and" to describe its scope.
- Implementation changes committed before the tests that exercise them.
- A snippet submitted without a `--json-events` smoke test.
- A large Claude Code session that edits 10+ files in one pass without any
  intermediate verification.
- Backend route added without running `node --test tests/backend/server.test.mjs`.

## Positive signals

- CI passes on every commit to `main`.
- Each commit in `git log` names one concern.
- `bats tests/bash/` and `npm run test` are run locally before push.
- New snippets are tested with `--check-only --json-events` before commit.

## Related guides

- [LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md) — focused prompts keep
  context cost low per change.
- [OBSERVABILITY_GUIDE.md](./OBSERVABILITY_GUIDE.md) — the fourth stage
  (observability) of the stacked change pattern.
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md) — broader
  change quality expectations at review time.

## Summary checklist

- [ ] Work is decomposed into a named sequence before any generation begins.
- [ ] Each change targets one concern with one verification condition.
- [ ] Tests are committed before the implementation they exercise.
- [ ] All relevant verification commands pass before the next change starts.
- [ ] Each commit message names one concern without "and".
- [ ] New snippets are smoke-tested with `--check-only --json-events`.
- [ ] CI passes on every push to `main`.
