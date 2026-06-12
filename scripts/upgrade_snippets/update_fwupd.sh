#!/bin/bash
#
# update_fwupd.sh - Firmware Update Manager
# SNIPPET_ID: fwupd
# SNIPPET_NAME: Firmware Update (fwupd)
#
# Handles version checking and updates for fwupd and system firmware.
# This script manages both the fwupd package itself and firmware updates
# for devices on the system.
#
# Dependencies:
#   - fwupd (Linux Firmware Update Daemon)
#   - apt (for package updates)
#
# Reference: https://fwupd.org/

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/fwupd.yaml"

# Show what's taking up space in /boot/efi
show_efi_space_usage() {
    print_status "Analyzing /boot/efi space usage..."
    echo ""
    
    # Show overall disk usage
    print_status "Disk usage summary:"
    df -h /boot/efi
    echo ""
    
    # List contents with sizes
    print_status "Directory contents:"
    ls -lh /boot/efi 2>/dev/null || sudo ls -lh /boot/efi
    echo ""
    
    # Show directory sizes sorted by size
    print_status "Largest directories (sorted by size):"
    sudo du -h --max-depth=2 /boot/efi 2>/dev/null | sort -hr | head -10
    echo ""
    
    # Show EFI subdirectories if they exist
    if [ -d "/boot/efi/EFI" ]; then
        print_status "EFI subdirectories:"
        sudo ls -lh /boot/efi/EFI/ 2>/dev/null
        echo ""
    fi
}

