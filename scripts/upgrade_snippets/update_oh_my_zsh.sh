#!/bin/bash
#
# update_oh_my_zsh.sh - Oh My Zsh Update Manager
# SNIPPET_ID: oh-my-zsh
# SNIPPET_NAME: Oh My Zsh
#
# Handles version checking and updates for Oh My Zsh.
# Reference: https://github.com/ohmyzsh/ohmyzsh
#
# Version: 0.1.0-alpha
# Date: 2026-05-04
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-04) - Initial alpha version
#                            - Uses custom git commit-based update detection
#                            - Updates Oh My Zsh via fast-forward git pull
#

OH_MY_ZSH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OH_MY_ZSH_LIB_DIR="$(cd "$OH_MY_ZSH_SCRIPT_DIR/../lib" && pwd)"
source "$OH_MY_ZSH_LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$OH_MY_ZSH_SCRIPT_DIR/oh_my_zsh.yaml"

get_oh_my_zsh_install_dir() {
    if [ -n "${ZSH:-}" ]; then
        echo "$ZSH"
        return 0
    fi

    local configured_install_dir
    configured_install_dir=$(get_config "application.installation_dir")

    if [ -z "$configured_install_dir" ]; then
        echo "$HOME/.oh-my-zsh"
        return 0
    fi

    case "$configured_install_dir" in
        "\${ZSH:-\${HOME}/.oh-my-zsh}"|"\${ZSH:-\$HOME/.oh-my-zsh}")
            echo "$HOME/.oh-my-zsh"
            ;;
        "\${HOME}/"*)
            echo "${configured_install_dir//\$\{HOME\}/$HOME}"
            ;;
        "\$HOME/"*)
            echo "${configured_install_dir//\$HOME/$HOME}"
            ;;
        *)
            echo "$configured_install_dir"
            ;;
    esac
}

show_oh_my_zsh_install_help() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    local install_help
    install_help=$(get_config "messages.install_help")
    install_help="${install_help//\{path\}/$install_dir}"
    if [ -n "$install_help" ]; then
        local line
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                print_status "$line"
            else
                echo ""
            fi
        done <<< "$install_help"
    fi
}

is_oh_my_zsh_git_checkout() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    git -C "$install_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

has_oh_my_zsh_commit_history() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    git -C "$install_dir" rev-parse --verify HEAD >/dev/null 2>&1
}

has_oh_my_zsh_origin_remote() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    [ -n "$(git -C "$install_dir" config --get remote.origin.url 2>/dev/null)" ]
}

check_oh_my_zsh_ready() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    if [ ! -d "$install_dir" ]; then
        local not_installed_msg
        not_installed_msg=$(get_config "messages.not_installed")
        not_installed_msg="${not_installed_msg/\{path\}/$install_dir}"
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_status "$not_installed_msg"

        show_oh_my_zsh_install_help
        return 2
    fi

    if ! is_oh_my_zsh_git_checkout; then
        local not_git_msg
        not_git_msg=$(get_config "messages.not_git_repo")
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$not_git_msg"
        show_oh_my_zsh_install_help
        return 3
    fi

    if ! has_oh_my_zsh_commit_history; then
        local empty_repo_msg
        empty_repo_msg=$(get_config "messages.empty_git_repo")
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$empty_repo_msg"
        show_oh_my_zsh_install_help
        return 3
    fi

    if ! has_oh_my_zsh_origin_remote; then
        local missing_remote_msg
        missing_remote_msg=$(get_config "messages.missing_git_remote")
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$missing_remote_msg"
        show_oh_my_zsh_install_help
        return 3
    fi

    return 0
}

# Return a fixed 8-char commit prefix so it compares cleanly with the remote
# prefix in get_oh_my_zsh_remote_commit. `git rev-parse --short` picks a variable
# (often 7-char) length, which would never equal the 8-char remote prefix even at
# the same commit, causing a false "update available" every run.
get_oh_my_zsh_current_commit() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    local full_sha
    full_sha=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null) || return 1
    printf '%.8s\n' "$full_sha"
}

get_oh_my_zsh_remote_commit() {
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    local branch
    branch=$(get_config "update.branch")
    local remote_url
    remote_url=$(git -C "$install_dir" config --get remote.origin.url 2>/dev/null)

    if [ -z "$remote_url" ]; then
        local fetch_failed_msg
        fetch_failed_msg=$(get_config "messages.fetch_failed")
        print_error "$fetch_failed_msg" >&2
        return 1
    fi

    local remote_ref
    remote_ref=$(git ls-remote --heads "$remote_url" "$branch" 2>/dev/null | awk 'NR==1 {print $1}')
    if [ -z "$remote_ref" ]; then
        local fetch_failed_msg
        fetch_failed_msg=$(get_config "messages.fetch_failed")
        print_error "$fetch_failed_msg" >&2
        return 1
    fi

    printf '%.8s\n' "$remote_ref"
}

