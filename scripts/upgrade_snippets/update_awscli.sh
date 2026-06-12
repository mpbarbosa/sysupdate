#!/bin/bash
#
# update_awscli.sh - AWS CLI Update Manager
# SNIPPET_ID: awscli
# SNIPPET_NAME: AWS CLI
#
# Handles version checking and updates for AWS CLI v2.
# Reference: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
#
# Dependencies:
#   - curl
#   - unzip
#   - sudo (for installation)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/awscli.yaml"

perform_awscli_install_or_update() {
    local download_msg
    download_msg=$(get_config "messages.downloading_installer")
    local cleanup_msg
    cleanup_msg=$(get_config "messages.cleanup_message")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local previous_version="${CURRENT_VERSION:-}"
    
    print_status "$download_msg"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1
    
    if ! curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; then
        print_error "Failed to download AWS CLI installer"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! unzip -q awscliv2.zip; then
        print_error "Failed to unzip AWS CLI installer"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi

    local install_output
    local install_status
    if [ "$VERBOSE_MODE" = true ]; then
        install_output=$(run_with_sudo ./aws/install --update 2>&1)
        install_status=$?
        printf '%s\n' "$install_output"
    else
        install_output=$(run_with_sudo ./aws/install --update 2>&1)
        install_status=$?
        printf '%s\n' "$install_output" | tail -20
    fi
    
    cd - > /dev/null
    
    print_status "$cleanup_msg"
    rm -rf "$temp_dir"
    
    if [ $install_status -ne 0 ]; then
        print_error "AWS CLI installation/update failed"
        return 1
    fi

    local installed_version
    local version_cmd
    local version_regex
    version_cmd=$(get_config "version.command")
    version_regex=$(get_config "version.regex")
    installed_version=$(eval "$version_cmd" 2>/dev/null | head -1 | sed -nE "s/$version_regex/\1/p")

    if [ -z "$installed_version" ]; then
        print_error "AWS CLI update completed but the installed version could not be verified"
        return 1
    fi

    if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$installed_version" ]; then
        print_error "AWS CLI update completed but active version is still $installed_version (expected $LATEST_VERSION)"
        if [ -n "$previous_version" ] && [ "$installed_version" = "$previous_version" ]; then
            print_error "The active aws binary did not change after running the installer"
        fi
        return 1
    fi

    print_success "$success_msg"
    print_status "Installed version: $installed_version"
    show_installation_info "aws" "$APP_DISPLAY_NAME"
    return 0
}

update_awscli() {
    local dep_name
    local dep_cmd
    local dep_help
    
    dep_name=$(get_config "dependencies[0].name")
    dep_cmd=$(get_config "dependencies[0].command")
    dep_help=$(get_config "dependencies[0].help")
    
    if ! check_app_installed_or_help "$dep_name" "$dep_cmd" "$dep_help"; then
        return 0
    fi
    
    dep_name=$(get_config "dependencies[1].name")
    dep_cmd=$(get_config "dependencies[1].command")
    dep_help=$(get_config "dependencies[1].help")
    
    if ! check_app_installed_or_help "$dep_name" "$dep_cmd" "$dep_help"; then
        return 0
    fi
    
    if ! config_driven_version_check; then
        local install_help
        install_help=$(get_config "messages.install_help")
        print_info "$install_help"
        
        if prompt_yes_no "Would you like to install AWS CLI now?"; then
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "2" \
                "perform_awscli_install_or_update"; then
                ask_continue
                return 1
            fi
        fi
        return 0
    fi
    
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_awscli_install_or_update"; then
        ask_continue
        return 1
    fi
}

update_awscli
