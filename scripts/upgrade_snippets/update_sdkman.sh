#!/bin/bash
#
# update_sdkman.sh - SDKMAN! Update Manager
# SNIPPET_ID: sdkman
# SNIPPET_NAME: SDKMAN!
#
# Handles version checking and updates for the SDKMAN! CLI itself.
# Reference: https://sdkman.io/
#
# Version: 0.1.1-alpha
# Date: 2026-05-10
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.1-alpha (2026-05-10) - Temporarily disables nounset while sourcing
#                            - SDKMAN! init so non-interactive strict shells work
#   0.1.0-alpha (2026-05-10) - Initial version
#                            - Loads SDKMAN! in non-interactive shells
#                            - Compares installed version with sdkman/sdkman-cli release
#                            - Updates via `sdk selfupdate`
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
# shellcheck source=../lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$LIB_DIR/upgrade_utils.sh"

get_sdkman_dir() {
    if [ -n "${SDKMAN_DIR:-}" ]; then
        echo "$SDKMAN_DIR"
        return 0
    fi

    echo "$HOME/.sdkman"
}

get_sdkman_init_script() {
    local sdkman_dir
    sdkman_dir=$(get_sdkman_dir)
    echo "$sdkman_dir/bin/sdkman-init.sh"
}

show_sdkman_install_help() {
    local init_script
    init_script=$(get_sdkman_init_script)
    print_status "Install SDKMAN! with: curl -s \"https://get.sdkman.io\" | bash"
    print_status "Expected SDKMAN! init script: $init_script"
}

emit_sdkman_not_installed_summary() {
    emit_summary_event "version_check" \
        "target" "SDKMAN!" \
        "status" "not_installed" \
        "current_version" "unknown" \
        "latest_version" "unknown"
}

emit_sdkman_unknown_summary() {
    local current_version="${1:-unknown}"
    local latest_version="${2:-unknown}"

    emit_summary_event "version_check" \
        "target" "SDKMAN!" \
        "status" "unknown" \
        "current_version" "$current_version" \
        "latest_version" "$latest_version"
}

load_sdkman_environment() {
    local init_script
    local restore_nounset=false
    local source_status=0
    init_script=$(get_sdkman_init_script)

    if [ ! -f "$init_script" ]; then
        emit_sdkman_not_installed_summary
        print_status "SDKMAN! is not installed in $(get_sdkman_dir)"
        show_sdkman_install_help
        return 1
    fi

    if [[ $- == *u* ]]; then
        restore_nounset=true
        set +u
    fi

    # shellcheck source=/dev/null
    source "$init_script"
    source_status=$?

    if [ "$restore_nounset" = true ]; then
        set -u
    fi

    if [ "$source_status" -ne 0 ]; then
        emit_sdkman_unknown_summary
        print_error "Failed to initialize SDKMAN! from $init_script"
        return 1
    fi

    if ! command -v sdk >/dev/null 2>&1; then
        emit_sdkman_unknown_summary
        print_error "Failed to initialize SDKMAN! from $init_script"
        return 1
    fi

    return 0
}

get_sdkman_current_version() {
    local version_output
    local parsed_version
    version_output=$(sdk version 2>&1)

    parsed_version=$(printf '%s\n' "$version_output" | sed -nE '
        s/^script:[[:space:]]*([0-9]+(\.[0-9]+)+([+.-][0-9A-Za-z._-]+)?).*/\1/p
        t
        s/^([0-9]+(\.[0-9]+)+([+.-][0-9A-Za-z._-]+)?)$/\1/p
        t
        s/.*SDKMAN!?[^0-9]*([0-9]+(\.[0-9]+)+([+.-][0-9A-Za-z._-]+)?).*/\1/p
    ' | head -1)

    if [ -n "$parsed_version" ]; then
        echo "$parsed_version"
        return 0
    fi

    local sdkman_dir
    sdkman_dir=$(get_sdkman_dir)

    if [ -f "$sdkman_dir/var/version" ]; then
        sed -nE 's/^([0-9]+(\.[0-9]+)+([+.-][0-9A-Za-z._-]+)?)$/\1/p' \
            "$sdkman_dir/var/version" | head -1
        return 0
    fi

    echo ""
}

get_sdkman_latest_version() {
    get_github_latest_version "sdkman" "sdkman-cli"
}

show_sdkman_installation_info() {
    if [ "${VERBOSE_MODE:-false}" != "true" ]; then
        return 0
    fi

    print_status "SDKMAN! directory: $(get_sdkman_dir)"
}

perform_sdkman_update() {
    local previous_version="$1"
    local latest_version="$2"
    local success_msg="SDKMAN! updated"

    if ! sdk selfupdate; then
        print_error "Failed to update SDKMAN!"
        return 1
    fi

    local installed_version
    installed_version=$(get_sdkman_current_version)
    if [ -z "$installed_version" ]; then
        print_error "Failed to verify SDKMAN! version after update"
        return 1
    fi

    print_status "Installed version: $installed_version"

    if [ -n "$previous_version" ] && [ "$installed_version" = "$previous_version" ]; then
        print_error "SDKMAN! version did not change after update"
        return 1
    fi

    compare_versions "$installed_version" "$latest_version"
    local version_cmp=$?
    if [ $version_cmp -eq 2 ]; then
        print_error "SDKMAN! update did not reach the expected version: $installed_version < $latest_version"
        return 1
    fi

    print_success "$success_msg"

    if [ $version_cmp -eq 1 ]; then
        emit_summary_event "version_check" "target" "SDKMAN!" "status" "ahead_of_latest" "current_version" "$installed_version" "latest_version" "$latest_version"
    else
        emit_summary_event "version_check" "target" "SDKMAN!" "status" "up_to_date" "current_version" "$installed_version" "latest_version" "$latest_version"
    fi

    show_sdkman_installation_info
    return 0
}

update_sdkman() {
    print_operation_header "Checking SDKMAN! updates..."

    if ! load_sdkman_environment; then
        ask_continue
        return 0
    fi

    local current_version
    current_version=$(get_sdkman_current_version)
    if [ -z "$current_version" ]; then
        emit_sdkman_unknown_summary
        print_error "Failed to get current SDKMAN! version"
        ask_continue
        return 0
    fi

    local latest_version
    latest_version=$(get_sdkman_latest_version)

    APP_DISPLAY_NAME="SDKMAN!"
    compare_and_report_versions "$current_version" "$latest_version" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_sdkman_update '$current_version' '$latest_version'"; then
        ask_continue
        return 1
    fi
}

update_sdkman
