#!/bin/bash
#
# update_zsh.sh - Zsh Shell Update Manager
# SNIPPET_ID: zsh
# SNIPPET_NAME: Zsh Shell
#
# Handles version checking and updates for zsh shell packages.
# Reference: https://www.zsh.org/
#
# Version: 0.1.0-alpha
# Date: 2026-06-13
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-13) - Initial alpha version
#                            - Checks active zsh version from `zsh --version`
#                            - Resolves latest package version from the active package manager
#                            - Updates zsh through shared package-manager helpers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/zsh.yaml"

show_zsh_install_help() {
    local install_help
    install_help=$(get_config "messages.install_help")

    if [ -z "$install_help" ]; then
        return 0
    fi

    local line
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            print_status "$line"
        else
            echo ""
        fi
    done <<< "$install_help"
}

get_latest_zsh_version_from_apt() {
    apt-cache policy zsh 2>/dev/null | awk '/Candidate:/ {print $2; exit}' | sed 's/-[^-]*$//'
}

get_latest_zsh_version_from_pacman() {
    pacman -Si zsh 2>/dev/null | awk '/^Version/ {print $3; exit}' | sed 's/-[^-]*$//'
}

get_latest_zsh_version_from_brew() {
    brew info --json=v2 zsh 2>/dev/null | tr -d '\n' | sed -nE 's/.*"stable":"([^"]+)".*/\1/p'
}

get_latest_zsh_version_from_dnf() {
    dnf info zsh 2>/dev/null | awk '/^Version/ {print $3; exit}'
}

get_latest_zsh_version_from_yum() {
    yum info zsh 2>/dev/null | awk '/^Version/ {print $3; exit}'
}

get_latest_zsh_version() {
    local latest_version=""

    if command -v apt-cache &>/dev/null; then
        latest_version=$(get_latest_zsh_version_from_apt)
    elif command -v pacman &>/dev/null; then
        latest_version=$(get_latest_zsh_version_from_pacman)
    elif command -v brew &>/dev/null; then
        latest_version=$(get_latest_zsh_version_from_brew)
    elif command -v dnf &>/dev/null; then
        latest_version=$(get_latest_zsh_version_from_dnf)
    elif command -v yum &>/dev/null; then
        latest_version=$(get_latest_zsh_version_from_yum)
    fi

    if [ -z "$latest_version" ]; then
        echo ""
        return 1
    fi

    echo "$latest_version"
}

perform_zsh_update() {
    local previous_version="${1:-$CURRENT_VERSION}"
    local expected_version="${2:-$LATEST_VERSION}"
    local package_name
    package_name=$(get_config "application.name")

    if ! update_via_package_manager "$package_name" "zsh"; then
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    verify_configured_update_result "$previous_version" "$expected_version" "$success_msg"
}

zsh_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"

    APP_DISPLAY_NAME=$(get_config "application.display_name")
    if [ -z "$APP_DISPLAY_NAME" ]; then
        APP_DISPLAY_NAME="Zsh Shell"
    fi

    if ! check_app_installed "zsh" "$APP_DISPLAY_NAME"; then
        show_zsh_install_help
        return 2
    fi

    CURRENT_VERSION=$(get_current_version_from_config)
    if [ -z "$CURRENT_VERSION" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_get_version")
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        return 1
    fi

    LATEST_VERSION=$(get_latest_zsh_version)
    if [ -z "$LATEST_VERSION" ]; then
        local failed_latest_msg
        failed_latest_msg=$(get_config "messages.failed_latest_version")
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_error "$failed_latest_msg"
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?
    return 0
}

update_zsh() {
    zsh_version_check
    local check_status=$?

    case "$check_status" in
        0)
            ;;
        2)
            ask_continue
            return 0
            ;;
        *)
            ask_continue
            return 0
            ;;
    esac

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_zsh_update '$CURRENT_VERSION' '$LATEST_VERSION'"; then
        ask_continue
        return 1
    fi
}

update_zsh
