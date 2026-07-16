# Defensive Coding Guide

Defensive coding is the practice of validating every external input at the
system boundary — HTTP request bodies, external command/API output, file
contents, browser storage — so that inner code (snippet update logic, the
child-process spawn, React render) can trust its inputs and focus on behavior.

## Goal

Reject invalid data at the point of entry and normalize missing values there,
so failures surface where they originate — at the boundary that read the bad
data — instead of propagating into a snippet's version comparison, a `dpkg -i`
invocation, or a React effect where the symptom no longer resembles the cause.

## What Defensive Coding Means Here

`sysupdate` has no rich domain model with constructor invariants. Its boundaries
are I/O boundaries: the CLI reads external command output, the backend bridge
reads HTTP bodies, and the dashboard reads WebSocket messages and `localStorage`.
So "defensive coding" here means:

1. Every value crossing a boundary is validated (or parsed into a known-good
   value) once, at that boundary, before any logic uses it.
2. Values that fail validation become an explicit, honest signal — `""` /
   `"unknown"` + an `unknown` summary event in Bash, `null` + HTTP 400 in the
   bridge, an empty `Set` in the frontend — never a silently coerced value.
3. Missing/absent external values are resolved at the boundary, not propagated.
4. Inner code is written to the validated shape and does not re-parse the raw
   input.

It does **not** mean sprinkling checks through every function. One thorough pass
at the boundary is correct; the same regex repeated in three snippets is not
(see [DRY Guide](./DRY_GUIDE.md)).

## Why It Matters

1. **AI-generated code is optimistic.** Claude Code drives most development here;
   without an explicit "validate at the boundary" convention, generated snippets
   assume `curl`/`dpkg`/redirect output is well-formed and skip the checks.
2. **This repo has already been bitten by boundary gaps.** Real fixes in the
   history: a version regex that lost the first digit of a two-digit major
   (`extract-version-greedy-major`), a `--short` vs `%.8s` SHA length mismatch
   that falsely reported git-commit updates, an empty commit hash from a
   load-balanced VSCode redirect chain, and a mixed-prefix git tag leaking out
   as a bogus "latest" (`select_highest_semver_tag`). Each was an
   unvalidated-external-input failure.
3. **The boundaries are untrusted by nature** — the GitHub REST API rate-limits
   and returns error JSON, CDNs return different redirect chains, `localStorage`
   can hold anything a prior version wrote. Trusting them raw produces
   misleading downstream errors.

## Required Rules

1. All input from external sources — `curl`/`gh` API responses, redirect
   `Location:` headers, `dpkg-query`/`apt-check` output, git tag refs, file
   contents, HTTP request bodies, WebSocket payloads, `localStorage` — is
   validated at the boundary before any logic uses it.
2. A value that fails validation produces an explicit signal, not a coerced
   value. Bash: return `""`/`"unknown"` and emit an `unknown` summary. Backend:
   `sanitizeSnippetId` → `null` → HTTP 400. Frontend: fall back to a safe empty
   value.
3. Absent external values (rate-limited API, missing stamp file, empty
   redirect) are resolved at the boundary — layered fallbacks in
   `upgrade_utils.sh`, `0.0.0` for a missing matchmaker stamp — never left to
   surface as a downstream comparison against `""`.
4. Programming errors (a snippet calling a helper with an empty `owner`/`repo`)
   fail fast with an empty return + non-zero status; they are not silently
   patched over deep in a comparison.
5. Inner code trusts the validated shape. The child-process spawn in
   `server.js` does not re-check the snippet id; it was already sanitized at the
   route.

## Boundary Reference

| Boundary | What crosses it | Where it is validated | Trust inside |
| --- | --- | --- | --- |
| HTTP request → backend | `POST /api/runs/upgrade` / `check-only` body `{ snippetId }` | `sanitizeSnippetId` in [`web/backend/utils.js`](../../web/backend/utils.js) (`/^[a-zA-Z0-9._-]+$/`), route returns 400 on `null` | `server.js` spawn trusts the id — no re-check |
| External command/API → CLI | `apt-check`, `dpkg-query`, `curl`/`gh` JSON, redirect URLs, git tags | Regex/format checks in `scripts/lib/apt_manager.sh` (`[[ "$total_updates" =~ ^[0-9]+$ ]]`), `select_highest_semver_tag` in `scripts/lib/upgrade_utils.sh`, per-snippet `version.regex` | Comparison/handlers trust the parsed version string |
| File → app | `run-history.jsonl`, matchmaker stamp file | `readLogHistory` handles missing file (`[]`) + malformed JSONL (catch); stamp read defaults to `0.0.0` | Callers get a well-formed list / version |
| Browser storage → frontend | `localStorage["sysupdate.autoUpdateIds"]` | `loadAutoUpdateIds` in [`web/src/App.tsx`](../../web/src/App.tsx) — `JSON.parse` in `try`, filter to strings, else empty `Set` | Auto-upgrade logic trusts a `Set<string>` |
| WebSocket → frontend | `snapshot` / `cli.event` messages | `JSON.parse` in `try`, `isRecord`/`asRunSnapshot` shape guards in `App.tsx` | Reducers trust the typed snapshot |

## Best Practices

### Parse, don't validate

Convert raw input into a known-good value at the boundary and pass *that* on.
`sanitizeSnippetId(value)` returns `string | null` — the route branches once on
`null`; everything downstream receives a valid id. `loadAutoUpdateIds()` returns
`Set<string>`, never raw JSON. `select_highest_semver_tag` emits only a bare
semver or nothing. See the "parse, don't validate" note in
[Low Coupling Guide](./LOW_COUPLING_GUIDE.md).

