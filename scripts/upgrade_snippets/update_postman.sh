#!/bin/bash
#
# update_postman.sh - Postman Update Manager
# SNIPPET_ID: postman
# SNIPPET_NAME: Postman API Platform
#
# Handles version checking and updates for Postman API Platform.
# Supports both snap and tarball installations.
#
# Reference: https://learning.postman.com/docs/getting-started/installation/installation-and-updates/
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/postman.yaml"
# shellcheck source=../lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$LIB_DIR/upgrade_utils.sh"

POSTMAN_INSTALL_METHOD=""
POSTMAN_REQUIRES_MIGRATION=false
POSTMAN_BACKUP_DIR=""

verbose_enabled() {
    [ "${VERBOSE:-0}" -eq 1 ] || [ "${VERBOSE_MODE:-false}" = "true" ]
}

print_postman_message_block() {
    local message="$1"
    local line

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            print_status "$line"
        else
            echo ""
        fi
    done <<< "$message"
}

show_postman_install_help() {
    local install_help
    install_help=$(get_config "messages.install_help")
    print_postman_message_block "$install_help"
}

get_postman_snap_installed_version() {
    snap info postman 2>/dev/null | awk '/^installed:/ {print $2; exit}'
}

get_postman_snap_latest_version() {
    snap info postman 2>/dev/null | awk '/v11\/stable:/ {print $2; exit}'
}

verify_postman_snap_update() {
    local previous_version="$1"
    local latest_version="$2"
    local current_version
    current_version=$(get_postman_snap_installed_version)

    if [ -z "$current_version" ]; then
        print_error "Failed to verify current Postman snap version after update"
        return 1
    fi

    print_status "Installed version: $current_version"

    if [ "$current_version" = "$previous_version" ]; then
        print_error "Postman snap version did not change after update"
        return 1
    fi

    compare_versions "$current_version" "$latest_version"
    local version_cmp=$?
    if [ $version_cmp -eq 2 ]; then
        print_error "Postman snap update did not reach the expected version: $current_version < $latest_version"
        return 1
    fi

    if [ $version_cmp -eq 1 ]; then
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "ahead_of_latest" "current_version" "$current_version" "latest_version" "$latest_version" "install_method" "snap"
    else
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version" "install_method" "snap"
    fi

    return 0
}

verify_postman_tarball_update() {
    local previous_version="$1"
    local latest_version="$2"
    local current_version
    current_version=$(get_tarball_version)

    if [ -z "$current_version" ]; then
        print_error "Failed to verify current Postman tarball version after update"
        return 1
    fi

    print_status "Installed version: $current_version"

    if [ "$current_version" = "$previous_version" ]; then
        print_error "Postman tarball version did not change after update"
        return 1
    fi

    compare_versions "$current_version" "$latest_version"
    local version_cmp=$?
    if [ $version_cmp -eq 2 ]; then
        print_error "Postman tarball update did not reach the expected version: $current_version < $latest_version"
        return 1
    fi

    if [ $version_cmp -eq 1 ]; then
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "ahead_of_latest" "current_version" "$current_version" "latest_version" "$latest_version" "install_method" "tarball"
    else
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version" "install_method" "tarball"
    fi

    return 0
}

