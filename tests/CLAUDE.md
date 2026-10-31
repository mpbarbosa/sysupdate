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
- `tests/bash/hyprland_setup_prefix.bats` reaches `scripts/setup-hyprland-alternatives.sh` (a root,
  `/opt`-writing script) through `SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1`, sourcing it inside
  `bash -c` so its `set -euo pipefail` stays out of the BATS shell and BATS's own positional args
  never reach the script's arg parser. `DEST` is repointed at `$BATS_TEST_TMPDIR` — never real `/opt`
- `tests/integration/launcher_port_reuse.bats` drives `web/run_app.sh` against fake listeners
  (`python3 -m http.server`) on ports it asks the kernel for — never 5173/5174/4174, which are
  routinely busy on a developer's machine. It shadows `npm` and the browser openers with stubs on
  `PATH`, runs a *copy* of the launcher (the real one clears `web/dist/` in its own directory), and
  sources the launcher with `SYSUPDATE_RUN_APP_DEFINE_ONLY=1` to reach the probe helpers alone.
  It needs no root, so the launcher's `-i` path stays out of scope
- Fixture snippets call `compare_and_report_versions` with hardcoded versions — no network calls
- Capture JSON events (stderr only): `run bash -c "CMD 2>&1 1>/dev/null"`
- Validate JSON lines via stdin pipe: `echo "$line" | python3 -c "import json,sys; json.loads(sys.stdin.read())"`
- Not every stderr line is JSON — skip lines that don't start with `{`

## Guides for this directory

- [UNIT_TEST_GUIDE.md](../docs/guides/UNIT_TEST_GUIDE.md) — BATS and Vitest patterns, setup/teardown, fixture design
- [INTEGRATION_TEST_GUIDE.md](../docs/guides/INTEGRATION_TEST_GUIDE.md) — seam testing, env var overrides for isolation
- [OBSERVABILITY_GUIDE.md](../docs/guides/OBSERVABILITY_GUIDE.md) — JSON event schema being validated in `tests/integration/`
