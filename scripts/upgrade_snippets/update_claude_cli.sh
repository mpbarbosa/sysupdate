#!/bin/bash
#
# update_claude_cli.sh - Anthropic Claude CLI Update Manager
# SNIPPET_ID: claude
# SNIPPET_NAME: Anthropic Claude CLI
#
# Handles version checking and updates for Anthropic Claude CLI.
# Reference: https://github.com/anthropics/claude-code
#
# Version: 0.1.0-alpha
# Date: 2026-05-02
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-02) - Initial alpha version
#                            - Uses official anthropics/claude-code tags for version checks
#                            - Updates through the built-in `claude update` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/claude_cli.yaml"

perform_claude_cli_update() {
    local update_cmd
    update_cmd=$(get_config "update.command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local update_output

    if ! update_output=$(eval "$update_cmd" 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
        print_error "Failed to update $APP_DISPLAY_NAME"
        return 1
    fi

    [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"

    # `claude update` can exit 0 without actually advancing the version (e.g. a
    # managed/no-op install), so the exit code alone cannot confirm success.
    # Verify the installed version actually reached the latest release; this
    # prints "Verified version: X", emits the summary event, and reports an
    # honest failure if the binary did not change.
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

update_claude_cli() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_claude_cli_update"; then
        ask_continue
        return 1
    fi
}

update_claude_cli
