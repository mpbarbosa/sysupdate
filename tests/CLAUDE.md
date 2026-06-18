# CLAUDE.md — tests/

Three test suites live here:

| Directory | Framework | Run command |
| --- | --- | --- |
| `tests/bash/` | BATS | `bats tests/bash/` |
| `tests/integration/` | BATS | `bats tests/integration/` |
| `tests/backend/` | node:test | `node --test tests/backend/server.test.mjs` |

## Key rules for this directory

- BATS test names use plain English: `"function: condition returns expected outcome"`
- `setup()` in BATS: source the module under test, `export NO_COLOR=1`, set `REPO_ROOT`
- Integration tests use `SYSUPDATE_SNIPPETS_DIR` to point at `tests/integration/fixtures/snippets/` — never real snippets
- Backend tests use `SYSUPDATE_SCRIPT_PATH` to point at `tests/backend/fixtures/stub_script.sh` — never the real script
- Fixture snippets call `compare_and_report_versions` with hardcoded versions — no network calls
- Capture JSON events (stderr only): `run bash -c "CMD 2>&1 1>/dev/null"`
- Validate JSON lines via stdin pipe: `echo "$line" | python3 -c "import json,sys; json.loads(sys.stdin.read())"`
- Not every stderr line is JSON — skip lines that don't start with `{`

## Guides for this directory

- [UNIT_TEST_GUIDE.md](../docs/guides/UNIT_TEST_GUIDE.md) — BATS and Vitest patterns, setup/teardown, fixture design
- [INTEGRATION_TEST_GUIDE.md](../docs/guides/INTEGRATION_TEST_GUIDE.md) — seam testing, env var overrides for isolation
- [OBSERVABILITY_GUIDE.md](../docs/guides/OBSERVABILITY_GUIDE.md) — JSON event schema being validated in `tests/integration/`
