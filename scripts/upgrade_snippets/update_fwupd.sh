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

# fwupdmgr exits with EXIT_NOTHING_TO_DO when there was simply nothing to do
# (metadata already current, no updatable devices). That is not a failure.
FWUPD_EXIT_NOTHING_TO_DO=2

# Fallback for firmware.required_esp_mb when the config omits it
FWUPD_DEFAULT_REQUIRED_ESP_MB=32

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
    if efi_dir_exists "/boot/efi/EFI"; then
        print_status "EFI subdirectories:"
        sudo ls -lh /boot/efi/EFI/ 2>/dev/null
        echo ""
    fi
}

# Test for a directory below /boot/efi
# The ESP is normally mounted dmask=0077, so an unprivileged `[ -d ]` on
# anything below the mount point returns false even when the directory exists.
# Probe through sudo, but only when sudo can run without blocking on a password
# prompt that nobody is there to answer.
efi_dir_exists() {
    sudo_can_run && sudo test -d "$1"
}

# Report a size (in MB) for the /boot/efi filesystem
# Usage: get_efi_space_mb avail|size
# Echoes an integer, or nothing when df output cannot be parsed
get_efi_space_mb() {
    local field="$1"
    local column
    case "$field" in
        avail) column=4 ;;
        size)  column=2 ;;
        *) echo ""; return 1 ;;
    esac

    local value
    value=$(df -P -BM /boot/efi 2>/dev/null | awk -v col="$column" 'NR==2 {print $col}' | tr -d 'M')

    # Guard against unexpected df output (missing mount, wrapped long device names)
    case "$value" in
        ''|*[!0-9]*) echo ""; return 1 ;;
    esac

    echo "$value"
}

