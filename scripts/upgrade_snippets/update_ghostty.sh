#!/bin/bash
#
# update_ghostty.sh - Ghostty Update Manager
# SNIPPET_ID: ghostty
# SNIPPET_NAME: Ghostty Terminal
#
# Handles version checking and updates for Ghostty.
# Supports apt, snap, and AppImage installations.
#
# Reference: https://ghostty.org/docs/install/binary
#
# Version: 0.1.0-alpha
# Date: 2026-05-28
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-28) - Initial alpha version
#                            - Supports apt, snap, and AppImage installations
#                            - Uses pkgforge Ghostty AppImage releases for AppImage updates
#

# Load upgrade utilities library
GHOSTTY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$GHOSTTY_SCRIPT_DIR/../lib" && pwd)"
CONFIG_FILE="$GHOSTTY_SCRIPT_DIR/ghostty.yaml"
source "$LIB_DIR/upgrade_utils.sh"

set -u
set -o pipefail

extract_semver() {
    local input="$1"

    echo "$input" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

normalize_apt_version() {
    local version="$1"

    echo "$version" | sed -E 's/^[0-9]+://; s/[+~-].*$//'
}

get_ghostty_appimage_install_path() {
    local install_dir
    install_dir=$(get_config "update.appimage_install_dir")
    local installed_filename
    installed_filename=$(get_config "update.appimage_installed_filename")

    echo "$install_dir/$installed_filename"
}

get_ghostty_appimage_binary() {
    local symlink
    symlink=$(get_config "update.appimage_symlink")
    local installed_path
    installed_path=$(get_ghostty_appimage_install_path)
    local resolved_path=""

    if [ -L "$symlink" ]; then
        resolved_path=$(readlink -f "$symlink" 2>/dev/null || true)
        if [ -n "$resolved_path" ] && [ -x "$resolved_path" ] && [[ "$resolved_path" = *.AppImage ]]; then
            echo "$resolved_path"
            return 0
        fi
    fi

    if [ -x "$installed_path" ]; then
        echo "$installed_path"
        return 0
    fi

    if command -v ghostty &>/dev/null; then
        resolved_path=$(readlink -f "$(command -v ghostty)" 2>/dev/null || true)
        if [ -n "$resolved_path" ] && [ -x "$resolved_path" ] && [[ "$resolved_path" = *.AppImage ]]; then
            echo "$resolved_path"
            return 0
        fi
    fi

    echo ""
}

get_current_ghostty_version() {
    local binary_path="${1:-ghostty}"

    "$binary_path" --version 2>&1 | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

get_ghostty_package_name() {
    get_config "update.apt_package_name"
}

get_ghostty_snap_name() {
    get_config "update.snap_package_name"
}

is_ghostty_snap() {
    local snap_package
    snap_package=$(get_ghostty_snap_name)

    command -v snap &>/dev/null && snap list "$snap_package" &>/dev/null
}

is_ghostty_apt() {
    local package_name
    package_name=$(get_ghostty_package_name)

    if ! command -v dpkg &>/dev/null; then
        return 1
    fi

    if is_ghostty_snap; then
        return 1
    fi

    if ! dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]\+$package_name[[:space:]]"; then
        return 1
    fi

    local package_version
    package_version=$(dpkg -l 2>/dev/null | awk -v pkg="$package_name" '$1 == "ii" && $2 == pkg { print $3; exit }')
    [[ "$package_version" == *snap* ]] && return 1

    return 0
}

is_ghostty_appimage() {
    [ -n "$(get_ghostty_appimage_binary)" ]
}

detect_ghostty_install_method() {
    if is_ghostty_snap; then
        echo "snap"
    elif is_ghostty_apt; then
        echo "apt"
    elif is_ghostty_appimage; then
        echo "appimage"
    else
        echo "unknown"
    fi
}

get_apt_candidate_ghostty_version() {
    local package_name
    package_name=$(get_ghostty_package_name)
    local candidate

    candidate=$(apt-cache policy "$package_name" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
        echo ""
        return 1
    fi

    normalize_apt_version "$candidate"
}

get_snap_candidate_ghostty_version() {
    local snap_package
    snap_package=$(get_ghostty_snap_name)
    local stable_line

    stable_line=$(snap info "$snap_package" 2>/dev/null | grep -m1 'stable:')
    extract_semver "$stable_line"
}

get_ghostty_appimage_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

get_latest_ghostty_appimage_release_info() {
    local owner
    owner=$(get_config "version.github_owner")
    local repo
    repo=$(get_config "version.github_repo")
    local asset_arch
    asset_arch=$(get_ghostty_appimage_arch) || return 1
    local release_json

    release_json=$(curl -fsSL "https://api.github.com/repos/$owner/$repo/releases/latest" 2>/dev/null)
    if [ -z "$release_json" ]; then
        echo ""
        return 1
    fi

    local tag_name
    tag_name=$(printf '%s\n' "$release_json" | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    local version
    version=$(extract_semver "$tag_name")
    local download_url
    download_url=$(printf '%s\n' "$release_json" | \
        grep '"browser_download_url"' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        grep -iE "ghostty.*${asset_arch}.*\.appimage$" | \
        head -1)

    if [ -z "$version" ] || [ -z "$download_url" ]; then
        echo ""
        return 1
    fi

    printf '%s|%s\n' "$version" "$download_url"
}

get_latest_ghostty_appimage_version() {
    local release_info
    release_info=$(get_latest_ghostty_appimage_release_info) || return 1

    echo "${release_info%%|*}"
}

perform_ghostty_update_apt() {
    local package_name
    package_name=$(get_ghostty_package_name)
    local refreshing_msg
    refreshing_msg=$(get_config "messages.refreshing_apt")
    local output_lines
    output_lines=$(get_config "update.output_lines")

    print_status "$refreshing_msg"

    if ! sudo apt-get update; then
        print_error "Failed to refresh apt package lists"
        return 1
    fi

    if [ "${VERBOSE_MODE:-false}" = "true" ]; then
        sudo apt-get install --only-upgrade -y "$package_name"
    else
        sudo apt-get install --only-upgrade -y "$package_name" 2>&1 | tail -"$output_lines"
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    success_msg="${success_msg/\{version\}/$LATEST_VERSION}"
    print_success "$success_msg"
    show_installation_info "$package_name" "$APP_DISPLAY_NAME"
}

perform_ghostty_update_snap() {
    local snap_package
    snap_package=$(get_ghostty_snap_name)
    local refreshing_msg
    refreshing_msg=$(get_config "messages.refreshing_snap")
    local output_lines
    output_lines=$(get_config "update.output_lines")

    print_status "$refreshing_msg"

    if [ "${VERBOSE_MODE:-false}" = "true" ]; then
        sudo snap refresh "$snap_package"
    else
        sudo snap refresh "$snap_package" 2>&1 | tail -"$output_lines"
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    success_msg="${success_msg/\{version\}/$LATEST_VERSION}"
    print_success "$success_msg"
    show_installation_info "$snap_package" "$APP_DISPLAY_NAME"
}

perform_ghostty_update_appimage() {
    local release_info
    release_info=$(get_latest_ghostty_appimage_release_info) || {
        local error_msg
        error_msg=$(get_config "messages.failed_download_url")
        print_error "$error_msg"
        return 1
    }

    local latest_version
    latest_version="${release_info%%|*}"
    local download_url
    download_url="${release_info#*|}"
    local install_dir
    install_dir=$(get_config "update.appimage_install_dir")
    local installed_path
    installed_path=$(get_ghostty_appimage_install_path)
    local symlink
    symlink=$(get_config "update.appimage_symlink")
    local temp_file
    temp_file=$(get_config "update.temp_file_appimage")
    local downloading_msg
    downloading_msg=$(get_config "messages.downloading_appimage")
    local installing_msg
    installing_msg=$(get_config "messages.installing_appimage")
    local creating_symlink_msg
    creating_symlink_msg=$(get_config "messages.creating_symlink")
    local backup_msg
    backup_msg=$(get_config "messages.backing_up_appimage")

    print_status "$downloading_msg"
    if ! wget -q --show-progress "$download_url" -O "$temp_file"; then
        print_error "Failed to download Ghostty AppImage"
        rm -f "$temp_file"
        return 1
    fi

    sudo mkdir -p "$install_dir" || {
        print_error "Failed to create Ghostty AppImage install directory"
        rm -f "$temp_file"
        return 1
    }

    if [ -f "$installed_path" ]; then
        local backup_path="${installed_path}.backup.$(date +%Y%m%d_%H%M%S)"
        backup_msg="${backup_msg/\{path\}/$backup_path}"
        print_status "$backup_msg"
        if ! sudo mv "$installed_path" "$backup_path"; then
            print_error "Failed to back up the existing Ghostty AppImage"
            rm -f "$temp_file"
            return 1
        fi
    fi

    print_status "$installing_msg"
    if ! sudo mv "$temp_file" "$installed_path"; then
        print_error "Failed to install the new Ghostty AppImage"
        rm -f "$temp_file"
        return 1
    fi

    if ! sudo chmod +x "$installed_path"; then
        print_error "Failed to mark the Ghostty AppImage as executable"
        return 1
    fi

    print_status "$creating_symlink_msg"
    if ! sudo ln -sf "$installed_path" "$symlink"; then
        print_error "Failed to update the Ghostty symlink"
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    success_msg="${success_msg/\{version\}/$latest_version}"
    print_success "$success_msg"
    show_installation_info "ghostty" "$APP_DISPLAY_NAME"
}

update_ghostty() {
    APP_DISPLAY_NAME=$(get_config "application.display_name")

    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"

    local install_method
    install_method=$(detect_ghostty_install_method)

    case "$install_method" in
        apt)
            print_status "$(get_config "messages.detected_apt")"
            CURRENT_VERSION=$(get_current_ghostty_version "ghostty")
            LATEST_VERSION=$(get_apt_candidate_ghostty_version)
            ;;
        snap)
            print_status "$(get_config "messages.detected_snap")"
            CURRENT_VERSION=$(get_current_ghostty_version "ghostty")
            LATEST_VERSION=$(get_snap_candidate_ghostty_version)
            ;;
        appimage)
            print_status "$(get_config "messages.detected_appimage")"
            local appimage_binary
            appimage_binary=$(get_ghostty_appimage_binary)
            CURRENT_VERSION=$(get_current_ghostty_version "$appimage_binary")
            LATEST_VERSION=$(get_latest_ghostty_appimage_version)
            ;;
        *)
            if command -v ghostty &>/dev/null; then
                CURRENT_VERSION=$(get_current_ghostty_version "ghostty")
                if [ -n "$CURRENT_VERSION" ]; then
                    print_status "Current version: $CURRENT_VERSION"
                fi
            fi
            print_warning "$(get_config "messages.unknown_install")"
            echo -e "$(get_config "messages.install_help")"
            ask_continue
            return 0
            ;;
    esac

    if [ -z "${CURRENT_VERSION:-}" ]; then
        print_error "$(get_config "messages.failed_version")"
        ask_continue
        return 1
    fi

    if [ -z "${LATEST_VERSION:-}" ]; then
        print_error "$(get_config "messages.failed_latest_version")"
        ask_continue
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    case "$install_method" in
        apt)
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_ghostty_update_apt"; then
                ask_continue
                return 1
            fi
            ;;
        snap)
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_ghostty_update_snap"; then
                ask_continue
                return 1
            fi
            ;;
        appimage)
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_ghostty_update_appimage"; then
                ask_continue
                return 1
            fi
            ;;
    esac

    return 0
}

update_ghostty