# Override version check for Postman (snap has special requirements)
check_postman_version() {
    print_operation_header "Checking Postman updates..."
    APP_DISPLAY_NAME=$(get_config "application.display_name")
    POSTMAN_REQUIRES_MIGRATION=false
    POSTMAN_INSTALL_METHOD=""
    
    # Check if Postman is installed
    if verbose_enabled; then
        print_status "Verifying Postman installation..."
    fi
    if ! command -v postman &>/dev/null; then
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_error "Postman is not installed"
        show_postman_install_help
        ask_continue
        return 1
    fi
    if verbose_enabled; then
        print_success "Postman installation detected"
    fi
    
    # Detect installation method first
    if verbose_enabled; then
        print_status "Detecting installation method..."
    fi
    local install_method
    install_method=$(detect_install_method)
    POSTMAN_INSTALL_METHOD="$install_method"
    if verbose_enabled; then
        print_success "Installation method: $install_method"
    fi
    
    if verbose_enabled; then
        print_status "Retrieving version information..."
    fi
    if [[ "$install_method" == "snap" ]]; then
        CURRENT_VERSION=$(get_postman_snap_installed_version)
        if [ -z "$CURRENT_VERSION" ]; then
            emit_summary_event "version_check" "target" "Postman API Platform" "status" "unknown" "current_version" "unknown" "latest_version" "unknown" "install_method" "snap"
            print_error "Failed to get current Postman version"
            ask_continue
            return 1
        fi

        # Check if snap version is compatible
        if ! check_snap_compatibility; then
            print_error "Snap version of Postman is incompatible with your system"
            echo ""
            local incompatible_msg
            incompatible_msg=$(get_config "messages.snap_incompatible")
            print_postman_message_block "$incompatible_msg"
            echo ""
            if verbose_enabled; then
                print_status "Offering migration to tarball installation..."
            fi
            LATEST_VERSION=$(get_latest_tarball_version)
            if [ -z "$LATEST_VERSION" ]; then
                LATEST_VERSION="unknown"
            fi
            POSTMAN_REQUIRES_MIGRATION=true
            if [ "$CHECK_ONLY_MODE" = true ]; then
                print_status "Check-only mode - Postman snap installation requires tarball migration for a live update."
            else
                print_status "Postman will use tarball migration for the update path."
            fi
            emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION" "install_method" "snap" "recommended_install_method" "tarball"
        else
            if verbose_enabled; then
                print_success "Snap version is compatible"
            fi

            # Get latest available version from snap channel
            LATEST_VERSION=$(get_postman_snap_latest_version)
            
            if [ -z "$LATEST_VERSION" ]; then
                print_warning "Could not determine latest version from snap"
                LATEST_VERSION="$CURRENT_VERSION"
            fi
        fi
    elif [[ "$install_method" == "tarball" ]]; then
        # For tarball, get the installed app version from local metadata.
        CURRENT_VERSION=$(get_tarball_version)
        
        if [ -z "$CURRENT_VERSION" ]; then
            emit_summary_event "version_check" "target" "Postman API Platform" "status" "unknown" "current_version" "unknown" "latest_version" "unknown" "install_method" "tarball"
            print_error "Could not determine current tarball version"
            ask_continue
            return 1
        fi
        
        LATEST_VERSION=$(get_latest_tarball_version)
        if [ -z "$LATEST_VERSION" ]; then
            emit_summary_event "version_check" "target" "Postman API Platform" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown" "install_method" "tarball"
            print_warning "Could not determine latest tarball version"
            print_status "Installed tarball version: $CURRENT_VERSION"
            ask_continue
            return 1
        fi
    else
        emit_summary_event "version_check" "target" "Postman API Platform" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "Could not detect Postman installation"
        ask_continue
        return 1
    fi
    
    # Compare versions
    if verbose_enabled; then
        print_success "Retrieved version information"
    fi
    print_status "Current version: $CURRENT_VERSION"
    print_status "Latest version: $LATEST_VERSION"
    
    if [ "$POSTMAN_REQUIRES_MIGRATION" = true ]; then
        VERSION_STATUS=2
    elif [[ "$LATEST_VERSION" == "latest" ]] || [[ "$CURRENT_VERSION" == "unknown" ]]; then
        if verbose_enabled; then
            print_status "Assuming update is available for tarball installation"
        fi
        VERSION_STATUS=2
    else
        compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"
        VERSION_STATUS=$?
    fi
    
    if [ "$POSTMAN_REQUIRES_MIGRATION" != true ]; then
        case "$VERSION_STATUS" in
            0)
                emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "up_to_date" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION" "install_method" "$install_method"
                ;;
            1)
                emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "ahead_of_latest" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION" "install_method" "$install_method"
                ;;
            2)
                emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION" "install_method" "$install_method"
                ;;
        esac
    fi
    
    return 0
}

# Check if snap version is compatible with the system
check_snap_compatibility() {
    if verbose_enabled; then
        print_status "Checking snap compatibility..."
    fi
    # Try to get version info - if it fails with library error, it's incompatible
    # Try to get snap postman version with a timeout to avoid hangs
    local snap_output rc
    snap_output=$(timeout 2s snap run postman --version 2>&1) || rc=$?
    rc=${rc:-0}
    # timeout exit code is 124 -> treat as incompatible
    if [ "$rc" -eq 124 ]; then
        return 1
    fi
    # Any GLIBC related error indicates incompatibility
    if echo "$snap_output" | grep -q -E "GLIBC|libc\.so\.6"; then
        return 1
    fi
    # Quick test - just check if command exists without error
    if ! timeout 2 postman --version &>/dev/null; then
        # Command failed or timed out - likely compatibility issue
        return 1
    fi
    return 0
}