# Clean up old EFI files to free space
# Returns: 0 if free space actually increased, 1 otherwise
cleanup_efi_space() {
    print_status "Attempting to free up space in /boot/efi..."

    # Show what's using space before cleanup
    show_efi_space_usage

    local before_mb
    before_mb=$(get_efi_space_mb avail)

    # Old kernels are the usual occupant of a full ESP, but purging them touches
    # packages well outside fwupd's remit, so it stays opt-in.
    if prompt_yes_no "Remove unused packages and old kernels (apt-get autoremove --purge)?"; then
        print_status "Removing old kernels..."
        if sudo apt-get autoremove --purge -y; then
            print_success "Old kernels removed"
        else
            print_warning "apt-get autoremove failed"
        fi
    fi

    # Stale capsule payloads staged by earlier fwupd runs. Only the payload
    # directory is touched: the fwupd EFI binaries that sit beside it are what
    # applies a capsule update and must stay in place.
    if efi_dir_exists "/boot/efi/EFI/fwupd/fw"; then
        print_status "Removing stale fwupd capsule payloads..."
        sudo rm -f /boot/efi/EFI/fwupd/fw/*.cap 2>/dev/null
    fi

    # Pending capsules are firmware updates queued for the next boot; removing
    # one cancels that update, so ask before discarding them.
    if efi_dir_exists "/boot/efi/EFI/UpdateCapsule"; then
        local queued_capsules
        queued_capsules=$(sudo ls -A /boot/efi/EFI/UpdateCapsule 2>/dev/null)
        if [ -n "$queued_capsules" ]; then
            print_warning "/boot/efi/EFI/UpdateCapsule holds firmware updates queued for the next boot"
            if prompt_yes_no "Discard the queued capsules?"; then
                sudo rm -rf /boot/efi/EFI/UpdateCapsule/* 2>/dev/null
            fi
        fi
    fi

    local after_mb
    after_mb=$(get_efi_space_mb avail)

    # Measure the result instead of trusting exit codes: rm and apt-get both
    # report success when there was nothing to remove.
    if [ -z "$before_mb" ] || [ -z "$after_mb" ]; then
        return 1
    fi

    [ "$after_mb" -gt "$before_mb" ]
}

# Check if /boot/efi has room to stage a firmware capsule
# Returns: 0 if there is enough space (or no ESP to check), 1 if not
check_efi_space() {
    # Check if /boot/efi is mounted
    if ! mountpoint -q /boot/efi 2>/dev/null; then
        return 0
    fi

    local available_mb
    available_mb=$(get_efi_space_mb avail)
    local total_mb
    total_mb=$(get_efi_space_mb size)

    if [ -z "$available_mb" ]; then
        print_warning "Could not read free space on /boot/efi - leaving the check to fwupd"
        return 0
    fi

    local required_mb
    required_mb=$(get_config "firmware.required_esp_mb")
    case "$required_mb" in
        ''|*[!0-9]*) required_mb=$FWUPD_DEFAULT_REQUIRED_ESP_MB ;;
    esac

    # A stock ESP is often only 96-100MB, so a fixed threshold can exceed the
    # partition itself and make the check impossible to satisfy. Cap it.
    if [ -n "$total_mb" ] && [ "$required_mb" -ge "$total_mb" ]; then
        required_mb=$(( total_mb / 2 ))
        print_status "/boot/efi is only ${total_mb}MB - requiring ${required_mb}MB free instead"
    fi

    if [ "$available_mb" -ge "$required_mb" ]; then
        return 0
    fi

    print_error "/boot/efi does not have sufficient space"
    print_status "Available: ${available_mb}MB, Required: ${required_mb}MB"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - skipping automatic EFI cleanup"
        return 1
    fi

    if ! cleanup_efi_space; then
        print_warning "Unable to free sufficient space automatically"
        print_status "Manual cleanup needed: Check /boot/efi for old files"
        return 1
    fi

    print_success "Cleanup completed"

    # Recheck available space
    available_mb=$(get_efi_space_mb avail)
    print_status "Available space after cleanup: ${available_mb:-unknown}MB"

    if [ -z "$available_mb" ] || [ "$available_mb" -lt "$required_mb" ]; then
        print_error "Still insufficient space after cleanup"
        print_status "Required: ${required_mb}MB"
        print_status "Manual cleanup needed: Check /boot/efi for old files"
        return 1
    fi

    print_success "Sufficient space now available"
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
    local refresh_output
    local refresh_status
    refresh_output=$(eval "$refresh_cmd" 2>&1)
    refresh_status=$?

    if [ "$refresh_status" -eq 0 ]; then
        print_success "Firmware metadata refreshed"
    elif [ "$refresh_status" -eq "$FWUPD_EXIT_NOTHING_TO_DO" ]; then
        # fwupdmgr exits 2 when the metadata is already current - not a failure
        print_status "Firmware metadata is already up to date"
    else
        print_warning "Failed to refresh firmware metadata"
        [ -n "$refresh_output" ] && echo "$refresh_output"
    fi

    print_status "$checking_msg"

    # Check for firmware updates
    local check_cmd
    check_cmd=$(get_config "firmware.check_command")
    local firmware_output
    local check_status
    firmware_output=$(eval "$check_cmd" 2>&1)
    check_status=$?

    if [ "$check_status" -eq 0 ]; then
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "update_available"
        print_success "$updates_available_msg"
        echo "$firmware_output"

        # Check EFI space before prompting
        if ! check_efi_space; then
            local efi_remediation
            efi_remediation=$(get_remediation "insufficient_efi_space" "/boot/efi")
            emit_summary_event "firmware_readiness" "target" "fwupd" "status" "insufficient_efi_space" "remediation" "$efi_remediation"
            print_warning "Cannot proceed with firmware update due to insufficient space"
            return 1
        fi

        # Prompt to update firmware
        if prompt_yes_no "Update firmware now?"; then
            update_firmware
        else
            print_status "Skipping firmware update"
        fi
    elif [ "$check_status" -eq "$FWUPD_EXIT_NOTHING_TO_DO" ]; then
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "up_to_date"
        print_success "$no_updates_msg"
    else
        emit_summary_event "firmware_updates" "target" "fwupd" "status" "unknown"
        print_warning "Could not determine firmware update status (fwupdmgr exited $check_status)"
        [ -n "$firmware_output" ] && echo "$firmware_output"
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

    local update_status
    eval "$update_cmd"
    update_status=$?

    if [ "$update_status" -eq 0 ]; then
        print_success "$success_msg"
        # Capsule updates land at next power-on. On many systems (Dell in
        # particular) a warm reboot is not enough and fwupd asks for a full
        # shutdown, so say so rather than just "reboot".
        print_warning "Note: firmware is staged, not yet applied"
        print_status "Run 'fwupdmgr check-reboot-needed' to see what is pending; a full shutdown (power off), not just a reboot, may be required"
    elif [ "$update_status" -eq "$FWUPD_EXIT_NOTHING_TO_DO" ]; then
        # Typically a device that must be rebooted before the next update lands
        print_warning "No firmware was applied - a reboot may be required before fwupd can continue"
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
                print_status "$install_help"
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
