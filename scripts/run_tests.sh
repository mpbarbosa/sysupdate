#!/usr/bin/env bash
#
# run_tests.sh — run every sysupdate test suite locally (on the host).
#
# The local counterpart to run_tests_docker.sh: same suites and flags, but runs
# directly on this machine instead of in a throwaway container. Use this for a
# fast inner-loop check when bats/yq/shellcheck/node and the web deps are already
# installed; use run_tests_docker.sh for a clean-room run on a machine that only
# has Docker.
#
# Presentation (colored per-suite ✅/❌ + PASS/FAIL summary) is modeled on the
# run_tests.sh in the sibling `scripts` repo.
#
# Suites (in order, mirroring the three CI workflows):
#   1. bash -n syntax check + ShellCheck        (ci-bash: lint)
#   2. bats tests/bash/                          (ci-bash: test)
#   3. bats tests/integration/                   (ci-integration: cli)
#   4. node --test tests/backend/server.test.mjs (ci-integration: backend)
#   5. web: tsc --noEmit, eslint, vitest, build  (ci-web)
#
# Usage:
#   scripts/run_tests.sh [OPTIONS]
#
# Options:
#   --bash-only        Run only the Bash suites (1 + 2).
#   --integration-only Run only the integration suites (3 + 4).
#   --web-only         Run only the web suite (5).
#   --no-web           Skip the web suite (fastest for CLI-focused work).
#   -h, --help         Show this help and exit.
#
# Exit status: 0 if every selected suite passed, 1 otherwise.

# Note: `set -e` is intentionally NOT used — suites run to completion so the
# summary reflects every failure, not just the first.
# suite_* / require / web_deps_ready are invoked indirectly through run_suite,
# which shellcheck cannot trace (SC2329).
# shellcheck disable=SC2329
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

RUN_BASH=true
RUN_INTEGRATION=true
RUN_WEB=true

usage() {
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --bash-only)        RUN_INTEGRATION=false; RUN_WEB=false ;;
        --integration-only) RUN_BASH=false; RUN_WEB=false ;;
        --web-only)         RUN_BASH=false; RUN_INTEGRATION=false ;;
        --no-web)           RUN_WEB=false ;;
        -h|--help)          usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
    shift
done

PASSED=0
FAILED=0
FAILED_SUITES=()

# run_suite "Label" cmd args...  — run a suite, print its result, tally it.
run_suite() {
    local label="$1"
    shift
    printf '\n%b==> %s%b\n' "$CYAN" "$label" "$NC"
    if "$@"; then
        printf '%b✅ %s%b\n' "$GREEN" "$label" "$NC"
        ((PASSED++))
    else
        printf '%b❌ %s%b\n' "$RED" "$label" "$NC"
        ((FAILED++))
        FAILED_SUITES+=("$label")
    fi
}

# require <tool> <suite-label> — true if the tool exists, else warn + fail.
require() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    printf '%b⚠️  %s not found — needed for: %s%b\n' "$YELLOW" "$1" "$2" "$NC"
    return 1
}

# --- suite functions --------------------------------------------------------