# Migrate from snap to tarball installation
migrate_snap_to_tarball() {
    print_operation_header "Migrating from snap to tarball installation"
    
    # Confirm with user
    if ! prompt_yes_no "Remove snap version and install tarball?"; then
        print_status "Migration cancelled"
        return 1
    fi
    
    # Remove snap
    print_status "Removing snap version..."
    if ! run_with_sudo snap remove postman; then
        print_error "Failed to remove snap version"
        return 1
    fi
    
    print_success "Snap version removed"
    
    # Install tarball
    print_status "Installing tarball version..."
    if ! perform_postman_update "$CURRENT_VERSION" "$LATEST_VERSION"; then
        print_error "Failed to install tarball version"
        return 1
    fi
    
    print_success "Migration completed successfully!"
    return 0
}

# Get version from tarball installation
get_tarball_version() {
    local install_dir
    install_dir=$(get_config "update.install_dir")
    
    if [ -f "$install_dir/version" ]; then
        cat "$install_dir/version"
        return 0
    fi

    local package_json="$install_dir/app/resources/app/package.json"
    if [ -f "$package_json" ]; then
        sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$package_json" | head -1
        return 0
    else
        echo ""
    fi
}

# Get latest version from the downloadable tarball metadata without fetching the full archive.
get_latest_tarball_version() {
    local download_url
    download_url=$(get_config "update.download_url")
    local temp_tarball
    temp_tarball=$(mktemp) || return 1

    if ! curl -fsS -r 0-12000000 "$download_url" -o "$temp_tarball"; then
        rm -f "$temp_tarball"
        return 1
    fi

    local latest_version
    latest_version=$(tar -xOf "$temp_tarball" Postman/app/resources/app/package.json 2>/dev/null | \
        sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -1)

    rm -f "$temp_tarball"

    if [ -z "$latest_version" ]; then
        return 1
    fi

    echo "$latest_version"
}

# Detect installation method
detect_install_method() {
    if command -v snap &>/dev/null && snap list postman &>/dev/null 2>&1; then
        echo "snap"
    elif [ -d "/opt/Postman" ]; then
        echo "tarball"
    else
        echo "unknown"
    fi
}

# Update via snap
update_via_snap() {
    local previous_version="$1"
    local latest_version="$2"
    local update_msg
    update_msg=$(get_config "messages.updating_snap")
    print_status "$update_msg"
    
    if ! run_with_sudo snap refresh postman; then
        print_error "Failed to update Postman via snap"
        return 1
    fi

    if ! verify_postman_snap_update "$previous_version" "$latest_version"; then
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"
    show_installation_info "postman" "$APP_DISPLAY_NAME"
    return 0
}

# Backup existing Postman installation
backup_postman() {
    local install_dir
    install_dir=$(get_config "update.install_dir")
    POSTMAN_BACKUP_DIR=""
    
    if [[ -d "$install_dir" ]]; then
        local backup_msg
        backup_msg=$(get_config "messages.backing_up")
        print_status "$backup_msg"
        
        local backup_dir
        backup_dir="${install_dir}.backup.$(date +%Y%m%d_%H%M%S)"
        run_with_sudo mv "$install_dir" "$backup_dir" || {
            print_error "Failed to backup existing installation"
            return 1
        }
        POSTMAN_BACKUP_DIR="$backup_dir"
        print_success "Backed up to $backup_dir"
    fi
}

restore_postman_backup() {
    local install_dir
    install_dir=$(get_config "update.install_dir")

    if [ -n "$POSTMAN_BACKUP_DIR" ] && [ -d "$POSTMAN_BACKUP_DIR" ]; then
        if [ -d "$install_dir" ]; then
            run_with_sudo rm -rf "$install_dir" || return 1
        fi
        run_with_sudo mv "$POSTMAN_BACKUP_DIR" "$install_dir" || return 1
        POSTMAN_BACKUP_DIR=""
    fi
}

