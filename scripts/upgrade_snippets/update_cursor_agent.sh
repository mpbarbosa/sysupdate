#!/bin/bash
#
# update_cursor_agent.sh - Cursor CLI Agent Update Manager
# SNIPPET_ID: cursor-agent
# SNIPPET_NAME: Cursor CLI Agent
#
# Handles updates for cursor-agent, the Cursor command-line agent.
# Companion to the `cursor` snippet (the Cursor IDE desktop app).
#
# cursor-agent is calendar-versioned (e.g. 2026.05.16-0338208). The public
# installer script (https://cursor.com/install) hardcodes the latest build ID,
# so it doubles as an unauthenticated release feed. Updates run through that
# installer: the built-in `cursor-agent update` requires a valid login and
# fails with "[unauthenticated]" whenever the stored session has expired.
#
# Version: 0.2.0-alpha
# Date: 2026-09-17
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.2.0-alpha (2026-09-17) - Resolve latest version from the install script
#                            - Update via the install script (no auth needed)
#                            - Surface update output to the JSON event stream
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Reports current version from `cursor-agent --version`
#                            - Updates through the built-in `cursor-agent update` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

CURSOR_AGENT_DISPLAY_NAME="Cursor CLI Agent"
CURSOR_AGENT_INSTALL_URL="https://cursor.com/install"
# Build IDs look like 2026.09.15-d2fe57e
CURSOR_AGENT_BUILD_REGEX='[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9a-f]+'

get_cursor_agent_version() {
    cursor-agent --version 2>/dev/null | head -1 | grep -oE "$CURSOR_AGENT_BUILD_REGEX" | head -1
}

# Print the build ID embedded in an installer script read from stdin.
extract_cursor_agent_installer_build() {
    grep -oE "cursor-agent/versions/${CURSOR_AGENT_BUILD_REGEX}" | head -1 | grep -oE "$CURSOR_AGENT_BUILD_REGEX"
}

# Calendar date part of a build ID (2026.09.15-d2fe57e -> 2026.09.15)
cursor_agent_build_date() {
    printf '%s\n' "${1%%-*}"
}

update_cursor_agent() {
    print_operation_header "Checking Cursor CLI Agent updates..."

    if ! check_app_installed "cursor-agent" "$CURSOR_AGENT_DISPLAY_NAME"; then
        print_status "Install Cursor CLI Agent: curl $CURSOR_AGENT_INSTALL_URL -fsS | bash"
        ask_continue
        return 0
    fi

    local current_version
    current_version=$(get_cursor_agent_version)
    current_version="${current_version:-unknown}"

    local installer_script latest_version
    installer_script=$(curl -fsSL --max-time 30 "$CURSOR_AGENT_INSTALL_URL" 2>/dev/null)
    latest_version=$(printf '%s\n' "$installer_script" | extract_cursor_agent_installer_build)

    if [ -z "$latest_version" ]; then
        print_status "Current version: $current_version"
        emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
            "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        print_warning "Could not determine latest $CURSOR_AGENT_DISPLAY_NAME version from $CURSOR_AGENT_INSTALL_URL"
        ask_continue
        return 0
    fi

    print_status "Current version: $current_version"
    print_status "Latest version: $latest_version"

    # 0 = up to date, 1 = ahead of latest, 2 = update available
    local version_status=2
    if [ "$current_version" = "$latest_version" ]; then
        version_status=0
    elif [ "$current_version" != "unknown" ]; then
        # Build IDs order by date; same date with a different hash is still a different build.
        compare_versions "$(cursor_agent_build_date "$current_version")" \
            "$(cursor_agent_build_date "$latest_version")"
        [ $? -eq 1 ] && version_status=1
    fi

    case "$version_status" in
        0)
            print_success "$CURSOR_AGENT_DISPLAY_NAME is up to date"
            emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
                "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version"
            ;;
        1)
            print_status "$CURSOR_AGENT_DISPLAY_NAME version is newer than latest release"
            emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
                "status" "ahead_of_latest" "current_version" "$current_version" "latest_version" "$latest_version"
            ;;
        2)
            print_warning "$CURSOR_AGENT_DISPLAY_NAME update available: $current_version → $latest_version"
            emit_summary_event "version_check" "target" "$CURSOR_AGENT_DISPLAY_NAME" \
                "status" "update_available" "current_version" "$current_version" "latest_version" "$latest_version"
            ;;
    esac

    CURSOR_AGENT_INSTALLER_SCRIPT="$installer_script"
    handle_update_prompt "$CURSOR_AGENT_DISPLAY_NAME" "$version_status" \
        "perform_cursor_agent_update \"$latest_version\""
}

# Drop the installer's progress bar and cursor-control escapes (stdin -> stdout).
clean_cursor_agent_installer_output() {
    tr '\r' '\n' | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -vE '^[[:space:]#=]*([0-9.]+%)?[[:space:]]*$'
}

# Run the downloaded installer and verify the active build afterwards.
perform_cursor_agent_update() {
    local installer_script="$CURSOR_AGENT_INSTALLER_SCRIPT"
    local latest_version="$1"

    local update_output
    local installer_status
    update_output=$(printf '%s\n' "$installer_script" | NO_COLOR=1 bash 2>&1)
    installer_status=$?
    update_output=$(printf '%s\n' "$update_output" | clean_cursor_agent_installer_output)
    if [ "$installer_status" -ne 0 ]; then
        emit_captured_output "$update_output" 20
        print_error "Failed to update $CURSOR_AGENT_DISPLAY_NAME"
        ask_continue
        return 1
    fi
    emit_captured_output "$update_output" 20

    local new_version
    new_version=$(get_cursor_agent_version)
    if [ "$new_version" != "$latest_version" ]; then
        print_error "$CURSOR_AGENT_DISPLAY_NAME still reports ${new_version:-unknown} after update (expected $latest_version)"
        ask_continue
        return 1
    fi

    print_success "$CURSOR_AGENT_DISPLAY_NAME updated to $new_version"
    ask_continue
    return 0
}

update_cursor_agent
