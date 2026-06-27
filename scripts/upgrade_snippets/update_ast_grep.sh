#!/bin/bash
#
# update_ast_grep.sh - ast-grep Update Manager
# SNIPPET_ID: ast-grep
# SNIPPET_NAME: ast-grep (structural code search)
#
# Handles version checking and updates for ast-grep installed as a global
# npm package (@ast-grep/cli). Mirrors the GitHub Copilot CLI snippet: it
# updates the npm global install and, when a system-wide /usr/local install
# is present, refreshes it via sudo.
#
# Reference: https://github.com/ast-grep/ast-grep
#
# Version: 0.1.0-alpha
# Date: 2026-06-24
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-24) - Initial alpha version
#                            - npm-registry version check + npm global update
#                            - System-wide /usr/local sudo update when present
#
# Dependencies:
#   - npm (Node Package Manager)
#   - Node.js (required by npm)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/ast_grep.yaml"

# Install the latest @ast-grep/cli using the npm that owns the active binary.
# A /usr/local install is updated with the system npm under sudo; any other
# (e.g. nvm/user-prefix) install is updated with the npm on PATH, no sudo.
perform_ast_grep_update() {
    local npm_package
    npm_package=$(get_config "application.npm_package")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    output_lines="${output_lines:-10}"

    local resolved
    resolved=$(readlink -f "$(command -v ast-grep)" 2>/dev/null)

    local update_output
    local update_exit_code
    if [[ "$resolved" == /usr/local/* ]] && [ -x "/usr/local/bin/npm" ]; then
        # Repair the system npm first if it is corrupted, else the install
        # below would crash with "Class extends value ... not a constructor".
        if ! ensure_npm_healthy "/usr/local/bin/npm" --sudo; then
            print_error "System npm is unhealthy; cannot update ast-grep"
            return 1
        fi
        print_status "Updating system-wide ast-grep via /usr/local/bin/npm..."
        update_output=$(run_with_sudo /usr/local/bin/npm install -g "${npm_package}@latest" 2>&1)
        update_exit_code=$?
    else
        if ! ensure_npm_healthy "npm"; then
            print_error "npm is unhealthy; cannot update ast-grep"
            return 1
        fi
        update_output=$(npm install -g "${npm_package}@latest" 2>&1)
        update_exit_code=$?
    fi

    emit_captured_output "$update_output" "$output_lines"
    if [ $update_exit_code -ne 0 ]; then
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

update_ast_grep() {
    # Check npm dependency first
    local dep_name
    dep_name=$(get_config "dependencies[0].name")
    local dep_cmd
    dep_cmd=$(get_config "dependencies[0].command")
    local dep_help
    dep_help=$(get_config "dependencies[0].help")

    if ! check_app_installed_or_help "$dep_name" "$dep_cmd" "$dep_help"; then
        ask_continue
        return 0
    fi

    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    # handle_update_prompt guards check-only mode and the confirm prompt,
    # so the (sudo) install only runs when an update is confirmed.
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_ast_grep_update"; then
        ask_continue
        return 1
    fi

    return 0
}

update_ast_grep
