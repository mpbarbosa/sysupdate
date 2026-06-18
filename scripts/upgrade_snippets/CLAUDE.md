# CLAUDE.md — scripts/upgrade_snippets/

This directory is the config-driven plugin system for per-tool update logic.
Each snippet is a `.sh` file (optionally paired with a `.yaml` config).

## Key rules for this directory

- File naming: `update_<name>.sh` + `<name>.yaml` (paired config)
- Every `.sh` must declare `# SNIPPET_ID: kebab-case-id` and `# SNIPPET_NAME: Human Title` header comments
- `SNIPPET_ID` must be kebab-case and pass `sanitizeSnippetId` (`/^[a-zA-Z0-9._-]+$/`)
- YAML keys are `snake_case` — consistent with all other snippet YAML files
- Source `lib/upgrade_utils.sh`; rely on `compare_and_report_versions` to emit `summary.updates` events
- Every snippet must emit at least one `summary.updates` event (call `compare_and_report_versions`)
- Tool-not-found: `print_warning` + `return 0` (not an error); update failure: `print_error` + `return 1`
- No changes to `system_update.sh` needed — snippets are auto-discovered

## Smoke test after adding/editing a snippet

```bash
./scripts/system_update.sh --snippet <id> --check-only --json-events
shellcheck scripts/upgrade_snippets/update_<name>.sh
```

## Guides for this directory

- [NAMING_GUIDE.md](../../docs/guides/NAMING_GUIDE.md) — snippet IDs, file names, YAML keys, env var prefix
- [OBSERVABILITY_GUIDE.md](../../docs/guides/OBSERVABILITY_GUIDE.md) — `summary.updates` event rules, `emit_summary_event` usage
- [INCREMENTAL_CHANGE_GUIDE.md](../../docs/guides/INCREMENTAL_CHANGE_GUIDE.md) — stacked change pattern for adding snippets
- [ERROR_HANDLING_GUIDE.md](../../docs/guides/ERROR_HANDLING_GUIDE.md) — tool-not-found vs update-failure handling
