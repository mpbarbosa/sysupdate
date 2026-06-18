# Naming Guide

This repo mixes Bash, TypeScript, Node.js, and YAML. Each layer has its own
naming conventions. This guide establishes the expected conventions per layer
so that any identifier is interpretable without reading its body.

## Goal

Every symbol, file, environment variable, snippet ID, and YAML key should be
interpretable from its name alone — by a developer, by Claude Code, and by
`grep`.

## Naming by layer

### Bash (scripts/lib/, scripts/upgrade_snippets/, scripts/system_update.sh)

| Symbol | Convention | Good example | Bad example |
| --- | --- | --- | --- |
| Function | `snake_case` verb + noun | `compare_versions`, `emit_summary_event` | `doCompare`, `handler` |
| Boolean function | `snake_case` + `_available`/`_enabled`/`_exists` or `check_*` | `check_updates_available` | `updates()`, `checkUp` |
| Local variable | `snake_case` noun | `current_version`, `snippets_dir` | `cv`, `d`, `tmp` |
| Global / env var | `UPPER_SNAKE_CASE` | `QUIET_MODE`, `CHECK_ONLY_MODE`, `RUN_ID` | `quiet`, `checkonly` |
| Env var set by user | `SYSUPDATE_` prefix + `UPPER_SNAKE_CASE` | `SYSUPDATE_SNIPPETS_DIR`, `SYSUPDATE_SCRIPT_PATH` | `SNIPPETS_DIR_OVERRIDE`, `SCRIPT` |
| Snippet function | `update_<name>` or `_update_<name>` (fixture prefix) | `update_rtk`, `_update_fixture_current` | `doRTK`, `rtk_upgrade` |
| Script file | `update_<name>.sh` or `<name>_manager.sh` | `update_firefox.sh`, `apt_manager.sh` | `firefox.sh`, `fxUpdate.sh` |
| Config YAML | `<name>.yaml` paired with `update_<name>.sh` | `rtk.yaml` | `rtk_config.yml`, `firefox.conf` |

### TypeScript / JavaScript (web/src/, web/backend/)

| Symbol | Convention | Good example | Bad example |
| --- | --- | --- | --- |
| Function | `camelCase` verb + noun | `applyRunSnapshot`, `sanitizeSnippetId` | `process`, `handle` |
| Boolean function | `camelCase` predicate: `is*`, `has*`, `can*` | `isRunActive()` | `checkRun()`, `runActive()` |
| Type / Interface | `PascalCase` domain noun | `UpdateItem`, `BackendRunSnapshot` | `IUpdateItem`, `UpdateData` |
| React component | `PascalCase` noun | `TerminalPanel`, `UpdateCard` | `Panel1`, `updateCard` |
| Constant | `UPPER_SNAKE_CASE` for configuration | `MAX_TERMINAL_LINES`, `DEFAULT_LOG_LIMIT` | `limit`, `maxLines` |
| Lookup map / config | `UPPER_SNAKE_CASE` | `SUMMARY_ITEM_OVERRIDES`, `PACKAGE_MANAGER_SUMMARY_CONFIG` | `overrides`, `pkgConfig` |
| File (module) | Describes the primary export | `utils.js`, `server.js`, `theme.ts` | `helpers.js`, `common.ts` |
| Test file | `<module>.test.<ext>` co-located | `utils.test.js`, `theme.test.ts` | `test_utils.js`, `utilsTests.ts` |

### YAML config (scripts/upgrade_snippets/*.yaml)

| Key | Convention | Good example | Bad example |
| --- | --- | --- | --- |
| All keys | `snake_case` | `github_owner`, `display_name` | `githubOwner`, `DisplayName` |
| Nested | consistent depth (not mixed flat + nested) | `version.source`, `version.command` | `versionSource`, `version_command` |

### BATS tests

| Symbol | Convention | Example |
| --- | --- | --- |
| Test name | Plain English: condition + expected outcome | `"compare_versions: equal versions returns 0"` |
| Setup variable | `UPPER_CASE` for repo paths, `lower_case` for locals | `REPO_ROOT`, `started_line` |

### Snippet IDs and SNIPPET_NAME

| Field | Convention | Example |
| --- | --- | --- |
| `SNIPPET_ID` | `kebab-case` | `rtk`, `fixture-current`, `nodejs` |
| `SNIPPET_NAME` | Human-readable title case | `RTK (Rust Token Killer)`, `Node.js` |

Snippet IDs are validated by `sanitizeSnippetId` in `utils.js` — they must
match `/^[a-zA-Z0-9._-]+$/`. This rules out spaces, slashes, and shell
metacharacters.

## Required rules

1. No generic unprefixed names: `helper`, `util`, `common`, `manager` are not
   acceptable as standalone Bash function or JS file names.
2. Every Bash function contains a verb.
3. Every env var set by users for configuration starts with `SYSUPDATE_`.
4. `SNIPPET_ID` values are `kebab-case` with no spaces or special characters.
5. YAML keys are `snake_case`; they must be consistent across all snippets
   (i.e., if one snippet uses `version.github_owner`, all must use
   `version.github_owner`, not `version.githubOwner`).
6. Test names in both BATS and Vitest describe the scenario and expected outcome.

## Review heuristics

### Cold name test

Given `compare_versions`, `emit_summary_event`, `applyRunSnapshot`,
`sanitizeSnippetId` — can you predict what each does without reading its body?
If a new name fails this test, rename before committing.

### Prefix consistency test

Are all user-facing env vars prefixed with `SYSUPDATE_`? Check any new env
var being added: `SYSUPDATE_SNIPPETS_DIR`, `SYSUPDATE_SCRIPT_PATH`,
`SYSUPDATE_LOG_FILE` — this is the pattern.

### YAML key consistency test

Read the YAML keys from any two existing snippets. If the new snippet's YAML
uses different key names for the same concept, align it with the established
convention.

## Positive signals

- `grep -r "SYSUPDATE_" scripts/` finds all user-tunable env vars in one pass.
- Snippet IDs are all `kebab-case` and pass `sanitizeSnippetId` without
  modification.
- A new BATS test name reads like a sentence with a clear outcome.
- TypeScript type names match the domain vocabulary used in `CLAUDE.md`.

## Warning signs

- A new env var without the `SYSUPDATE_` prefix that is meant for user configuration.
- A YAML config file that uses `camelCase` keys instead of `snake_case`.
- A JS file named `helpers.js` or `common.ts`.
- A Vitest or BATS test name that starts with "test" or names the function
  under test rather than the scenario.
- A Bash function named `do_update` or `run_check` without a specific subject.

## Related guides

- [LLM_CONTEXT_GUIDE.md](./LLM_CONTEXT_GUIDE.md) — precise names reduce
  context cost per encounter.
- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md) — a symbol that is hard
  to name probably has multiple responsibilities.
