# Claude Code Workflow Guide

This guide covers the operational patterns for Claude Code sessions in this
repo — how to structure a session, what to review before approving, how to
correct course, and which skills and verification commands apply at each stage.

For code structure patterns that keep sessions efficient, see
[LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md). This guide covers the session
itself, not the code it produces.

## Goal

Produce small, verifiable, independently reviewable diffs — one concern at a
time — with each change confirmed before the next begins.

## Before a session starts

Answer three questions before opening a conversation:

1. **What is the one concern?** A snippet, a route, a test, a guide update.
   Not a snippet and a dashboard update and a bug fix.
2. **What is the verification command?** Know which command confirms the change
   is correct before starting (see verification table below).
3. **Which directory am I editing?** The per-directory `CLAUDE.md` for that
   location loads automatically and surfaces the relevant guides and rules.

If you cannot answer all three, the task needs more scoping before starting.

## Prompt construction

A good prompt for this repo includes:

- **Desired behavior**, not implementation: "The snippet should emit
  `summary.updates` with status `up_to_date` when versions match" — not
  "call `compare_and_report_versions` with these arguments."
- **The reference pattern**: paste the header of one existing similar snippet
  or function signature. This anchors the output to established conventions.
- **Explicit scope**: "Add only X. Do not refactor Y. Do not add error handling
  for cases not described here."
- **The guide that applies** (by name): "Following the stacked change pattern
  in INCREMENTAL_CHANGE_GUIDE."

Omitting scope leads to "while I'm in here" additions — refactors, extra error
handling, new abstractions — none of which were asked for.

## Verification commands by layer

Run the command that matches the files changed before moving to the next task:

| Layer | Verification command |
| --- | --- |
| Bash syntax | `bash -n scripts/lib/*.sh scripts/upgrade_snippets/*.sh` |
| Bash lint | `shellcheck --severity=error --exclude=SC1091,SC2034 scripts/lib/*.sh scripts/upgrade_snippets/*.sh` |
| Bash unit tests | `bats tests/bash/` |
| CLI integration | `bats tests/integration/` |
| TypeScript types | `npx tsc --noEmit` (from `web/`) |
| Web lint | `npm run lint` (from `web/`) |
| JS unit tests | `npm run test` (from `web/`) |
| Backend integration | `node --test tests/backend/server.test.mjs` |
| Snippet smoke test | `./scripts/system_update.sh --snippet <id> --check-only --json-events` |

A change is not verified by type-checking or linting alone — run the test suite
for the relevant layer.

## Reviewing tool calls before approving

Claude Code shows a description before executing each tool call. Read it.

| Tool call type | What to check |
| --- | --- |
| File read | Is this file in scope for the stated task? |
| File write / edit | Does the description match the one concern? Is the scope narrow? |
| `git add` | Does the staged set match only the intended files? |
| `git commit` | Does the message name one concern without "and"? |
| `git push` | Is this the intended branch? Is now the right time to push? |
| Shell command | Is the command reversible? Does it match the task? |

**Read diffs before approving writes.** A diff that touches 5+ files for a
single-concern task should prompt a redirect, not an approve.

Watch for these additions that were not asked for:
- New error handling for cases the task does not describe
- Refactored surrounding code ("while I'm in here…")
- New abstraction layers or helper functions
- Extra imports or dependencies

If any of these appear, stop and redirect immediately — do not let them
accumulate across multiple tool calls.

## Available skills

Two skills are registered for this repo:

| Skill | When to use |
| --- | --- |
| `bump-version-stage-commit-push` | After each coherent change set: bumps `web/package.json` patch version, stages all, lints, commits, pushes |
| `import-adapt-guides` | When the guide library in `doc_template_lib` has new templates worth importing |

Invoke via `/bump-version-stage-commit-push` or `/import-adapt-guides` in any
session. The skill reads its own `SKILL.md` at `.claude/skills/<name>/`.

Use `bump-version-stage-commit-push` as the default commit workflow — it
enforces lint before commit and ensures `package-lock.json` stays in sync.

## Commit discipline

Each commit should name one concern. Use the conventional prefix that matches:

