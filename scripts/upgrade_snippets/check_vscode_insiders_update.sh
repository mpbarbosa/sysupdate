#!/bin/bash
#
# check_vscode_insiders_update.sh - VSCode Insiders Update Manager
# SNIPPET_ID: vscode-insiders
# SNIPPET_NAME: VS Code Insiders
#
# Handles version checking and updates for Visual Studio Code Insiders.
# Reference: https://code.visualstudio.com/insiders
#
# Version: 1.0.0-alpha
# Date: 2025-11-25
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-25) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 2: Installer Script Pattern (deb_package)
#                            - Simplified main function to use handle_deb_package_update()
#                            - Removed download_and_install_vscode_insiders() function
#                            - Follows check_kitty_update.sh pattern
#                            - Custom version checking in perform_vscode_version_check()
#   0.1.0-alpha (2025-11-25) - Initial alpha version with upgrade script pattern
#                            - Migrated from hardcoded to config-driven approach
#                            - All strings externalized to vscode_insiders.yaml
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/vscode_insiders.yaml"

# Get latest VSCode Insiders version from download redirect
get_vscode_insiders_latest_version() {
    local fetch_url
    fetch_url=$(get_config "version.custom_fetch_url")
    local version_regex
    version_regex=$(get_config "version.version_regex")
    
    # Extract version from redirect URL
    # Format: https://vscode.download.prss.microsoft.com/dbazure/download/insider/HASH/code-insiders_VERSION_amd64.deb
    local latest_version
    latest_version=$(curl -sL "$fetch_url" -I 2>/dev/null | \
                     grep -i 'location:' | \
                     sed -E "s/.*$version_regex.*/\1/" | \
                     tr -d '\r')
    echo "$latest_version"
}

# Get latest VSCode Insiders commit hash from download redirect
get_vscode_insiders_latest_commit() {
    local fetch_url
    fetch_url=$(get_config "version.custom_fetch_url")
    
    # Extract commit hash from the redirect URL
    # Format: https://vscode.download.prss.microsoft.com/dbazure/download/insider/HASH/code-insiders_VERSION_amd64.deb
    local latest_commit
    latest_commit=$(curl -sL "$fetch_url" -I 2>/dev/null | \
                    grep -i 'location:' | \
                    sed -E 's|.*/insider/([a-f0-9]{40})/.*|\1|' | \
                    tr -d '\r')
    echo "$latest_commit"
}

# Custom version check for VSCode Insiders
# VSCode Insiders has a non-standard version format that requires custom handling
perform_vscode_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"
    
    # Check if VSCode Insiders is installed
    local app_name
    app_name=$(get_config "application.name")
    local app_display
    app_display=$(get_config "application.display_name")
    local install_help
    install_help=$(get_config "messages.install_help")
    
    if ! check_app_installed_or_help "$app_name" "$app_display" "$install_help"; then
        emit_summary_event "version_check" "target" "$app_display" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        return 1
    fi
    
    # Get current version and commit hash
    local version_cmd
    version_cmd=$(get_config "version.command")
    local version_output
    version_output=$($version_cmd 2>/dev/null)
    
    local current_version
    current_version=$(echo "$version_output" | sed -n '1p')
    local current_commit
    current_commit=$(echo "$version_output" | sed -n '2p')
    
    if [ -z "$current_version" ] || [ -z "$current_commit" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_version")
        emit_summary_event "version_check" "target" "$app_display" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$error_msg"
        return 1
    fi
    
    # Get latest version and commit hash
    local latest_version
    latest_version=$(get_vscode_insiders_latest_version)
    local latest_commit
    latest_commit=$(get_vscode_insiders_latest_commit)
    
    print_status "Current version: $current_version (commit: ${current_commit:0:7})"
    print_status "Latest version:  $latest_version (commit: ${latest_commit:0:7})"
    
    if [ -z "$latest_version" ] || [ -z "$latest_commit" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_latest_version")
        emit_summary_event "version_check" "target" "$app_display" "status" "unknown" "current_version" "$current_version" "latest_version" "unknown" "current_commit" "${current_commit:0:7}" "latest_commit" "unknown"
        print_error "$error_msg"
        return 1
    fi
    
    # Compare using commit hash (more precise than version string)
    # Display both version and commit for user reference
    VERSION_STATUS=0
    if [ "$current_commit" != "$latest_commit" ]; then
        local update_msg
        update_msg=$(get_config "messages.update_available")
        update_msg="${update_msg/\{current\}/$current_version (${current_commit:0:7})}"
        update_msg="${update_msg/\{latest\}/$latest_version (${latest_commit:0:7})}"
        print_warning "$update_msg"
        emit_summary_event "version_check" "target" "$app_display" "status" "update_available" "current_version" "$current_version" "latest_version" "$latest_version" "current_commit" "${current_commit:0:7}" "latest_commit" "${latest_commit:0:7}"
        VERSION_STATUS=2
    else
        local uptodate_msg
        uptodate_msg=$(get_config "messages.up_to_date")
        print_success "$uptodate_msg"
        emit_summary_event "version_check" "target" "$app_display" "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version" "current_commit" "${current_commit:0:7}" "latest_commit" "${latest_commit:0:7}"
        VERSION_STATUS=0
    fi
    
    # Set global variables for handle_update_prompt
    CURRENT_VERSION="$current_version"
    LATEST_VERSION="$latest_version"
    APP_DISPLAY_NAME="$app_display"
    
    return 0
}

# Update VSCode Insiders
# Uses Method 2: Installer Script Pattern (see upgrade_script_pattern_documentation.md)
# Note: VSCode uses .deb package download instead of shell installer
check_vscode_insiders_update() {
    # Perform custom version check (VSCode has non-standard version format)
    if ! perform_vscode_version_check; then
        ask_continue
        return 0
    fi
    
    # Handle .deb package download and installation (extracted to upgrade_utils.sh)
    handle_deb_package_update
}

check_vscode_insiders_update