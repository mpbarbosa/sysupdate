#!/bin/bash
#
# update_lazygit.sh - lazygit Update Manager
# SNIPPET_ID: lazygit
# SNIPPET_NAME: lazygit (terminal UI for git)
#
# Handles version checking and updates for lazygit.
# Supports the official GitHub release tarball (standalone binary) and snap.
#
# Reference: https://github.com/jesseduffield/lazygit
#
# Version: 0.1.0-alpha
# Date: 2026-06-24
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-24) - Initial alpha version
#                            - GitHub release version check + tarball install
#                            - Refreshes the snap when lazygit resolves to a snap path
#

# Load upgrade utilities library
LAZYGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$LAZYGIT_SCRIPT_DIR/../lib" && pwd)"
CONFIG_FILE="$LAZYGIT_SCRIPT_DIR/lazygit.yaml"
source "$LIB_DIR/upgrade_utils.sh"

set -u
set -o pipefail

# Resolve the path of the active lazygit binary (following symlinks).
get_lazygit_resolved_path() {
    local binary
    binary=$(command -v lazygit 2>/dev/null) || return 1
    readlink -f "$binary" 2>/dev/null || echo "$binary"
}

# A lazygit install counts as "snap" only when the active binary lives under /snap.
is_lazygit_snap() {
    local resolved
    resolved=$(get_lazygit_resolved_path) || return 1
    [[ "$resolved" == /snap/* ]]
}

# Map uname -m to the lazygit release asset architecture token.
get_lazygit_asset_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "linux_x86_64" ;;
        aarch64|arm64) echo "linux_arm64" ;;
        armv6l|armv7l) echo "linux_armv6" ;;
        *) echo ""; return 1 ;;
    esac
}

# Resolve the latest release tarball download URL for this architecture.
get_lazygit_tarball_url() {
    local owner
    owner=$(get_config "version.github_owner")
    local repo
    repo=$(get_config "version.github_repo")
    local asset_arch
    asset_arch=$(get_lazygit_asset_arch) || return 1

    curl -fsSL "https://api.github.com/repos/$owner/$repo/releases/latest" 2>/dev/null | \
        grep '"browser_download_url"' | \
        sed -E 's/.*"([^"]+)".*/\1/' | \
        grep -E "lazygit_[0-9.]+_${asset_arch}\.tar\.gz$" | \
        head -1
}

# Determine where to install the binary: the directory of the active binary,
# falling back to the configured default install dir.
get_lazygit_install_path() {
    local binary_name
    binary_name=$(get_config "update.binary_name")
    local resolved
    resolved=$(get_lazygit_resolved_path 2>/dev/null)

    if [ -n "$resolved" ] && [[ "$resolved" != /snap/* ]]; then
        echo "$(dirname "$resolved")/$binary_name"
        return 0
    fi

    local default_dir
    default_dir=$(get_config "update.default_install_dir")
    echo "$default_dir/$binary_name"
}

perform_lazygit_update_snap() {
    local snap_package
    snap_package=$(get_config "update.snap_package_name")
    local output_lines
    output_lines=$(get_config "update.output_lines")

    print_status "$(get_config "messages.refreshing_snap")"

    local refresh_output
    refresh_output=$(run_with_sudo snap refresh "$snap_package" 2>&1)
    local refresh_exit_code=$?
    emit_captured_output "$refresh_output" "$output_lines"
    if [ $refresh_exit_code -ne 0 ]; then
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" \
        "${success_msg/\{version\}/$LATEST_VERSION}"
}

perform_lazygit_update_binary() {
    local download_url
    download_url=$(get_lazygit_tarball_url)
    if [ -z "$download_url" ]; then
        print_error "$(get_config "messages.failed_download_url")"
        return 1
    fi

    local temp_file
    temp_file=$(get_config "update.temp_file")
    if [ -z "$temp_file" ]; then
        temp_file=$(mktemp "/tmp/lazygit-update-XXXXXX.tar.gz") || return 1
    fi

    local install_path
    install_path=$(get_lazygit_install_path)
    local install_dir
    install_dir=$(dirname "$install_path")

    print_status "$(get_config "messages.downloading")"
    if ! download_with_progress "$download_url" "$temp_file"; then
        print_error "Failed to download lazygit release tarball"
        rm -f "$temp_file"
        return 1
    fi

    local extract_dir
    extract_dir=$(mktemp -d "/tmp/lazygit-extract-XXXXXX") || { rm -f "$temp_file"; return 1; }

    if ! tar -xzf "$temp_file" -C "$extract_dir" lazygit; then
        print_error "Failed to extract lazygit from the release tarball"
        rm -f "$temp_file"
        rm -rf "$extract_dir"
        return 1
    fi

    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "${installing_msg/\{path\}/$install_path}"

    # Use sudo only when the install directory is not writable by the user.
    local installer=()
    if [ ! -w "$install_dir" ]; then
        installer=(run_with_sudo)
    fi

    if ! "${installer[@]}" install -m 0755 "$extract_dir/lazygit" "$install_path"; then
        print_error "Failed to install the new lazygit binary to $install_path"
        rm -f "$temp_file"
        rm -rf "$extract_dir"
        return 1
    fi

    rm -f "$temp_file"
    rm -rf "$extract_dir"

    local success_msg
    success_msg=$(get_config "messages.update_success")
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" \
        "${success_msg/\{version\}/$LATEST_VERSION}"
}

update_lazygit() {
    if ! config_driven_version_check; then
        return 1
    fi

    local update_callback
    if is_lazygit_snap; then
        print_status "$(get_config "messages.detected_snap")"
        update_callback="perform_lazygit_update_snap"
    else
        print_status "$(get_config "messages.detected_binary")"
        update_callback="perform_lazygit_update_binary"
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "$update_callback"; then
        ask_continue
        return 1
    fi

    return 0
}

update_lazygit
