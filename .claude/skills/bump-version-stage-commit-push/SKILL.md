---
name: bump-version-stage-commit-push
description: >
  Bump the project version, track and stage all intended files, generate an
  appropriate commit message from the staged diff, commit, and push the current
  branch. Use this skill when the user asks for a version bump plus full git
  release flow in one pass.
---

## Overview

This skill performs a lightweight release-style git workflow for this
repository:

1. Bump the version
2. Stage the intended files
3. Validate the repo state
4. Generate a commit message from the staged changes
5. Commit
6. Push the current branch

For this project, `web/package.json` is the canonical version source and
`web/package-lock.json` must stay in sync with it. The Bash script files under
`scripts/` carry their own `# Version:` header comments — do **not** bump those
manually; they track individual module versions independently.

---

## Canonical version files

Update through npm versioning (from the `web/` directory) instead of manual editing:

| File | Rule |
|------|------|
| `web/package.json` | Canonical project version for the web layer |
| `web/package-lock.json` | Must match `web/package.json` after version bump |

Preferred command (run from repo root):

```bash
(cd web && npm version patch --no-git-tag-version)
```

If the user explicitly asks for a different bump level, use one of:

```bash
(cd web && npm version minor --no-git-tag-version)
(cd web && npm version major --no-git-tag-version)
```

---

## Preconditions

Before committing:

1. Confirm the repo exists and the current branch is known.
2. Inspect `git status --short`.
3. Decide whether there are already pending user changes that should be included.
4. Never discard unrelated user changes.

Stage all changes with:

```bash
git add -A
```

---

## Execution flow

### Step 1 — Inspect repo state

Run:

```bash
git status --short
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name '@{u}'
```

If upstream is missing, stop and report that push cannot proceed until the
branch has an upstream.

### Step 2 — Bump the version

Default to a patch bump unless the user specifies otherwise:

```bash
(cd web && npm version patch --no-git-tag-version)
```

### Step 3 — Stage changes

Stage the full intended set:

```bash
git add -A
```

### Step 4 — Validate

Run the web linter before committing:

```bash
(cd web && npm run lint)
```

If validation fails, fix the issue before committing.

### Step 5 — Review staged scope

Use:

```bash
git diff --cached --stat --summary
```

Generate the commit message from the staged diff, not from guesswork.

### Step 6 — Generate commit message

Use a short conventional-style subject that reflects the staged scope.

Examples:

- `chore: bump version and add CI workflows`
- `feat: add Phase 3 integration tests`
- `fix: resolve invalid option in nodejs snippet`
- `docs: update architecture notes`

Heuristics:

- Use `chore:` for version bumps, scripts, deployment helpers, and repo ops.
- Use `feat:` for user-facing behavior or new shipped functionality.
- Use `fix:` for bug fixes.
- Use `docs:` for documentation-only changes.

### Step 7 — Commit

Commit with the generated message and include the required trailer:

```bash
git commit -m "GENERATED_SUBJECT" -m "Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Step 8 — Push

Push the current branch:

```bash
git push origin "$(git branch --show-current)"
```

---

## Safety rules

- Do **not** amend previous commits unless the user explicitly asks.
- Do **not** use destructive git commands like `reset --hard`.
- Do **not** invent a version string manually when npm can update it safely.
- Do **not** claim success before push completes.
- If staged content is much broader than the user likely intended, inspect it
  and choose a message that honestly reflects the full scope.
- Pushing to the remote is a shared, hard-to-reverse action — confirm with the
  user before Step 8 unless they have already authorized pushing in this
  conversation.
