# LLM Context Efficiency Guide

Claude Code sessions drive most development in this repo. Code structure
determines how much context a session must load to answer any question or
make any change. This guide describes how to keep that context cost low.

## Goal

Structure code and documentation so that any change Claude Code is asked to
make can be understood from the minimum necessary context — fewer files loaded,
faster accurate edits, less risk of cross-file collateral damage.

## Why it matters here

This is a mixed-language repo (Bash + TypeScript + Node.js + YAML) with three
distinct layers: CLI core, backend bridge, and web frontend. Every session must
figure out where a change belongs before making it.

Without clear boundaries:
- Sessions load `scripts/system_update.sh`, `scripts/lib/*.sh`, and
  `web/backend/server.js` just to answer a focused question about one snippet
- Inconsistent snippet patterns force re-reading every snippet to understand what
  a new one should look like
- Generic names (`helper`, `util`) require body-reads on every encounter

## Context loading map for this repo

| Question | Minimum files needed |
| --- | --- |
| "How does a snippet work?" | One existing snippet + `upgrade_utils.sh` header |
| "What does `compare_versions` return?" | `scripts/lib/core_lib.sh` signature |
| "How does the backend bridge start a run?" | `web/backend/server.js` `startRun()` |
| "What does the web dashboard show?" | `web/src/App.tsx` state model + `web/src/types.ts` |
| "What JSON events does the CLI emit?" | `scripts/lib/core_lib.sh` `emit_event` + `emit_summary_event` |
| "Where does the version of `rtk` come from?" | `scripts/upgrade_snippets/rtk.yaml` |

If answering a question requires more than 3–4 files, the boundary is too wide.

## Required rules

### 1. `CLAUDE.md` is the primary context file

`CLAUDE.md` and `web/CLAUDE.md` are loaded on every session start. They must
accurately describe the architecture and point to the right files for each
concern. Stale CLAUDE.md entries are the single highest-cost context bug in
this repo — keep them current whenever architecture changes.

### 2. Snippets must be self-describing

Every snippet must declare `# SNIPPET_ID:` and `# SNIPPET_NAME:` in its
header. These headers are the only mechanism by which `list_upgrade_snippets`
and `source_upgrade_snippets` identify a snippet. A snippet without them is
invisible to the system and to sessions reading the directory.

### 3. Snippets must follow a consistent structural pattern

All config-driven snippets follow the same structure:
1. Header comments (`SNIPPET_ID`, `SNIPPET_NAME`)
2. Source `upgrade_utils.sh`
3. Define an update function
4. Set `CONFIG_FILE` to the paired YAML
5. Call `config_driven_version_check` + `handle_update_prompt`
6. Call the function at the bottom

Structural divergence requires a session to re-read the snippet to understand
it rather than generalizing from the pattern. Plain manager snippets
(`cargo_manager.sh`, `pip_manager.sh`) are the exception — they define their
own update functions and document this in their own comment headers.

### 4. Utility functions must have semantic names

`utils.js` in the backend is a named exception — it is the deliberate home for
pure helpers. Inside it, each function must have a self-describing name:
`sanitizeSnippetId`, `stripAnsi`, `trimArray`, `mapTerminalType` — not
`clean`, `transform`, or `map`.

### 5. YAML config keys must be consistent across snippets

All config-driven snippets read from YAML using the same key paths
(`application.name`, `version.source`, `version.command`, `update.method`).
Introducing a new YAML structure for one snippet forces a session to read
that specific YAML rather than generalizing from any existing one.

### 6. `web/backend/utils.js` must stay pure

`utils.js` has no I/O, no imports from Node built-ins, and no side effects.
Its context cost is bounded: a session can understand it completely from its
exports. Do not add I/O or stateful logic to `utils.js` — that belongs in
`server.js`.

## Context cost reference for this repo

| Code property | Context cost |
| --- | --- |
| `scripts/lib/upgrade_utils.sh` (27 KB) | High for full reads; low if querying specific function |
| `web/src/App.tsx` (24 KB) | High — consider splitting further |
| A config-driven snippet (~100 lines) | Low — pattern generalizes from one example |
| A paired `.yaml` file | Very low — fully declarative |
| `web/backend/utils.js` | Very low — pure, no imports |
| `scripts/lib/core_lib.sh` emit functions | Low — consistent emit_event signature |

## Review heuristics

### Session-start test

After `CLAUDE.md` is loaded, can a session correctly answer "where does this
module belong?" for a proposed new snippet, backend route, or React component
— without reading any other file? If not, `CLAUDE.md` needs updating.

### Pattern recognition test

Pick two existing config-driven snippets. Do they follow an identical
structural template? If an LLM would need to re-read both to generate a third,
the pattern has diverged.

### Cold name test

Given only `sanitizeSnippetId`, `compare_versions`, `emit_summary_event`,
`applyRunSnapshot` — can you predict what each does without reading its body?
That is the target naming density for all new functions.

### Dependency radius test

A new snippet should depend only on `upgrade_utils.sh` (which depends on
`core_lib.sh`). If a snippet imports additional modules or calls functions from
`apt_manager.sh`, its dependency radius has grown unnecessarily.

## Warning signs

- A snippet that sources multiple library files beyond `upgrade_utils.sh`.
- A YAML key that appears in only one snippet with no equivalent in any other.
- A session that must read all 35+ snippets to understand what the next one
  should look like — this means the pattern documentation in `CLAUDE.md` is
  insufficient.
- `web/src/App.tsx` growing beyond 600 lines without a component extraction.
- Functions in `utils.js` that import from `node:fs` or `node:child_process`.

## Related guides

- [CLEAN_ARCHITECTURE_GUIDE.md](./CLEAN_ARCHITECTURE_GUIDE.md) — layering keeps
  context cost bounded per layer.
- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md) — single-responsibility
  modules are cheaper to load.
- [LOW_COUPLING_GUIDE.md](./LOW_COUPLING_GUIDE.md) — sparse import graphs keep
  the dependency radius per question small.
- [INCREMENTAL_CHANGE_GUIDE.md](./INCREMENTAL_CHANGE_GUIDE.md) — single-concern
  prompts use less context than multi-concern ones.

## Summary checklist

- [ ] `CLAUDE.md` and `web/CLAUDE.md` accurately describe the current
      architecture and module locations.
- [ ] Every snippet has `# SNIPPET_ID:` and `# SNIPPET_NAME:` headers.
- [ ] Config-driven snippets follow the same structural template.
- [ ] YAML config keys are consistent across all snippets.
- [ ] `web/backend/utils.js` contains only pure functions with no I/O.
- [ ] Every public function name is interpretable without reading its body.
- [ ] Sessions are not required to load the entire snippet directory to add
      one new snippet.