show_oh_my_zsh_installation_info() {
    if [ "${VERBOSE_MODE:-false}" != "true" ]; then
        return 0
    fi

    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)
    print_status "Oh My Zsh directory: $install_dir"
}

perform_oh_my_zsh_update() {
    local previous_commit="$1"
    local expected_remote_commit="$2"
    local install_dir
    install_dir=$(get_oh_my_zsh_install_dir)

    local branch
    branch=$(get_config "update.branch")

    local pulling_msg
    pulling_msg=$(get_config "messages.pulling_updates")
    print_status "$pulling_msg"

    if ! git -C "$install_dir" pull --ff-only origin "$branch"; then
        local pull_failed_msg
        pull_failed_msg=$(get_config "messages.pull_failed")
        print_error "$pull_failed_msg"
        return 1
    fi

    local new_commit
    new_commit=$(get_oh_my_zsh_current_commit)
    if [ -z "$new_commit" ]; then
        print_error "Failed to verify updated Oh My Zsh commit"
        return 1
    fi

    if [ -n "$previous_commit" ] && [ "$new_commit" = "$previous_commit" ]; then
        print_error "Oh My Zsh commit did not change after update"
        return 1
    fi

    local verified_remote_commit
    verified_remote_commit=$(get_oh_my_zsh_remote_commit)
    if [ -z "$verified_remote_commit" ]; then
        print_error "Failed to verify remote Oh My Zsh commit after update"
        return 1
    fi

    if [ "$new_commit" != "$verified_remote_commit" ]; then
        print_error "Oh My Zsh update did not reach the remote branch head"
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"

    local commit_msg
    commit_msg=$(get_config "messages.commit_info")
    commit_msg="${commit_msg/\{commit\}/$new_commit}"
    print_status "$commit_msg"

    if [ -n "$expected_remote_commit" ] && [ "$new_commit" != "$expected_remote_commit" ]; then
        print_status "Remote branch advanced during update; verified latest commit is now $new_commit"
    fi

    emit_summary_event "version_check" "target" "Oh My Zsh" "status" "up_to_date" "current_version" "$new_commit" "latest_version" "$verified_remote_commit"
    show_oh_my_zsh_installation_info
    return 0
}

oh_my_zsh_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"

    check_oh_my_zsh_ready
    local readiness_status=$?
    if [ "$readiness_status" -ne 0 ]; then
        return "$readiness_status"
    fi

    local current_commit
    current_commit=$(get_oh_my_zsh_current_commit)
    if [ -z "$current_commit" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_get_version")
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        return 1
    fi

    local remote_commit
    remote_commit=$(get_oh_my_zsh_remote_commit)
    if [ -z "$remote_commit" ]; then
        emit_summary_event "version_check" "target" "Oh My Zsh" "status" "unknown" "current_version" "$current_commit" "latest_version" "unknown"
        print_error "Failed to fetch remote commit information"
        return 1
    fi

    CURRENT_VERSION="$current_commit"
    LATEST_VERSION="$remote_commit"
    APP_DISPLAY_NAME="Oh My Zsh"

    local commit_msg
    commit_msg=$(get_config "messages.commit_info")
    commit_msg="${commit_msg/\{commit\}/$current_commit}"
    print_status "$commit_msg"

    local remote_msg
    remote_msg=$(get_config "messages.remote_commit_info")
    remote_msg="${remote_msg/\{commit\}/$remote_commit}"
    print_status "$remote_msg"

    if [ "$current_commit" = "$remote_commit" ]; then
        VERSION_STATUS=0
        local already_updated_msg
        already_updated_msg=$(get_config "messages.already_updated")
        print_success "$already_updated_msg"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "up_to_date" "current_version" "$current_commit" "latest_version" "$remote_commit"
    else
        VERSION_STATUS=2
        print_status "Oh My Zsh update available: $current_commit → $remote_commit"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$current_commit" "latest_version" "$remote_commit"
    fi

    return 0
}

update_oh_my_zsh() {
    oh_my_zsh_version_check
    local check_status=$?

    case "$check_status" in
        0)
            ;;
        2|3)
            ask_continue
            return 0
            ;;
        *)
            ask_continue
            return 0
            ;;
    esac

    if [ "$VERSION_STATUS" -eq 0 ]; then
        ask_continue
        return 0
    fi

    local updating_msg
    updating_msg=$(get_config "messages.updating")

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "print_status '$updating_msg' && perform_oh_my_zsh_update '$CURRENT_VERSION' '$LATEST_VERSION'"; then
        ask_continue
        return 1
    fi
}

update_oh_my_zsh
