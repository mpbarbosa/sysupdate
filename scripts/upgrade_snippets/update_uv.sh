#!/bin/bash
#
# update_uv.sh - uv (Astral) Update Manager
# SNIPPET_ID: uv
# SNIPPET_NAME: uv (Astral Python Manager)
#
# Handles version checking and updates for uv, Astral's Python package and
# project manager. Reference: https://github.com/astral-sh/uv
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Uses astral-sh/uv releases for version checks
#                            - Updates through the built-in `uv self update` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/uv.yaml"

perform_uv_update() {
    local update_cmd
    update_cmd=$(get_config "update.command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local app_name
    app_name=$(get_config "application.name")
    local update_output

    if ! update_output=$(eval "$update_cmd" 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
        print_error "Failed to update $APP_DISPLAY_NAME"
        return 1
    fi

    [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
    print_success "$success_msg"
    show_installation_info "$app_name" "$APP_DISPLAY_NAME"
    return 0
}

update_uv() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_uv_update"; then
        ask_continue
        return 1
    fi
}

update_uv
