#!/bin/bash
#
# update_matchmaker.sh - Matchmaker CLI Update Manager
# SNIPPET_ID: matchmaker
# SNIPPET_NAME: Matchmaker CLI
#
# Handles installation and updates for Matchmaker CLI via the official
# prebuilt-binary installer (install.sh).
# Reference: https://github.com/Squirreljetpack/matchmaker
#
# Version: 0.2.0-alpha
# Date: 2026-07-03
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-26) - Initial alpha version
#                            - Cargo-only install/update workflow
#                            - Supports install when Matchmaker is missing
#   0.2.0-alpha (2026-07-03) - Switched from `cargo install matchmaker-cli` to the
#                              official installer: crates.io is frozen at 0.0.42
#                              (GitHub releases advance independently) and the 0.0.42
#                              build no longer compiles. Installed version is tracked
#                              in a stamp file since `mm` has no --version flag.
#

MATCHMAKER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$MATCHMAKER_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

CONFIG_FILE="$MATCHMAKER_SCRIPT_DIR/matchmaker.yaml"

# `mm` has no --version flag and the prebuilt release binary embeds no version
# string, so the installed version is tracked in this stamp file. It is exported
# because matchmaker.yaml's version.command reads it via eval (get_config).
export MATCHMAKER_VERSION_FILE="${SYSUPDATE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/sysupdate}/matchmaker.version"

# Record the version the installer just placed so the next run can compare
# against GitHub releases. The installer always fetches the latest release, so
# the stamp is LATEST_VERSION (set during the update flow) or, when unset (the
# install-if-missing path), a fresh GitHub lookup. A blank result is not stamped.
write_matchmaker_stamp() {
    local ver="$LATEST_VERSION"
    if [ -z "$ver" ]; then
        local owner repo
        owner=$(get_config "version.github_owner")
        repo=$(get_config "version.github_repo")
        ver=$(get_github_latest_version "$owner" "$repo")
    fi
    [ -z "$ver" ] && return 0
    mkdir -p "$(dirname "$MATCHMAKER_VERSION_FILE")" 2>/dev/null
    printf '%s\n' "$ver" > "$MATCHMAKER_VERSION_FILE"
}

perform_matchmaker_install_or_update() {
    local update_cmd
    update_cmd=$(get_config "update.command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local update_output

    if ! update_output=$(eval "$update_cmd" 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
        print_error "Failed to install/update $APP_DISPLAY_NAME"
        return 1
    fi

    [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
    write_matchmaker_stamp
    print_success "$success_msg"
    show_installation_info "mm" "$APP_DISPLAY_NAME"
    return 0
}

install_matchmaker_if_missing() {
    local install_help
    install_help=$(get_config "messages.install_help")
    local install_prompt
    install_prompt=$(get_config "messages.install_prompt")
    APP_DISPLAY_NAME=$(get_config "application.display_name")

    print_status "$install_help"

    if ! prompt_yes_no "$install_prompt"; then
        print_status "Skipping $APP_DISPLAY_NAME installation"
        ask_continue
        return 0
    fi

    if ! perform_matchmaker_install_or_update; then
        ask_continue
        return 1
    fi

    ask_continue
    return 0
}

update_matchmaker() {
    local dep_name
    dep_name=$(get_config "dependencies[0].name")
    local dep_cmd
    dep_cmd=$(get_config "dependencies[0].command")
    local dep_help
    dep_help=$(get_config "dependencies[0].help")

    if ! check_app_installed_or_help "$dep_name" "$dep_cmd" "$dep_help"; then
        return 0
    fi

    if ! check_app_installed "mm" "Matchmaker CLI"; then
        install_matchmaker_if_missing
        return $?
    fi

    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_matchmaker_install_or_update"; then
        ask_continue
        return 1
    fi
}

update_matchmaker
