#!/bin/bash
#
# update_cursor_agent.sh - Cursor CLI Agent Update Manager
# SNIPPET_ID: cursor-agent
# SNIPPET_NAME: Cursor CLI Agent
#
# Handles updates for cursor-agent, the Cursor command-line agent.
# Companion to the `cursor` snippet (the Cursor IDE desktop app).
#
# cursor-agent is calendar-versioned (e.g. 2026.05.16-0338208) with no public
# release feed to diff against, so this snippet cannot pre-compute whether an
# update is available. It relies on the built-in `cursor-agent update`, which
# performs its own up-to-date check, and reports the before/after version.
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Reports current version from `cursor-agent --version`
#                            - Updates through the built-in `cursor-agent update` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

CURSOR_AGENT_DISPLAY_NAME="Cursor CLI Agent"

get_cursor_agent_version() {
    cursor-agent --version 2>/dev/null | head -1 | tr -d '[:space:]'
}

update_cursor_agent() {
    print_operation_header "Checking Cursor CLI Agent updates..."

    if ! check_app_installed "cursor-agent" "$CURSOR_AGENT_DISPLAY_NAME"; then
        print_status "Install Cursor CLI Agent: curl https://cursor.com/install -fsS | bash"
        ask_continue
        return 0
    fi

    local current_version
    current_version=$(get_cursor_agent_version)
    current_version="${current_version:-unknown}"
    print_status "Current version: $current_version"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - latest version is resolved by 'cursor-agent update'"
        emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
            "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        ask_continue
        return 0
    fi

    if ! prompt_yes_no "Update $CURSOR_AGENT_DISPLAY_NAME?"; then
        print_status "Skipping $CURSOR_AGENT_DISPLAY_NAME update"
        ask_continue
        return 0
    fi

    print_status "Updating $CURSOR_AGENT_DISPLAY_NAME..."
    local update_output
    if ! update_output=$(cursor-agent update 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -20
        print_error "Failed to update $CURSOR_AGENT_DISPLAY_NAME"
        emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
            "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        ask_continue
        return 1
    fi
    [ -n "$update_output" ] && echo "$update_output" | tail -20

    local new_version
    new_version=$(get_cursor_agent_version)
    new_version="${new_version:-$current_version}"
    print_status "Verified version: $new_version"
    emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
        "status" "up_to_date" "current_version" "$new_version" "latest_version" "$new_version"
    print_success "Cursor CLI Agent updated"
    ask_continue
}

update_cursor_agent
