#!/bin/bash
#
# update_rtk.sh - RTK (Rust Token Killer) Update Manager
# SNIPPET_ID: rtk
# SNIPPET_NAME: RTK (Rust Token Killer)
#
# Handles version checking and updates for RTK, a token-optimized CLI proxy.
# Reference: https://github.com/rtk-ai/rtk
#
# Version: 0.1.0-alpha
# Date: 2026-06-18
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-18) - Initial alpha version
#                            - Downloads architecture-specific tarball from GitHub releases
#                            - Installs to the same directory as the existing rtk binary
#                            - Supports x86_64 and aarch64 Linux
#
# Dependencies:
#   - curl
#   - tar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/rtk.yaml"

perform_rtk_update() {
    local arch
    arch=$(uname -m)
    local target
    case "$arch" in
        x86_64)          target="x86_64-unknown-linux-musl" ;;
        aarch64|arm64)   target="aarch64-unknown-linux-gnu" ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    local download_url="https://github.com/rtk-ai/rtk/releases/download/v${LATEST_VERSION}/rtk-${target}.tar.gz"

    local install_dir
    install_dir="$(dirname "$(command -v rtk 2>/dev/null)")"
    if [ -z "$install_dir" ] || [ "$install_dir" = "." ]; then
        install_dir="$HOME/.local/bin"
    fi

    local temp_dir
    temp_dir=$(mktemp -d) || return 1

    print_status "Downloading RTK v${LATEST_VERSION} (${target})..."
    if ! curl -fsSL "$download_url" -o "$temp_dir/rtk.tar.gz"; then
        print_error "Failed to download RTK from $download_url"
        rm -rf "$temp_dir"
        return 1
    fi

    print_status "Extracting archive..."
    if ! tar -xzf "$temp_dir/rtk.tar.gz" -C "$temp_dir"; then
        print_error "Failed to extract RTK archive"
        rm -rf "$temp_dir"
        return 1
    fi

    local rtk_binary
    rtk_binary=$(find "$temp_dir" -maxdepth 2 -name "rtk" -type f | head -1)
    if [ -z "$rtk_binary" ]; then
        print_error "rtk binary not found in downloaded archive"
        rm -rf "$temp_dir"
        return 1
    fi

    mkdir -p "$install_dir"
    if ! cp "$rtk_binary" "$install_dir/rtk" || ! chmod +x "$install_dir/rtk"; then
        print_error "Failed to install RTK binary to $install_dir"
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"

    local success_msg
    success_msg=$(get_config "messages.update_success")
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

update_rtk() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_rtk_update"; then
        ask_continue
        return 1
    fi
}

update_rtk