### Guard clauses at the top

Bash helpers that cannot act on empty inputs return early:

```bash
get_github_latest_remote_tag_fallback() {
    local owner="$1" repo="$2"
    if [ -z "$owner" ] || [ -z "$repo" ] || ! command -v git &>/dev/null; then
        echo ""
        return 1
    fi
    ...
}
```

### Resolve absence at the boundary

- Rate-limited GitHub API → layered fallback (`gh api`, then
  `git ls-remote` via `select_highest_semver_tag`) rather than a downstream
  `"" → unknown` surprise.
- Missing matchmaker stamp → `0.0.0` (only after `mm` is confirmed installed, so
  it never misreports an absent tool).
- Failed check → `emit_summary_event ... status "unknown"` — an honest event,
  not a fabricated version.

### Validation error vs. programming error

| Scenario | Mechanism | Result |
| --- | --- | --- |
| Malformed `snippetId` in an HTTP body | `sanitizeSnippetId` → `null` at the route | HTTP 400 (expected, declared) — see [Error Handling Guide](./ERROR_HANDLING_GUIDE.md) |
| Unparseable `apt-check` output | regex check in `check_updates_available` | `print_warning` + `unknown` summary (recoverable) |
| Helper called with empty `owner`/`repo` | guard clause | empty return + non-zero status (fail fast) |
| Absent external value (missing stamp, rate limit) | boundary fallback | explicit default / layered lookup |

## Review Heuristics

- **Boundary consistency:** does every new external read — a new `curl`/`gh`
  call, a new redirect parse, a new HTTP route, a new `localStorage` key — have
  a validation/parse step before its value is used?
- **Re-validation:** does the same version regex or id check appear in inner
  code that already received a validated value? Fix the boundary; drop the inner
  check (mind [DRY Guide](./DRY_GUIDE.md)).
- **Silent coercion:** is a malformed value being turned into a plausible-looking
  one (a truncated version, a prefixed tag treated as semver, `"abc"` → `0`)
  instead of rejected? That is the class of bug behind several past fixes.
- **Absence propagation:** can a rate-limited/empty external result reach a
  version comparison as `""`? Resolve it at the source.

## Positive Signals

- Boundary parsing is concentrated: `sanitizeSnippetId` (one place),
  `select_highest_semver_tag` (one place), `loadAutoUpdateIds` (one place),
  each snippet's single `version.regex`.
- Failed validation yields an explicit signal (400 / `unknown` summary / empty
  `Set`), and there is a rejection test for it (`sanitizeSnippetId` rejects
  `../etc/passwd`, `id;rm -rf`; `tests/bash/upgrade_utils.bats` covers version
  parsing and tag selection).
- Inner code takes validated shapes: the spawn takes a sanitized id; reducers
  take a typed snapshot.

## Warning Signs

- A new snippet pipes `curl` output straight into a comparison with no regex or
  fallback.
- A validation check copied into a snippet that already relies on
  `config_driven_version_check` having produced a clean version.
- Coercing malformed external data into a valid-looking value instead of
  emitting `unknown`.
- A frontend `JSON.parse` on storage/WebSocket data outside a `try` / shape
  guard.
- A backend route that reads `body.snippetId` without `sanitizeSnippetId`.

## Current repo reality

Boundary validation is **strong at the two most-exercised surfaces** — the
backend `snippetId` route (`sanitizeSnippetId`, tested) and the CLI's external
version resolution (`select_highest_semver_tag`, per-snippet regexes, layered
API fallbacks) — and now at the frontend `localStorage` boundary
(`loadAutoUpdateIds`).

Two honest gaps remain:

- **Bash's sourcing model encourages some re-guarding.** Each `lib/` module can
  be sourced standalone, so helpers defensively re-check `[ -z "$owner" ]`
  rather than fully trusting a caller. This is pragmatic, not a violation — but
  it means the "validate once, trust everywhere" ideal is partial in Bash.
- **No typed domain objects.** The guide's constructor-invariant advice does not
  apply; the closest equivalent is "parse into a known-good string/Set/typed
  snapshot at the boundary," which the repo does follow.

## Related Guides

- [Error Handling Guide](./ERROR_HANDLING_GUIDE.md) — classifying validation
  errors (400, recoverable `unknown`) vs. fail-fast programming errors across
  the Bash / Node / React layers.
- [Clean Architecture Guide](./CLEAN_ARCHITECTURE_GUIDE.md) — why validation
  lives in the outer layers (routes, snippet I/O) and not the stable core.
- [Low Coupling Guide](./LOW_COUPLING_GUIDE.md) — "parse, don't validate":
  typed values reduce coupling from repeated raw-input checks.
- [Unit Test Guide](./UNIT_TEST_GUIDE.md) — every invalid-input class needs a
  rejection test (`sanitizeSnippetId` cases; version/tag parsing in
  `tests/bash/upgrade_utils.bats`).
- [Naming Guide](./NAMING_GUIDE.md) — boundary parsers read as parsers
  (`sanitizeSnippetId`, `loadAutoUpdateIds`, `select_highest_semver_tag`).

## Summary Checklist

- [ ] Every external read (API/redirect/command output, file, HTTP body,
      WebSocket, `localStorage`) is validated or parsed at its boundary.
- [ ] Failed validation produces an explicit signal (400 / `unknown` summary /
      empty default), never a coerced value.
- [ ] Absent external values are resolved at the boundary (fallbacks, defaults),
      not propagated as `""`.
- [ ] Inner code receives validated shapes and does not re-parse raw input.
- [ ] Boundary parsing is single-source, not duplicated across snippets.
- [ ] Every invalid-input class has a rejection test.
