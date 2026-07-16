#!/bin/bash
#
# update_fastfetch.sh - Fastfetch Update Manager
# SNIPPET_ID: fastfetch
# SNIPPET_NAME: Fastfetch
#
# Handles installation, version checking, and updates for Fastfetch, the
# system-info tool used by scripts/system_summary.sh. Tracks the upstream
# fastfetch-cli/fastfetch releases and installs the official prebuilt .deb
# (ahead of distro repos). When Fastfetch is not installed, it offers to install
# it from the same upstream .deb.
# Reference: https://github.com/fastfetch-cli/fastfetch
#
# Version: 0.3.0-alpha
# Date: 2026-07-14
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-07-07) - Initial apt-based version check and update
#   0.2.0-alpha (2026-07-14) - Switched to upstream github .deb (config-driven
#                              github version source + deb package update)
#   0.3.0-alpha (2026-07-14) - Install from the upstream github .deb when not
#                              installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/fastfetch.yaml"

# Install Fastfetch from the upstream github .deb when it is not present.
# Reuses the same deb download/install machinery as the update path, so the
# install channel matches the version source.
install_fastfetch_from_github() {
    APP_DISPLAY_NAME=$(get_config "application.display_name")
    [ -n "$APP_DISPLAY_NAME" ] || APP_DISPLAY_NAME="Fastfetch"

    print_operation_header "$(get_config messages.checking_updates)"
    print_warning "$APP_DISPLAY_NAME is not installed"

    # Best-effort latest version (github source, with the shared rate-limit
    # fallback). Used for the summary event and post-install verification.
    LATEST_VERSION=$(get_github_latest_version \
        "$(get_config version.github_owner)" "$(get_config version.github_repo)")
    # Read cross-module by perform_configured_deb_package_update / verify.
    # shellcheck disable=SC2034
    CURRENT_VERSION=""

    # Always emit at least one summary so consumers see the not-installed state
    # even when the user declines or we are in check-only mode.
    emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
        "status" "not_installed" "current_version" "not_installed" \
        "latest_version" "${LATEST_VERSION:-unknown}"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - skipping $APP_DISPLAY_NAME install"
        ask_continue
        return 0
    fi

    if ! prompt_yes_no "Install $APP_DISPLAY_NAME from the official GitHub release?"; then
        print_status "Skipping $APP_DISPLAY_NAME install"
        local install_help
        install_help=$(get_config messages.install_help)
        [ -n "$install_help" ] && printf '%s\n' "$install_help"
        ask_continue
        return 0
    fi

    # Downloads the .deb via the stable releases/latest/download redirect,
    # installs with dpkg, repairs dependencies, and verifies + emits the summary.
    if ! perform_configured_deb_package_update; then
        ask_continue
        return 1
    fi
}

update_fastfetch() {
    local app_cmd
    app_cmd=$(get_config "application.command")

    if ! command -v "${app_cmd:-fastfetch}" &>/dev/null; then
        install_fastfetch_from_github
        return $?
    fi

    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    # Downloads the .deb via the stable releases/latest/download redirect,
    # installs with dpkg, repairs dependencies, and verifies the installed
    # version reached the latest release (emits the summary event).
    if ! handle_deb_package_update; then
        ask_continue
        return 1
    fi
}

update_fastfetch
