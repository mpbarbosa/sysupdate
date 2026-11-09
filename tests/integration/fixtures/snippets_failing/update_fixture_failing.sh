#!/bin/bash
# SNIPPET_ID: fixture-failing
# SNIPPET_NAME: Fixture (Failing)
#
# Deterministic fixture snippet for integration tests: an update that runs and
# fails. It stands in for the real case that exposed the bug — a Postman
# update whose backup step could not acquire sudo — without needing sudo, the
# network, or anything outside the repository.
#
# The entry call is the file's last command, so its status is the status of
# `source`, which is what source_snippet_isolated reports upward.

_fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "$_fixture_dir/../../../.." && pwd)"
# shellcheck source=scripts/lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$_repo_root/scripts/lib/upgrade_utils.sh"

_update_fixture_failing() {
    emit_summary_event "version_check" \
        "target" "Fixture Failing" \
        "status" "update_available" \
        "current_version" "1.0.0" \
        "latest_version" "2.0.0"
    print_error "Fixture Failing could not complete its update"
    return 1
}

_update_fixture_failing