# Install Postman from tarball
install_postman_tarball() {
    local tarball="$1"
    local install_dir
    install_dir=$(get_config "update.install_dir")
    local symlink_path
    symlink_path=$(get_config "update.symlink_path")
    
    # Create temporary extraction directory
    local extract_dir
    extract_dir=$(mktemp -d) || {
        print_error "Cannot create temp directory"
        return 1
    }
    
    # Extract tarball
    local extracting_msg
    extracting_msg=$(get_config "messages.extracting")
    print_status "$extracting_msg"
    
    if ! tar -xzf "$tarball" -C "$extract_dir" 2>/dev/null; then
        rm -rf "$extract_dir"
        print_error "Failed to extract tarball"
        return 1
    fi
    
    # Install to /opt
    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "$installing_msg"
    
    if ! run_with_sudo mv "$extract_dir/Postman" "$install_dir"; then
        rm -rf "$extract_dir"
        print_error "Failed to move to $install_dir"
        return 1
    fi
    rm -rf "$extract_dir"
    
    # Create symbolic link
    local symlink_msg
    symlink_msg=$(get_config "messages.creating_symlink")
    print_status "$symlink_msg"
    
    run_with_sudo ln -sf "$install_dir/Postman" "$symlink_path" || {
        print_error "Failed to create symlink"
        return 1
    }
    
    # Create desktop entry
    create_desktop_entry
    
    return 0
}

# Create desktop entry for application launcher
create_desktop_entry() {
    local desktop_msg
    desktop_msg=$(get_config "messages.creating_desktop")
    print_status "$desktop_msg"
    
    local install_dir
    install_dir=$(get_config "update.install_dir")
    local desktop_file="$HOME/.local/share/applications/postman.desktop"
    
    mkdir -p "$(dirname "$desktop_file")"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Encoding=UTF-8
Name=Postman
Exec=$install_dir/Postman
Icon=$install_dir/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
    
    chmod +x "$desktop_file"
}

# Perform Postman update workflow
perform_postman_update() {
    local previous_version="$1"
    local latest_version="$2"
    local download_url
    download_url=$(get_config "update.download_url")
    local download_msg
    download_msg=$(get_config "messages.downloading")
    
    # Create temporary file for download
    local temp_tarball
    temp_tarball=$(mktemp --suffix=.tar.gz) || {
        print_error "Cannot create temp file"
        return 1
    }
    
    # Download latest tarball
    print_status "$download_msg"
    if ! download_with_progress "$download_url" "$temp_tarball"; then
        rm -f "$temp_tarball"
        print_error "Failed to download Postman"
        return 1
    fi
    
    # Backup and install
    if ! backup_postman; then
        rm -f "$temp_tarball"
        return 1
    fi
    
    if ! install_postman_tarball "$temp_tarball"; then
        rm -f "$temp_tarball"
        restore_postman_backup || print_warning "Failed to restore previous Postman backup"
        return 1
    fi
    rm -f "$temp_tarball"
    
    if ! verify_postman_tarball_update "$previous_version" "$latest_version"; then
        restore_postman_backup || print_warning "Failed to restore previous Postman backup"
        return 1
    fi

    POSTMAN_BACKUP_DIR=""
    
    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"
    show_installation_info "postman" "$APP_DISPLAY_NAME"
}

# Main update function
update_postman() {
    # Use custom version check
    if ! check_postman_version; then
        return 0
    fi
    
    # Detect installation method
    local install_method
    install_method="${POSTMAN_INSTALL_METHOD:-$(detect_install_method)}"
    local update_callback
    
    # Handle update based on installation method
    if [[ "$install_method" == "snap" ]]; then
        if [ "$POSTMAN_REQUIRES_MIGRATION" = true ]; then
            update_callback="migrate_snap_to_tarball"
        else
            update_callback="update_via_snap '$CURRENT_VERSION' '$LATEST_VERSION'"
        fi
    elif [[ "$install_method" == "tarball" ]]; then
        update_callback="perform_postman_update '$CURRENT_VERSION' '$LATEST_VERSION'"
    else
        print_error "Could not detect Postman installation method"
        show_postman_install_help
        ask_continue
        return 1
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "$update_callback"; then
        ask_continue
        return 1
    fi
}

update_postman
