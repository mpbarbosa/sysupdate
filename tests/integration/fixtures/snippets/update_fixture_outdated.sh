#!/bin/bash
# SNIPPET_ID: fixture-outdated
# SNIPPET_NAME: Fixture (Outdated)
#
# Deterministic fixture snippet for integration tests.
# Emits a version_check/update_available event — no network calls.

_fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "$_fixture_dir/../../../.." && pwd)"
# shellcheck source=scripts/lib/upgrade_utils.sh
source "$_repo_root/scripts/lib/upgrade_utils.sh"

_update_fixture_outdated() {
    compare_and_report_versions "1.0.0" "2.0.0" "Fixture Outdated"
    local _status=$?
    handle_update_prompt "Fixture Outdated" "$_status" "echo FIXTURE_UPDATE_CALLED"
}

_update_fixture_outdated