suite_syntax() {
    require bash "bash -n" || return 1
    local rc=0 script
    for script in scripts/system_update.sh scripts/lib/*.sh scripts/upgrade_snippets/*.sh; do
        [ -f "$script" ] || continue
        if ! bash -n "$script"; then
            printf '%b   syntax error: %s%b\n' "$RED" "$script" "$NC"
            rc=1
        fi
    done
    return "$rc"
}

suite_shellcheck() {
    require shellcheck "ShellCheck" || return 1
    shellcheck \
        --severity=error \
        --exclude=SC1091,SC2034 \
        scripts/system_update.sh \
        scripts/lib/*.sh \
        scripts/upgrade_snippets/*.sh
}

# Resolve a runnable `bats`. bats is commonly installed as an npm global under a
# specific nvm Node version (e.g. ~/.nvm/versions/node/vX/bin/bats), which is not
# on PATH when the runner is spawned under a different Node version or a minimal
# environment (CI, the release pipeline). Fall back to the usual on-disk homes so
# the bats suites run instead of being reported as "not found".
# Echoes the bats path, or nothing if none is found.
resolve_bats() {
    if command -v bats >/dev/null 2>&1; then
        command -v bats
        return 0
    fi
    local candidate
    for candidate in \
        "$HOME/.local/bin/bats" \
        /usr/local/bin/bats \
        /usr/bin/bats \
        "${NVM_DIR:-$HOME/.nvm}"/versions/node/*/bin/bats; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

suite_bats_unit() {
    local bats_bin
    if ! bats_bin=$(resolve_bats); then
        printf '%b⚠️  bats not found (PATH or ~/.nvm/.../bin) — needed for: bats tests/bash/%b\n' "$YELLOW" "$NC"
        return 1
    fi
    "$bats_bin" tests/bash/
}

suite_bats_integration() {
    local bats_bin
    if ! bats_bin=$(resolve_bats); then
        printf '%b⚠️  bats not found (PATH or ~/.nvm/.../bin) — needed for: bats tests/integration/%b\n' "$YELLOW" "$NC"
        return 1
    fi
    "$bats_bin" tests/integration/
}

suite_backend() {
    require node "node --test" || return 1
    node --test tests/backend/server.test.mjs
}

# Guard the web suite on installed deps rather than silently `npm install`ing.
web_deps_ready() {
    require npm "web suite" || return 1
    if [ ! -d web/node_modules ]; then
        printf '%b⚠️  web/node_modules missing — run: npm --prefix web install%b\n' "$YELLOW" "$NC"
        return 1
    fi
    return 0
}

# Run web tools from inside web/ so they resolve web/tsconfig.json and the local
# binaries (running tsc from the repo root mis-parses its args).
suite_web_tsc()    { web_deps_ready && ( cd web && node_modules/.bin/tsc --noEmit ); }
suite_web_lint()   { web_deps_ready && ( cd web && npm run lint ); }
suite_web_vitest() { web_deps_ready && ( cd web && npm run test ); }
suite_web_build()  { web_deps_ready && ( cd web && npm run build ); }

# --- run selected suites ----------------------------------------------------

printf '%bsysupdate test suite (local)%b\n' "$CYAN" "$NC"
printf 'repo:   %s\n' "$REPO_ROOT"
printf 'suites: bash=%s integration=%s web=%s\n' "$RUN_BASH" "$RUN_INTEGRATION" "$RUN_WEB"

if [ "$RUN_BASH" = true ]; then
    run_suite "bash -n syntax check"          suite_syntax
    run_suite "ShellCheck (lib + snippets)"   suite_shellcheck
    run_suite "BATS unit (tests/bash)"        suite_bats_unit
fi

if [ "$RUN_INTEGRATION" = true ]; then
    run_suite "BATS integration (tests/integration)" suite_bats_integration
    run_suite "Backend bridge (node --test)"         suite_backend
fi

if [ "$RUN_WEB" = true ]; then
    run_suite "Web: type-check (tsc --noEmit)" suite_web_tsc
    run_suite "Web: lint (eslint)"             suite_web_lint
    run_suite "Web: unit (vitest)"             suite_web_vitest
    run_suite "Web: production build"          suite_web_build
fi

# --- summary ----------------------------------------------------------------

printf '\n%b── Summary ──%b\n' "$YELLOW" "$NC"
printf '%bPassed: %d%b\n' "$GREEN" "$PASSED" "$NC"
printf '%bFailed: %d%b\n' "$RED" "$FAILED" "$NC"

if [ "$FAILED" -eq 0 ]; then
    printf '%b🎉 All selected suites passed!%b\n' "$GREEN" "$NC"
    exit 0
fi

printf '%bFailed suites:%b\n' "$RED" "$NC"
for suite in "${FAILED_SUITES[@]}"; do
    printf '  - %s\n' "$suite"
done
exit 1