| Prefix | Use for |
| --- | --- |
| `feat:` | New user-visible behavior or new shipped snippet |
| `fix:` | Bug fix in existing behavior |
| `test:` | Adding or fixing tests |
| `docs:` | Guide or documentation changes only |
| `chore:` | Version bumps, CI config, repo ops, skills |
| `ci:` | GitHub Actions workflow changes |

A commit message requiring "and" to describe its scope is two commits.

## Course correction

When Claude produces something outside the stated scope, correct immediately —
do not let a wrong direction continue across multiple tool calls.

Effective corrections are specific:

- "Do not add error handling for tool-not-found here — that case is handled by
  the caller. Remove those lines and try again."
- "That refactors `emit_summary_event` which is outside scope. Revert that
  change and only add the new snippet file."
- "The commit message says 'and'. Split this into two separate commits: one for
  the snippet, one for the dashboard update."

Vague corrections ("that's wrong, try again") produce vague re-attempts.
Reference the specific guide or rule that was violated when possible.

## Keeping CLAUDE.md files accurate

The per-directory `CLAUDE.md` files are the primary context for each layer.
If they describe a pattern that no longer exists, future sessions will follow
the wrong model:

- After adding a new snippet type, update `scripts/upgrade_snippets/CLAUDE.md`
  if the pattern differs from existing snippets.
- After adding a new backend route category, update `web/backend/CLAUDE.md`.
- After extracting a React component from `App.tsx`, update `web/src/CLAUDE.md`
  (especially the "App.tsx over 400 lines" warning threshold).
- After importing new guides, update `docs/guides/README.md` and the relevant
  per-directory `CLAUDE.md` guide lists.

CLAUDE.md inaccuracy is silent — no lint catches it. Review CLAUDE.md files
whenever a refactor changes module boundaries or adds a new pattern.

## Session anti-patterns

### The "while I'm in here" drift

Claude refactors adjacent code, adds error handling for uncovered cases, or
cleans up style — none of which were asked for. Approve only what was
requested. Redirect with an explicit scope statement.

### The growing session

A single conversation accumulates 10+ file changes across 3 concerns. Each
new task in the same session inherits context from the previous ones, making
it harder to isolate failures. Use separate sessions for separate concerns, or
commit and verify between tasks.

### Skipping verification

Approving a commit before running the relevant verification command. If the
verification fails after commit, the fix becomes a separate commit and the
history becomes noisy. Verify first, commit after.

### Approving a broad `git add -A` blindly

`git add -A` stages everything, including generated files, credentials, and
unrelated work-in-progress. Always check `git status --short` before the
commit to confirm what will be included.

### Over-specifying implementation

Prompts that dictate exact function names, exact variable names, and exact
call order produce output that looks like what was asked for but may not be
correct. Describe behavior; let Claude choose implementation. Review the
diff to confirm the behavior is right.

## Positive signals

- Each session addresses one concern with one verification gate.
- Diffs are readable in under 30 seconds.
- Verification passes before the commit is made.
- Commit messages name one concern without "and".
- CLAUDE.md files are updated when architecture changes.
- The `bump-version-stage-commit-push` skill is the default commit path.
- Course corrections are made immediately and specifically.

## Warning signs

- A diff touching 5+ files for a stated single-concern task.
- A commit message with "and" in it.
- Verification being run after commit rather than before.
- A session that continues past the point where Claude produced something
  outside scope, without redirecting.
- `CLAUDE.md` files describing a module layout that was refactored weeks ago.

## Related guides

- [LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md) — structure code so sessions
  load less context per change.
- [INCREMENTAL_CHANGE_GUIDE.md](./INCREMENTAL_CHANGE_GUIDE.md) — stacked change
  pattern and verification conditions for each stage.
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md) — review
  expectations for what constitutes a complete, correct change.
- [NAMING_GUIDE.md](./NAMING_GUIDE.md) — naming rules that make prompts and
  diffs unambiguous.

## Summary checklist

- [ ] The session's one concern is defined before starting.
- [ ] The verification command for that concern is known before starting.
- [ ] Every file write is reviewed before approving.
- [ ] Verification passes before committing.
- [ ] Commit message names one concern without "and".
- [ ] `bump-version-stage-commit-push` skill is used for the commit.
- [ ] Course corrections are made immediately and reference a specific rule.
- [ ] CLAUDE.md files are updated if architecture changed.
