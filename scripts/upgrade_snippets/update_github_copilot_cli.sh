#!/bin/bash
#
# update_github_copilot_cli.sh - GitHub Copilot CLI Update Manager
# SNIPPET_ID: copilot
# SNIPPET_NAME: GitHub Copilot CLI
#
# Handles version checking and updates for GitHub Copilot CLI.
# Reference: https://github.com/github/copilot-cli
#
# Version: 1.0.0-alpha
# Date: 2025-11-25
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-25) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 1: Direct Command Update
#                            - Added complete version header
#                            - Follows check_kitty_update.sh pattern
#   0.x.x (2025-11-24)     - Previous iterations with config extraction
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
CONFIG_FILE="$SCRIPT_DIR/github_copilot_cli.yaml"

# Update GitHub Copilot CLI
# Uses Method 1: Direct Command Update (see upgrade_script_pattern_documentation.md)
update_github_copilot_cli() {
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
    
    # Handle update workflow with direct npm command
    local update_cmd
    update_cmd=$(get_config "update.command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local app_name
    app_name=$(get_config "application.name")

    # Repair the PATH npm first if it is corrupted (mismatched dependency
    # tree), else the install below crashes loading cacache.
    ensure_npm_healthy "npm" || true

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "$update_cmd 2>&1 | tail -$output_lines && \
         print_success '$success_msg' && \
         show_installation_info '$app_name' '$APP_DISPLAY_NAME'"; then
        ask_continue
        return 1
    fi

    # Also update system-wide installation if present (e.g. /usr/local/bin/copilot)
    local system_npm="/usr/local/bin/npm"
    local system_copilot="/usr/local/bin/copilot"
    if [ -f "$system_copilot" ] && [ -f "$system_npm" ]; then
        if ensure_npm_healthy "$system_npm" --sudo; then
            print_status "Updating system-wide GitHub Copilot CLI installation ($system_copilot)..."
            run_with_sudo "$system_npm" install -g --force @github/copilot@latest 2>&1 | tail -"$output_lines"
            print_success "System-wide $APP_DISPLAY_NAME updated"
        else
            print_warning "System npm unhealthy; skipped system-wide $APP_DISPLAY_NAME update"
        fi
    fi
}

update_github_copilot_cli