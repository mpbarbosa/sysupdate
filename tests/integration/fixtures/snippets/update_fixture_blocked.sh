#!/bin/bash
# SNIPPET_ID: fixture-blocked
# SNIPPET_NAME: Fixture (Blocked)
#
# Deterministic fixture snippet for integration tests.
# Emits a version_check/invalid_installation event carrying a `remediation`
# field — the host-side fix a consumer (dashboard, widget) must display instead
# of offering a retry. No network calls.

_fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "$_fixture_dir/../../../.." && pwd)"
# shellcheck source=scripts/lib/upgrade_utils.sh
source "$_repo_root/scripts/lib/upgrade_utils.sh"

_update_fixture_blocked() {
    # Resolved from YAML through get_remediation, the way real snippets do it.
    # `local` so the fixture does not leak CONFIG_FILE into other snippets;
    # Bash's dynamic scoping still exposes it to get_remediation/get_config.
    # The value holds single quotes and a shell command — exactly the shape
    # real remediation text takes, so this exercises the JSON escaping too.
    local CONFIG_FILE="$_fixture_dir/fixture_blocked.yaml"

    local remediation
    remediation=$(get_remediation "needs_dpkg_configure" "")

    emit_summary_event "version_check" \
        "target" "Fixture Blocked" \
        "status" "invalid_installation" \
        "current_version" "unknown" \
        "latest_version" "unknown" \
        "remediation" "$remediation"
    print_warning "Fixture Blocked is installed but its package is unpacked, not configured"
}

_update_fixture_blocked
