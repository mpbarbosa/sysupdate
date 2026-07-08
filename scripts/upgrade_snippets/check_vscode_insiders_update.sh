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

# Resolve the VSCode Insiders download redirect once and cache the .deb URL.
# Both the version and commit hash are parsed from this single result, so we
# never issue two separate curl requests (Microsoft's CDN load-balances them
# and can return different redirect chains, leaving the commit hash empty).
VSCODE_INSIDERS_DEB_URL=""
resolve_vscode_insiders_deb_url() {
    # Return the cached URL if we already resolved it this run.
    if [ -n "$VSCODE_INSIDERS_DEB_URL" ]; then
        echo "$VSCODE_INSIDERS_DEB_URL"
        return 0
    fi

    local fetch_url
    fetch_url=$(get_config "version.custom_fetch_url")

    # Follow the redirect chain and keep only the location line that points at
    # the code-insiders .deb (there may be several redirect hops).
    # Format: https://vscode.download.prss.microsoft.com/dbazure/download/insider/HASH/code-insiders_VERSION_amd64.deb
    VSCODE_INSIDERS_DEB_URL=$(curl -sL "$fetch_url" -I 2>/dev/null | \
                              tr -d '\r' | \
                              grep -i '^location:' | \
                              grep -o 'https[^ ]*code-insiders_[^ ]*\.deb' | \
                              tail -n1)
    echo "$VSCODE_INSIDERS_DEB_URL"
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
    
    # Resolve the download redirect once, then parse both version and commit
    # from the same URL so the two never disagree.
    local deb_url
    deb_url=$(resolve_vscode_insiders_deb_url)
    local version_regex
    version_regex=$(get_config "version.version_regex")
    local latest_version
    latest_version=$(echo "$deb_url" | sed -E "s/.*$version_regex.*/\1/")
    local latest_commit
    latest_commit=$(echo "$deb_url" | sed -E 's|.*/insider/([a-f0-9]{40})/.*|\1|')
    
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