# Clean up old EFI files to free space
cleanup_efi_space() {
    print_status "Attempting to free up space in /boot/efi..."
    
    # Show what's using space before cleanup
    show_efi_space_usage
    
    local cleaned=0
    
    # First try to remove old kernels using apt autoremove
    print_status "Removing old kernels..."
    if sudo apt-get autoremove --purge -y 2>/dev/null; then
        cleaned=1
        print_success "Old kernels removed"
    fi
    
    # Clean fwupd cache if the directory exists
    if [ -d "/boot/efi/EFI/fwupd" ]; then
        print_status "Removing old fwupd files..."
        if sudo rm -rf /boot/efi/EFI/fwupd/*.* 2>/dev/null; then
            cleaned=1
        fi
    fi
    
    # Remove old update capsules
    if [ -d "/boot/efi/EFI/UpdateCapsule" ]; then
        print_status "Removing old update capsules..."
        if sudo rm -rf /boot/efi/EFI/UpdateCapsule/* 2>/dev/null; then
            cleaned=1
        fi
    fi
    
    # Clean apt cache
    print_status "Cleaning apt cache..."
    if sudo apt-get clean 2>/dev/null; then
        cleaned=1
    fi
    
    return $cleaned
}

# Check if /boot/efi has sufficient space for firmware updates
# Returns: 0 if sufficient space or not mounted, 1 if insufficient space
check_efi_space() {
    # Check if /boot/efi is mounted
    if ! mountpoint -q /boot/efi 2>/dev/null; then
        return 0
    fi
    
    # Get available space in MB
    local available_mb
    available_mb=$(df -BM /boot/efi | awk 'NR==2 {print $4}' | sed 's/M//')
    
    # Require at least 100MB free space for firmware updates
    local required_mb=100
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        print_error "/boot/efi does not have sufficient space"
        print_status "Available: ${available_mb}MB, Required: ${required_mb}MB"

        if [ "$CHECK_ONLY_MODE" = true ]; then
            print_status "Check-only mode - skipping automatic EFI cleanup"
            return 1
        fi
        
        # Try to clean up old firmware files
        if cleanup_efi_space; then
            print_success "Cleanup completed"
            
            # Recheck available space
            available_mb=$(df -BM /boot/efi | awk 'NR==2 {print $4}' | sed 's/M//')
            print_status "Available space after cleanup: ${available_mb}MB"
            
            if [ "$available_mb" -lt "$required_mb" ]; then
                print_error "Still insufficient space after cleanup"
                print_status "Required: ${required_mb}MB"
                print_status "Manual cleanup needed: Check /boot/efi for old files"
                return 1
            fi
            
            print_success "Sufficient space now available"
            return 0
        else
            print_warning "Unable to free sufficient space automatically"
            print_status "Manual cleanup needed: Check /boot/efi for old files"
            return 1
        fi
    fi
    
    return 0
}

# Check and update firmware for devices
check_firmware_updates() {
    local refresh_msg
    refresh_msg=$(get_config "messages.refresh_metadata")
    local checking_msg
    checking_msg=$(get_config "messages.checking_firmware")
    local no_updates_msg
    no_updates_msg=$(get_config "messages.no_firmware_updates")
    local updates_available_msg
    updates_available_msg=$(get_config "messages.firmware_updates_available")
    
    print_status "$refresh_msg"
    
    # Refresh metadata
    local refresh_cmd
    refresh_cmd=$(get_config "firmware.refresh_command")
    if ! eval "$refresh_cmd" >/dev/null 2>&1; then
        print_warning "Failed to refresh firmware metadata"
    fi
    
    print_status "$checking_msg"
    
    # Check for firmware updates
    local check_cmd
    check_cmd=$(get_config "firmware.check_command")
    local firmware_output
    firmware_output=$(eval "$check_cmd" 2>&1)
    local check_status=$?
    
    if [ $check_status -eq 0 ]; then
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "update_available"
        print_success "$updates_available_msg"
        echo "$firmware_output"
        
        # Check EFI space before prompting
        if ! check_efi_space; then
            emit_summary_event "firmware_readiness" "target" "fwupd" "status" "insufficient_efi_space"
            print_warning "Cannot proceed with firmware update due to insufficient space"
            return 1
        fi
        
        # Prompt to update firmware
        if prompt_yes_no "Update firmware now?"; then
            update_firmware
        else
            print_status "Skipping firmware update"
        fi
    elif [ $check_status -eq 2 ]; then
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "up_to_date"
        print_success "$no_updates_msg"
    else
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "unknown"
        print_info "$no_updates_msg"
    fi
}

# Perform firmware update
update_firmware() {
    local updating_msg
    updating_msg=$(get_config "messages.updating_firmware")
    local success_msg
    success_msg=$(get_config "messages.firmware_update_success")
    local failed_msg
    failed_msg=$(get_config "messages.firmware_update_failed")
    
    print_status "$updating_msg"
    
    local update_cmd
    update_cmd=$(get_config "firmware.update_command")
    
    if eval "$update_cmd"; then
        print_success "$success_msg"
        print_warning "Note: Some firmware updates may require a system reboot to take effect"
    else
        print_error "$failed_msg"
        return 1
    fi
}

# Check if fwupd is installed and offer to install if not
check_and_install_fwupd() {
    local app_cmd
    app_cmd=$(get_config "application.command")
    local app_name
    app_name=$(get_config "application.name")
    
    if ! command -v "$app_cmd" >/dev/null 2>&1; then
        emit_summary_event "version_check" "target" "$app_name" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$app_cmd not installed"
        
        if prompt_yes_no "Would you like to install $app_name now?"; then
            print_status "Installing $app_name..."
            if sudo apt-get update && sudo apt-get install -y "$app_name"; then
                print_success "$app_name installed successfully"
                return 0
            else
                print_error "Failed to install $app_name"
                ask_continue
                return 1
            fi
        else
            print_status "Skipping $app_name installation"
            local install_help
            install_help=$(get_config "messages.install_help")
            if [ -n "$install_help" ]; then
                print_info "$install_help"
            fi
            ask_continue
            return 1
        fi
    fi
    return 0
}

# Main update function
update_fwupd() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"
    
    # Check if fwupd is installed first, prompt to install if not
    if ! check_and_install_fwupd; then
        return 1
    fi
    
    # Now do version check (this will skip the install check since fwupd is installed)
    # We need to do the version check manually to avoid duplicate header
    local app_name
    app_name=$(get_config "application.name")
    local app_cmd
    app_cmd=$(get_config "application.command")
    local display_name
    display_name=$(get_config "application.display_name")
    APP_DISPLAY_NAME="${display_name:-$app_name}"
    
    # Get current version
    local version_cmd
    version_cmd=$(get_config "version.command")
    local version_regex
    version_regex=$(get_config "version.regex")
    CURRENT_VERSION=$($version_cmd 2>/dev/null | grep 'org.freedesktop.fwupd' | head -1 | sed -E "s/$version_regex/\1/")
    
    if [ -z "$CURRENT_VERSION" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_version")
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$error_msg"
        ask_continue
        return 1
    fi
    
    # Get latest version from apt
    local package_name
    package_name=$(get_config "version.package_name")
    LATEST_VERSION=$(get_apt_latest_version "$package_name")
    
    if [ -z "$LATEST_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_error "Failed to get latest version from apt"
        ask_continue
        return 1
    fi
    
    # Set display name
    # Compare versions and emit structured summary for the fwupd package itself
    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?
    
    # Handle fwupd package update workflow
    local update_cmd
    update_cmd=$(get_config "update.update_command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local app_name
    app_name=$(get_config "application.name")
    
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "$update_cmd 2>&1 | tail -$output_lines && \
         print_success '$success_msg' && \
         show_installation_info '$app_name' '$APP_DISPLAY_NAME'"; then
        ask_continue
        return 1
    fi
    
    # After updating fwupd package, check for firmware updates
    echo ""
    print_section_header "Firmware Updates"
    check_firmware_updates
    
    ask_continue
}

update_fwupd
