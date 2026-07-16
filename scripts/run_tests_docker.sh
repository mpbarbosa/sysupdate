#!/usr/bin/env bash
#
# run_tests_docker.sh — run every sysupdate test suite inside a Docker container.
#
# Mirrors the three CI workflows (ci-bash, ci-integration, ci-web) in one
# throwaway container so the full suite can be exercised on any machine that has
# Docker, without installing bats/yq/shellcheck/node locally.
#
# Suites (in order):
#   1. bash -n syntax check + ShellCheck        (ci-bash: lint)
#   2. bats tests/bash/                          (ci-bash: test)
#   3. bats tests/integration/                   (ci-integration: cli)
#   4. node --test tests/backend/server.test.mjs (ci-integration: backend)
#   5. web: tsc --noEmit, eslint, vitest, build  (ci-web)
#
# Usage:
#   scripts/run_tests_docker.sh [OPTIONS]
#
# Options:
#   --bash-only        Run only the Bash suites (1 + 2).
#   --integration-only Run only the integration suites (3 + 4).
#   --web-only         Run only the web suite (5).
#   --no-web           Skip the web suite (fastest for CLI-focused work).
#   --keep             Do not remove the container after the run.
#   -h, --help         Show this help and exit.
#
# Environment:
#   NODE_IMAGE   Base image to use (default: node:26-bookworm). node:26 is
#                Debian-based, matching web/.node-version (26.3.0) and giving
#                apt access to bats/yq/shellcheck.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_IMAGE="${NODE_IMAGE:-node:26-bookworm}"

RUN_BASH=true
RUN_INTEGRATION=true
RUN_WEB=true
KEEP_CONTAINER=false

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --bash-only)        RUN_INTEGRATION=false; RUN_WEB=false ;;
        --integration-only) RUN_BASH=false; RUN_WEB=false ;;
        --web-only)         RUN_BASH=false; RUN_INTEGRATION=false ;;
        --no-web)           RUN_WEB=false ;;
        --keep)             KEEP_CONTAINER=true ;;
        -h|--help)          usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
    shift
done

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker is not installed or not on PATH" >&2
    exit 1
fi

# The in-container test driver. Runs as a single bash -euo pipefail script so a
# failure in any suite aborts with a non-zero exit code that docker propagates.
build_runner() {
    cat <<'RUNNER'
set -euo pipefail

section() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

section "Installing test dependencies (bats, yq, shellcheck)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq bats yq shellcheck >/dev/null

cd /work

if [ "${RUN_BASH:-true}" = true ]; then
    section "bash -n syntax check"
    bash -n scripts/system_update.sh
    bash -n scripts/lib/*.sh
    bash -n scripts/upgrade_snippets/*.sh

    section "ShellCheck"
    shellcheck \
        --severity=error \
        --exclude=SC1091,SC2034 \
        scripts/system_update.sh \
        scripts/lib/*.sh \
        scripts/upgrade_snippets/*.sh

    section "BATS unit tests (tests/bash/)"
    bats tests/bash/
fi

if [ "${RUN_INTEGRATION:-true}" = true ]; then
    section "BATS integration tests (tests/integration/)"
    bats tests/integration/
fi

if [ "${RUN_INTEGRATION:-true}" = true ] || [ "${RUN_WEB:-true}" = true ]; then
    section "Installing web dependencies (npm ci)"
    npm --prefix web ci
fi

if [ "${RUN_INTEGRATION:-true}" = true ]; then
    section "Backend bridge integration tests (node --test)"
    node --test tests/backend/server.test.mjs
fi

if [ "${RUN_WEB:-true}" = true ]; then
    section "Web: type-check (tsc --noEmit)"
    npm --prefix web exec tsc -- --noEmit

    section "Web: lint (eslint)"
    npm --prefix web run lint

    section "Web: unit tests (vitest)"
    npm --prefix web run test

    section "Web: production build"
    npm --prefix web run build
fi

section "All selected suites passed"
RUNNER
}

DOCKER_RM=(--rm)
if [ "$KEEP_CONTAINER" = true ]; then
    DOCKER_RM=(--name sysupdate-tests)
fi

echo "Image:        $NODE_IMAGE"
echo "Repo:         $REPO_ROOT"
echo "Suites:       bash=$RUN_BASH integration=$RUN_INTEGRATION web=$RUN_WEB"

# Mount the repo read-only, copy it to a writable /work inside the container so
# npm ci / vite build artifacts never leak back onto the host tree, then run the
# suite driver (passed via env to avoid nested-quoting headaches).
exec docker run "${DOCKER_RM[@]}" \
    -e RUN_BASH="$RUN_BASH" \
    -e RUN_INTEGRATION="$RUN_INTEGRATION" \
    -e RUN_WEB="$RUN_WEB" \
    -e CI=true \
    -e SYSUPDATE_TEST_RUNNER="$(build_runner)" \
    -v "$REPO_ROOT":/repo:ro \
    "$NODE_IMAGE" \
    bash -euo pipefail -c 'cp -a /repo /work && bash -euo pipefail -c "$SYSUPDATE_TEST_RUNNER"'
