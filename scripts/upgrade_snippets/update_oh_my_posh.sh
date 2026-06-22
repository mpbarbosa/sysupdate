#!/bin/bash
#
# update_oh_my_posh.sh - Oh My Posh Update Manager
# SNIPPET_ID: oh-my-posh
# SNIPPET_NAME: Oh My Posh
#
# Handles version checking and updates for Oh My Posh, a prompt theme engine.
# Reference: https://github.com/JanDeDobbeleer/oh-my-posh
#
# Note: distinct from the `oh-my-bash` and `oh-my-zsh` snippets — Oh My Posh is
# a standalone cross-shell prompt engine, not a shell framework.
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Uses JanDeDobbeleer/oh-my-posh releases for version checks
#                            - Updates through the built-in `oh-my-posh upgrade` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/oh_my_posh.yaml"

perform_oh_my_posh_update() {
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

update_oh_my_posh() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_oh_my_posh_update"; then
        ask_continue
        return 1
    fi
}

update_oh_my_posh
