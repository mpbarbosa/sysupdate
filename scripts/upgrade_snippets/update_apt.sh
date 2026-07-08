#!/bin/bash
#
# update_apt.sh - APT System Packages update snippet
# SNIPPET_ID: apt
# SNIPPET_NAME: APT System Packages
#
# Thin wrapper that exposes the orchestrator's core APT flow (apt_manager.sh)
# as a targetable snippet, so clients that act by SNIPPET_ID — e.g. the web
# dashboard's per-target "Upgrade" button — can apply APT updates the same way
# they apply snippet updates. apt has no standalone package to install, so it is
# not config-driven; it delegates to the existing apt_manager.sh functions
# rather than duplicating their logic.
#
# IMPORTANT: apt is normally handled directly by the orchestrator. Every snippet
# is also sourced during a normal full run, so to avoid checking/upgrading apt
# twice (and emitting duplicate apt_updates summary events), this snippet only
# acts when it is *explicitly* targeted via `--snippet apt`. During a normal run
# (empty SNIPPET_ID_FILTER) it is a deliberate no-op.
#
# Version: 0.1.0-alpha
# Date: 2026-07-07
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-07-07) - Initial alpha version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

if [ -z "$BLUE" ]; then
    source "$LIB_DIR/core_lib.sh"
fi
# apt_manager.sh is already sourced when run via the orchestrator; source it
# here only if its functions are not yet available (e.g. isolated invocation).
if ! declare -f check_updates_available >/dev/null 2>&1; then
    source "$LIB_DIR/apt_manager.sh"
fi

update_apt() {
    # Only act when explicitly targeted. During a normal full run the
    # orchestrator already runs the core apt flow, so acting here would
    # double-check/upgrade apt and emit a duplicate apt_updates event.
    if [ "${SNIPPET_ID_FILTER:-}" != "apt" ]; then
        return 0
    fi

    if [ "$(detect_package_manager)" != "apt" ]; then
        print_warning "APT is not the active package manager on this system - skipping"
        return 0
    fi

    if [ "${CHECK_ONLY_MODE:-false}" = true ]; then
        # Emits the apt_updates summary event without making changes.
        check_updates_available || true
        return 0
    fi

    # upgrade_packages re-checks (emitting the apt_updates summary) and applies
    # the available updates via sudo.
    upgrade_packages
}

update_apt
