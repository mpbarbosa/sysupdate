#!/bin/bash
#
# update_npm.sh - npm Update Manager
# SNIPPET_ID: npm
# SNIPPET_NAME: npm Package Manager
#
# Handles version checking and updates for npm (Node Package Manager).
# Reference: https://docs.npmjs.com/try-the-latest-stable-version-of-npm
#
# Version: 1.0.0-alpha
# Date: 2025-11-26
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-26) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 1: Direct Command Update
#                            - Added complete version header
#                            - Follows update_github_copilot_cli.sh pattern
#
# Dependencies:
#   - Node.js (required by npm)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/npm.yaml"

source "$LIB_DIR/upgrade_utils.sh"

perform_npm_update() {
    local output_lines="$1"
    local success_msg="$2"
    local app_name="$3"
    local display_name="$4"
    local npm_binary
    npm_binary=$(command -v npm 2>/dev/null)

    if [ -z "$npm_binary" ]; then
        print_error "npm binary not found"
        return 1
    fi

    local configured_prefix
    configured_prefix=$(npm config get prefix 2>/dev/null)

    local active_prefix
    active_prefix=$(cd "$(dirname "$npm_binary")/.." >/dev/null 2>&1 && pwd)
    if [ -z "$active_prefix" ] || [ ! -d "$active_prefix" ]; then
        print_error "Failed to determine the active npm installation prefix"
        return 1
    fi

    if [ -n "$configured_prefix" ] && [ "$configured_prefix" != "$active_prefix" ]; then
        print_warning "npm global prefix points to $configured_prefix, but the active npm installation is under $active_prefix"
        print_status "Targeting the active npm installation prefix for this update"
    fi

    local install_output
    local install_exit_code
    if [ -w "$active_prefix" ]; then
        install_output=$(env -u npm_config_prefix -u NPM_CONFIG_PREFIX -u PREFIX \
            "$npm_binary" install -g npm@latest --prefix "$active_prefix" 2>&1)
        install_exit_code=$?
    else
        install_output=$(run_with_sudo env -u npm_config_prefix -u NPM_CONFIG_PREFIX -u PREFIX \
            "$npm_binary" install -g npm@latest --prefix "$active_prefix" 2>&1)
        install_exit_code=$?
    fi

    printf '%s\n' "$install_output" | tail -"$output_lines"

    if [ "$install_exit_code" -ne 0 ]; then
        print_error "npm update failed"
        return 1
    fi

    local installed_version
    installed_version=$(npm --version 2>/dev/null | head -1)
    if [ -z "$installed_version" ]; then
        print_error "npm update completed but the installed version could not be verified"
        return 1
    fi

    if [ -n "$LATEST_VERSION" ]; then
        compare_versions "$installed_version" "$LATEST_VERSION"
        if [ $? -eq 2 ]; then
            print_error "npm update completed but active version is still $installed_version (expected $LATEST_VERSION)"
            return 1
        fi
    fi

    print_success "$success_msg"
    show_installation_info "$app_name" "$display_name"
}

# Update npm
# Uses Method 1: Direct Command Update (see upgrade_script_pattern_documentation.md)
update_npm() {
    # Check Node.js dependency first
    local dep_name
    dep_name=$(get_config "dependencies[0].name")
    local dep_cmd
    dep_cmd=$(get_config "dependencies[0].command")
    local dep_help
    dep_help=$(get_config "dependencies[0].help")
    
    if ! check_app_installed_or_help "$dep_cmd" "$dep_name" "$dep_help"; then
        ask_continue
        return 0
    fi
    
    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Handle update workflow with direct npm command
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local app_name
    app_name=$(get_config "application.name")
    
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_npm_update '$output_lines' '$success_msg' '$app_name' '$APP_DISPLAY_NAME'"; then
        ask_continue
        return 1
    fi
}

update_npm
