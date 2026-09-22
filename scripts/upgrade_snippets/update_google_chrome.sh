#!/bin/bash
#
# update_google_chrome.sh - Google Chrome Update Manager
# SNIPPET_ID: chrome
# SNIPPET_NAME: Google Chrome
#
# Handles version checking, installation, and updates for Google Chrome.
# Reference: https://support.google.com/chrome/a/answer/9025903?hl=en
#
# Version: 0.1.0-alpha
# Date: 2025-11-29
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2025-11-29) - Initial alpha version
#                            - Supports apt-based installation and updates
#                            - Auto-configures Chrome repository if needed
#                            - Follows upgrade script pattern v1.1.0
#
# Dependencies:
#   - wget (for downloading signing key)
#   - apt/dpkg (Debian/Ubuntu package management)
#

# Load upgrade utilities library
CHROME_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$CHROME_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$CHROME_SCRIPT_DIR/google_chrome.yaml"

CHROME_KEYRING_FILE="/usr/share/keyrings/google-chrome.gpg"
CHROME_REPO_URL="dl.google.com/linux/chrome"

# True when any enabled apt source already serves Chrome, in whichever shape.
# Chrome's own postinst maintains a deb822 `google-chrome.sources`, and
# Ubuntu's deb822 migration rewrites an old `google-chrome.list` into one
# (parking the original as `google-chrome.list.disabled`). Testing only for
# the `.list` this snippet writes reads a configured machine as unconfigured.
chrome_repository_is_configured() {
    apt_repository_is_configured "$CHROME_REPO_URL"
}

# Setup Chrome repository if not already configured
setup_chrome_repository() {
    local keyring_file="$CHROME_KEYRING_FILE"
    
    # Check if repository is already configured
    if chrome_repository_is_configured && [[ -f "$keyring_file" ]]; then
        local already_msg
        already_msg=$(get_config "messages.already_installed")
        print_status "$already_msg"
        return 0
    fi
    
    print_section_header "Setting up Google Chrome repository"
    
    # Add signing key, but only when it is actually missing. Re-running the
    # dearmor over an existing keyring makes gpg ask "File exists. Overwrite?
    # (y/N)" on a terminal nobody is reading when sysupdate was spawned
    # headlessly by the web backend, and the run blocks there indefinitely.
    if [[ -f "$keyring_file" ]]; then
        print_status "Google signing key already present at $keyring_file - keeping it"
    else
        local key_desc
        key_desc=$(get_config "update.pre_install_steps[0].description")
        local key_cmd
        key_cmd=$(get_config "update.pre_install_steps[0].command")
        
        print_status "$key_desc..."
        if ! eval "$key_cmd"; then
            print_error "Failed to add Google signing key"
            return 1
        fi
    fi
    
    # Add the repository only when nothing already serves it. Writing our
    # `.list` next to a live `google-chrome.sources` leaves the machine
    # fetching Chrome twice on every apt update, and resurrects the legacy
    # entry the deb822 migration deliberately disabled.
    if chrome_repository_is_configured; then
        print_status "Chrome repository already served by an existing apt source - not adding a duplicate"
    else
        local repo_desc
        repo_desc=$(get_config "update.pre_install_steps[1].description")
        local repo_cmd
        repo_cmd=$(get_config "update.pre_install_steps[1].command")
        
        print_status "$repo_desc..."
        if ! eval "$repo_cmd"; then
            print_error "Failed to configure Chrome repository"
            return 1
        fi
    fi
    
    # Update package cache
    local update_desc
    update_desc=$(get_config "update.pre_install_steps[2].description")
    local update_cmd
    update_cmd=$(get_config "update.pre_install_steps[2].command")
    
    print_status "$update_desc..."
    if ! eval "$update_cmd" > /dev/null 2>&1; then
        print_error "Failed to update package cache"
        return 1
    fi
    
    local success_msg
    success_msg=$(get_config "messages.repo_setup_success")
    print_success "$success_msg"
    return 0
}

# Install Chrome from scratch
install_chrome() {
    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "$installing_msg"
    
    local install_cmd
    install_cmd=$(get_config "update.install_command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    
    if eval "$install_cmd 2>&1 | tail -$output_lines"; then
        print_success "$success_msg"
        return 0
    else
        print_error "Installation failed"
        return 1
    fi
}

# Perform Chrome update
perform_chrome_update() {
    local update_cmd
    update_cmd=$(get_config "update.update_command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local app_name
    app_name=$(get_config "application.name")
    
    if eval "$update_cmd 2>&1 | tail -$output_lines"; then
        print_success "$success_msg"
        show_installation_info "$app_name" "$APP_DISPLAY_NAME"
        return 0
    else
        print_error "Update failed"
        return 1
    fi
}

# Main update function
update_google_chrome() {
    # Check wget dependency
    local dep_name
    dep_name=$(get_config "dependencies[0].name")
    local dep_cmd
    dep_cmd=$(get_config "dependencies[0].command")
    local dep_help
    dep_help=$(get_config "dependencies[0].help")
    
    if ! check_app_installed_or_help "$dep_cmd" "$dep_name" "$dep_help"; then
        return 0
    fi
    
    # Check if Chrome is installed
    local app_cmd
    app_cmd=$(get_config "application.command")
    
    if ! command -v "$app_cmd" &> /dev/null; then
        # Chrome not installed - offer installation
        local app_display
        app_display=$(get_config "application.display_name")
        local install_help
        install_help=$(get_config "messages.install_help")
        
        print_section_header "Google Chrome Installation"
        print_warning "$app_display is not installed."
        echo ""
        
        if ! prompt_yes_no "Would you like to install Google Chrome now?"; then
            print_status "Installation cancelled"
            ask_continue
            return 0
        fi
        
        # Setup repository
        if ! setup_chrome_repository; then
            ask_continue
            return 1
        fi
        
        # Install Chrome
        if ! install_chrome; then
            echo ""
            echo "$install_help"
            ask_continue
            return 1
        fi
        
        ask_continue
        return 0
    fi
    
    # Chrome is installed - check for updates
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Check if repository is configured (might be manual install)
    if ! chrome_repository_is_configured; then
        print_warning "Chrome repository not configured. Setting up for future updates..."
        if ! setup_chrome_repository; then
            ask_continue
            return 1
        fi
    fi
    
    # Handle update workflow
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_chrome_update"; then
        ask_continue
        return 1
    fi
}

update_google_chrome
