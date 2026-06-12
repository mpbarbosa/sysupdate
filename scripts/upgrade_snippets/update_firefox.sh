#!/bin/bash
#
# update_firefox.sh - Firefox Installation/Update Manager
# SNIPPET_ID: firefox
# SNIPPET_NAME: Firefox Browser
#
# Handles version checking, installation, and updates for Firefox.
# Supports both Snap and DEB versions, with preference for Mozilla's APT repository.
#

# Load upgrade utilities library
FIREFOX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$FIREFOX_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$FIREFOX_SCRIPT_DIR/firefox.yaml"

check_firefox_installed() {
    command -v firefox &> /dev/null
}

is_firefox_snap() {
    local snap_check_cmd
    snap_check_cmd=$(get_config "update.snap_check_cmd")
    eval "$snap_check_cmd" &> /dev/null 2>&1
}

is_firefox_deb() {
    if ! dpkg -l | grep -q "^ii.*firefox"; then
        return 1
    fi
    if is_firefox_snap; then
        return 1
    fi
    # Check if it's the Ubuntu transition package (fake DEB)
    local package_version
    package_version=$(dpkg -l | grep "^ii.*firefox" | awk '{print $3}')
    if [[ "$package_version" == *"snap"* ]]; then
        return 1
    fi
    return 0
}

get_firefox_install_method() {
    if is_firefox_snap; then
        echo "snap"
    elif is_firefox_deb; then
        echo "deb"
    else
        echo "unknown"
    fi
}

get_firefox_snap_current_version() {
    snap list firefox 2>/dev/null | awk 'NR==2 {print $2}'
}

get_firefox_snap_latest_version() {
    snap info firefox 2>/dev/null | awk '/latest\/stable:/ {print $2; exit}'
}

get_firefox_deb_current_version() {
    dpkg-query -W -f='${Version}\n' firefox 2>/dev/null | sed 's/^[0-9]\+://' | head -1
}

check_firefox_version() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    APP_DISPLAY_NAME=$(get_config "application.display_name")
    print_operation_header "$checking_msg"

    if ! check_firefox_installed; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_warning "Firefox is not installed."
        return 1
    fi

    local install_method
    install_method=$(get_firefox_install_method)

    case "$install_method" in
        snap)
            print_status "$(get_config "messages.detected_snap")"
            CURRENT_VERSION=$(get_firefox_snap_current_version)
            LATEST_VERSION=$(get_firefox_snap_latest_version)
            ;;
        deb)
            print_status "$(get_config "messages.detected_deb")"
            CURRENT_VERSION=$(get_firefox_deb_current_version)
            LATEST_VERSION=$(get_apt_latest_version "firefox")
            ;;
        *)
            emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
            print_warning "$(get_config "messages.unknown_type")"
            return 1
            ;;
    esac

    if [ -z "$CURRENT_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_version")"
        return 1
    fi

    if [ -z "$LATEST_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_warning "Could not determine latest Firefox version"
        print_status "Current version: $CURRENT_VERSION"
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    return 0
}

setup_mozilla_repo() {
    local setup_msg keyring_msg key_msg repo_msg priority_msg complete_msg
    setup_msg=$(get_config "messages.setup_repo")
    keyring_msg=$(get_config "messages.keyring_dir")
    key_msg=$(get_config "messages.importing_key")
    repo_msg=$(get_config "messages.adding_repo")
    priority_msg=$(get_config "messages.setting_priority")
    complete_msg=$(get_config "messages.repo_complete")
    
    local keyring_dir signing_key_url signing_key_path sources_list sources_entry preferences_file preferences_content
    keyring_dir=$(get_config "repository.keyring_dir")
    signing_key_url=$(get_config "repository.signing_key_url")
    signing_key_path=$(get_config "repository.signing_key_path")
    sources_list=$(get_config "repository.sources_list")
    sources_entry=$(get_config "repository.sources_entry")
    preferences_file=$(get_config "repository.preferences_file")
    preferences_content=$(get_config "repository.preferences_content")
    
    print_status "$setup_msg"
    
    print_status "$keyring_msg"
    sudo install -d -m 0755 "$keyring_dir"
    
    print_status "$key_msg"
    local dep_cmd
    dep_cmd=$(get_config "dependencies[0].command")
    if ! command -v "$dep_cmd" &> /dev/null; then
        print_status "wget not found, installing..."
        sudo apt update && sudo apt install -y wget
    fi
    wget -q "$signing_key_url" -O- | sudo tee "$signing_key_path" > /dev/null
    
    print_status "$repo_msg"
    echo "$sources_entry" | sudo tee -a "$sources_list" > /dev/null
    
    print_status "$priority_msg"
    echo "$preferences_content" | sudo tee "$preferences_file" > /dev/null
    
    print_success "$complete_msg"
}

