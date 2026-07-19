#!/bin/bash
#
# update_python3.sh - Python 3 (system interpreter) Update Manager
# SNIPPET_ID: python3
# SNIPPET_NAME: Python 3 (system, apt)
#
# Updates the system CPython interpreter through apt, the channel it is
# installed from on Debian/Ubuntu. See python3.yaml for the version-comparison
# rationale (apt package version on both sides, not `python3 --version`).
# Reference: https://www.python.org/
#
# Version: 0.1.0-alpha
# Date: 2026-07-07
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-07-07) - Initial alpha version, apt-based

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/python3.yaml"

perform_python3_update() {
    local update_cmd
    update_cmd=$(get_config "update.update_command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local installing_msg
    installing_msg=$(get_config "messages.installing")

    print_status "$installing_msg"

    local update_output
    if ! update_output=$(eval "$update_cmd" 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-15}"
        print_error "Failed to update $APP_DISPLAY_NAME"
        return 1
    fi

    [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-15}"

    # apt can exit 0 without advancing the version (already latest, or held).
    # Verify the installed package actually reached the apt candidate; prints
    # "Verified version: X", emits the summary event, and reports an honest
    # failure if the package did not change.
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

update_python3() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_python3_update"; then
        ask_continue
        return 1
    fi
}

update_python3
