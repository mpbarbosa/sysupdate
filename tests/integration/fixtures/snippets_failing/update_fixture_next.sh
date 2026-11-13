#!/bin/bash
# SNIPPET_ID: fixture-next
# SNIPPET_NAME: Fixture (Next)
#
# Deterministic fixture snippet for integration tests: it succeeds, and its
# only job is to prove that a snippet failing before it does not stop the run.
#
# Its filename must sort AFTER update_fixture_failing.sh, because
# source_upgrade_snippets walks the directory with a plain *.sh glob. Rename
# either file and this stops testing what it claims to test — the integration
# test asserts this snippet's event is present, which is only true if the loop
# carried on past the failure.

_fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "$_fixture_dir/../../../.." && pwd)"
# shellcheck source=scripts/lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$_repo_root/scripts/lib/upgrade_utils.sh"

_update_fixture_next() {
    emit_summary_event "version_check" \
        "target" "Fixture Next" \
        "status" "up_to_date" \
        "current_version" "3.0.0" \
        "latest_version" "3.0.0"
    print_status "Fixture Next ran after the failing snippet"
}

_update_fixture_next