install_firefox_deb() {
    local installing_msg removing_msg updating_msg complete_msg
    installing_msg=$(get_config "messages.installing_firefox")
    removing_msg=$(get_config "messages.removing_snap")
    updating_msg=$(get_config "messages.updating_packages")
    complete_msg=$(get_config "messages.install_complete")
    
    print_status "$installing_msg"
    
    if is_firefox_snap; then
        print_status "$removing_msg"
        local snap_remove_cmd
        snap_remove_cmd=$(get_config "update.snap_remove_cmd")
        eval "$snap_remove_cmd"
    fi
    
    setup_mozilla_repo
    
    print_status "$updating_msg"
    sudo apt update
    local remove_cmd install_cmd
    remove_cmd=$(get_config "update.remove_command")
    install_cmd=$(get_config "update.install_command")
    eval "$remove_cmd 2>/dev/null || true"
    eval "$install_cmd"
    
    print_success "$complete_msg"
}

update_firefox() {
    local updating_msg complete_msg update_cmd
    updating_msg=$(get_config "messages.updating_firefox")
    complete_msg=$(get_config "messages.update_complete")
    update_cmd=$(get_config "update.update_command")
    
    print_status "$updating_msg"
    eval "$update_cmd"
    print_success "$complete_msg"
}

install_or_update_firefox() {
    local app_name
    app_name=$(get_config "application.display_name")

    if [ "$CHECK_ONLY_MODE" = true ]; then
        check_firefox_version
        return 0
    fi
    
    print_section_header "$app_name Installation/Update Script"
    
    if check_firefox_installed; then
        print_status "Firefox is installed."
        
        if is_firefox_snap; then
            local snap_msg
            snap_msg=$(get_config "messages.detected_snap")
            print_status "$snap_msg"
            
            local prompt_msg
            prompt_msg=$(get_config "prompts.replace_snap.message")
            if prompt_yes_no "$prompt_msg"; then
                install_firefox_deb
            else
                print_status "Updating Firefox Snap..."
                local snap_update_cmd
                snap_update_cmd=$(get_config "update.snap_update_cmd")
                eval "$snap_update_cmd"
                print_success "Firefox Snap update complete!"
            fi
        elif is_firefox_deb; then
            local deb_msg
            deb_msg=$(get_config "messages.detected_deb")
            print_status "$deb_msg"
            
            local check_mozilla_cmd
            check_mozilla_cmd=$(get_config "update.check_mozilla_repo_cmd")
            if eval "$check_mozilla_cmd"; then
                local mozilla_msg
                mozilla_msg=$(get_config "messages.mozilla_configured")
                print_status "$mozilla_msg"
                update_firefox
            else
                local not_configured_msg prompt_msg
                not_configured_msg=$(get_config "messages.mozilla_not_configured")
                prompt_msg=$(get_config "prompts.setup_mozilla_repo.message")
                print_status "$not_configured_msg"
                if prompt_yes_no "$prompt_msg"; then
                    setup_mozilla_repo
                    update_firefox
                else
                    print_status "Updating with current repository..."
                    local update_cmd
                    update_cmd=$(get_config "update.update_command")
                    eval "$update_cmd"
                fi
            fi
        else
            local unknown_msg
            unknown_msg=$(get_config "messages.unknown_type")
            print_status "$unknown_msg"
            update_firefox
        fi
    else
        local not_installed_msg installing_msg
        not_installed_msg=$(get_config "messages.not_installed")
        installing_msg=$(get_config "messages.installing_firefox")
        print_status "$not_installed_msg"
        print_status "$installing_msg"
        install_firefox_deb
    fi
    
    echo ""
    print_success "Script execution complete!"
    firefox --version 2>/dev/null
}

install_or_update_firefox
