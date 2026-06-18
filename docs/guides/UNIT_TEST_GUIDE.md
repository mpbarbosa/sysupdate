# Unit Test Guide

This guide defines unit-testing expectations for `sysupdate`. It is
complementary to the integration and end-to-end guides: use it to shape fast,
deterministic tests for individual functions and modules in isolation.

## Current repo reality

Two unit test suites are active:

| Suite | Framework | Location | What it covers |
| --- | --- | --- | --- |
| Bash | BATS | `tests/bash/` | `compare_versions`, `normalize_version_for_comparison`, `extract_version`, `get_config`, `list_upgrade_snippets` |
| JavaScript | Vitest | `web/backend/utils.test.js`, `web/src/theme.test.ts` | `mapTerminalType`, `stripAnsi`, `trimArray`, `sanitizeSnippetId`, theme helpers |

Both suites run on every push via the GitHub Actions `CI – Bash` and
`CI – Web` workflows.

## Goal

Create tests that verify one unit of behavior at a time, run quickly, fail
predictably, and make refactoring safer — specifically the pure helper
functions and modules that the rest of the system depends on.

## What counts as a unit here

| Unit type | Examples |
| --- | --- |
| Pure Bash function | `compare_versions`, `normalize_version_for_comparison`, `extract_version` |
| Pure JS function | `stripAnsi`, `trimArray`, `sanitizeSnippetId`, `mapTerminalType` |
| Config reader | `get_config` with a fixture YAML file |
| Theme helper | `getThemeColorHex`, `getSeverityColor` |

Units that spawn child processes, write to disk, or make network calls are not
unit tests even if they use the same test runner — move those to
`tests/integration/`.

## Running the tests

```bash
# Bash unit tests
bats tests/bash/

# Run a single BATS file
bats tests/bash/core_lib.bats

# JS unit tests (from web/)
npm run test

# JS unit tests with coverage
npm run test:coverage
```

## Quality gates

### 1. Isolation gate

- A Bash unit test sources a library module directly and calls the function
  with explicit arguments.
- A Vitest unit test imports the function and supplies all its inputs —
  no network, no filesystem, no real subprocess.
- Shared `setup()` in BATS must not produce side effects visible to other
  tests; prefer `export NO_COLOR=1` and sourcing only the target module.

### 2. Determinism gate

- `compare_versions` and `normalize_version_for_comparison` are pure; their
  tests must not depend on system state, locale, or clock.
- Vitest tests for `stripAnsi`, `trimArray`, and `sanitizeSnippetId` are
  already fully deterministic — keep them that way.
- Do not add sleep, random seeds, or file-system state to a unit test.

### 3. Behavior gate

- Assert what the function returns or what global it sets, not how many
  lines it executes.
- For `compare_versions`, assert the numeric exit code: `0` = equal,
  `1` = v1 newer, `2` = v2 newer.
- For `sanitizeSnippetId`, assert the return value and null cases — not which
  regex branch was taken.

### 4. Naming gate

**BATS:** Names should read as plain sentences describing the scenario and
expected outcome:

```bash
@test "compare_versions: minor segment correctly ordered (1.10 > 1.9)" {
```

**Vitest:** Use `describe` + `it` with outcome-first phrasing:

```javascript
it('rejects id with path traversal → null', () => {
```

### 5. Error-path gate

- `sanitizeSnippetId` tests cover path traversal, command injection, spaces,
  non-string inputs, and empty string — this is the right model for security
  boundary functions.
- `compare_versions` tests cover pre-release suffixes, leading `v`, trailing
  zeros, and major version bumps.
- Every newly added pure function should get at least one invalid-input test.

### 6. Execution gate

```bash
bats tests/bash/     # completes in under 5 seconds locally
npm run test         # completes in under 10 seconds locally
```

If a test is slow, it is probably testing real I/O — move it to
`tests/integration/`.

## File layout

```
tests/
  bash/
    core_lib.bats          ← tests for scripts/lib/core_lib.sh
    upgrade_utils.bats     ← tests for scripts/lib/upgrade_utils.sh
    fixtures/
      sample.yaml          ← fixture YAML for get_config tests

web/
  backend/
    utils.test.js          ← tests for web/backend/utils.js (co-located)
  src/
    theme.test.ts          ← tests for web/src/theme.ts (co-located)
```

Co-locate JS tests with the file they exercise. Keep BATS tests in
`tests/bash/` (separate from `scripts/`) so the lint workflow can distinguish
them.

## Fixture pattern for BATS

```bash
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export NO_COLOR=1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/core_lib.sh"
}

@test "compare_versions: equal versions returns 0" {
    run compare_versions "1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}
```

## Pure function pattern for Vitest

```javascript
import { describe, it, expect } from 'vitest';
import { sanitizeSnippetId } from './utils.js';

describe('sanitizeSnippetId', () => {
  it('accepts a simple alphanumeric id', () => {
    expect(sanitizeSnippetId('rtk')).toBe('rtk');
  });

  it('rejects path traversal → null', () => {
    expect(sanitizeSnippetId('../etc/passwd')).toBeNull();
  });
});
```

## Warning signs

- A BATS test runs `apt-get`, `snap`, `curl`, or any real tool — that is an
  integration test, not a unit test.
- A Vitest test imports from `server.js` directly or spawns a child process —
  that is an integration test.
- A test is flaky because it reads from a real file path that may not exist.
- Multiple unrelated assertions in one test.

## Related guides

- [INTEGRATION_TEST_GUIDE.md](./INTEGRATION_TEST_GUIDE.md) for tests that cross
  real process, file, or network boundaries.
- [CODE_QUALITY_CONTROL_GUIDE.md](./CODE_QUALITY_CONTROL_GUIDE.md) for broader
  change quality expectations.
- [HIGH_COHESION_GUIDE.md](./HIGH_COHESION_GUIDE.md) for keeping functions
  narrow enough to be testable without mocking.

## Summary checklist

- [ ] Each test verifies one focused behavior.
- [ ] No live I/O: no network, no spawned processes, no real filesystem access.
- [ ] Outcomes are deterministic across machines and locales.
- [ ] Names describe the scenario and expected outcome (not the function name).
- [ ] Error paths and boundary values are covered.
- [ ] Tests complete in under 10 seconds locally.
- [ ] Integration concerns are in `tests/integration/`, not in `tests/bash/`.
