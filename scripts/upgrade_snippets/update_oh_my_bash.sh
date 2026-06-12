#!/bin/bash
#
# update_oh_my_bash.sh - Oh-My-Bash Update Manager
# SNIPPET_ID: oh-my-bash
# SNIPPET_NAME: Oh My Bash
#
# Handles version checking and updates for oh-my-bash framework.
# Reference: https://github.com/ohmybash/oh-my-bash
#
# Version: 1.1.0-alpha
# Date: 2025-11-29
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.1.0-alpha (2025-11-29) - Added installation prompt when oh-my-bash not installed
#   1.0.0-alpha (2025-11-27) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 3: Custom Update Logic
#                            - Git commit-based versioning
#                            - Git pull update mechanism
#
# Dependencies:
#   - git (version control)
#

OH_MY_BASH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OH_MY_BASH_LIB_DIR="$(cd "$OH_MY_BASH_SCRIPT_DIR/../lib" && pwd)"
source "$OH_MY_BASH_LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$OH_MY_BASH_SCRIPT_DIR/oh_my_bash.yaml"

get_oh_my_bash_display_name() {
    local display_name
    display_name=$(get_config "application.display_name")

    if [ -n "$display_name" ]; then
        echo "$display_name"
    else
        echo "Oh-My-Bash"
    fi
}

get_oh_my_bash_install_dir() {
    local configured_install_dir
    configured_install_dir=$(get_config "application.installation_dir")

    if [ -z "$configured_install_dir" ]; then
        echo "$HOME/.oh-my-bash"
        return 0
    fi

    case "$configured_install_dir" in
        "\${HOME}/"*)
            echo "${configured_install_dir//\$\{HOME\}/$HOME}"
            ;;
        "\$HOME/"*)
            echo "${configured_install_dir//\$HOME/$HOME}"
            ;;
        \~/*)
            echo "$HOME/${configured_install_dir#~/}"
            ;;
        *)
            echo "$configured_install_dir"
            ;;
    esac
}

show_oh_my_bash_install_help() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    local install_help
    install_help=$(get_config "messages.install_help")
    install_help="${install_help//\~\/.oh-my-bash/$install_dir}"

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

is_oh_my_bash_git_checkout() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    git -C "$install_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

has_oh_my_bash_commit_history() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    git -C "$install_dir" rev-parse --verify HEAD >/dev/null 2>&1
}

has_oh_my_bash_origin_remote() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    [ -n "$(git -C "$install_dir" config --get remote.origin.url 2>/dev/null)" ]
}

check_oh_my_bash_ready() {
    local app_display_name
    app_display_name=$(get_oh_my_bash_display_name)
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    if [ ! -d "$install_dir" ]; then
        local not_installed_msg
        not_installed_msg=$(get_config "messages.not_installed")
        not_installed_msg="${not_installed_msg/\{path\}/$install_dir}"
        emit_summary_event "version_check" "target" "$app_display_name" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_status "$not_installed_msg"
        show_oh_my_bash_install_help
        return 2
    fi

    if ! is_oh_my_bash_git_checkout; then
        local not_git_msg
        not_git_msg=$(get_config "messages.not_git_repo")
        emit_summary_event "version_check" "target" "$app_display_name" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$not_git_msg"
        show_oh_my_bash_install_help
        return 3
    fi

    if ! has_oh_my_bash_commit_history; then
        local empty_repo_msg
        empty_repo_msg=$(get_config "messages.empty_git_repo")
        emit_summary_event "version_check" "target" "$app_display_name" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$empty_repo_msg"
        show_oh_my_bash_install_help
        return 3
    fi

    if ! has_oh_my_bash_origin_remote; then
        local missing_remote_msg
        missing_remote_msg=$(get_config "messages.missing_git_remote")
        emit_summary_event "version_check" "target" "$app_display_name" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$missing_remote_msg"
        show_oh_my_bash_install_help
        return 3
    fi

    return 0
}

get_current_commit() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)

    git -C "$install_dir" rev-parse --short=8 HEAD 2>/dev/null
}

get_remote_commit() {
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)
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

show_oh_my_bash_installation_info() {
    if [ "${VERBOSE_MODE:-false}" != "true" ]; then
        return 0
    fi

    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)
    print_status "oh-my-bash directory: $install_dir"
}

perform_oh_my_bash_update() {
    local previous_commit="$1"
    local expected_remote_commit="$2"
    local app_display_name
    app_display_name=$(get_oh_my_bash_display_name)
    local install_dir
    install_dir=$(get_oh_my_bash_install_dir)
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
    new_commit=$(get_current_commit)
    if [ -z "$new_commit" ]; then
        local verify_updated_failed_msg
        verify_updated_failed_msg=$(get_config "messages.verify_updated_failed")
        print_error "$verify_updated_failed_msg"
        return 1
    fi

    if [ -n "$previous_commit" ] && [ "$new_commit" = "$previous_commit" ]; then
        local update_no_change_msg
        update_no_change_msg=$(get_config "messages.update_no_change")
        print_error "$update_no_change_msg"
        return 1
    fi

    local verified_remote_commit
    verified_remote_commit=$(get_remote_commit)
    if [ -z "$verified_remote_commit" ]; then
        local verify_remote_failed_msg
        verify_remote_failed_msg=$(get_config "messages.verify_remote_failed")
        print_error "$verify_remote_failed_msg"
        return 1
    fi

    if [ "$new_commit" != "$verified_remote_commit" ]; then
        local update_not_at_remote_head_msg
        update_not_at_remote_head_msg=$(get_config "messages.update_not_at_remote_head")
        print_error "$update_not_at_remote_head_msg"
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
        local remote_advanced_msg
        remote_advanced_msg=$(get_config "messages.remote_advanced")
        remote_advanced_msg="${remote_advanced_msg/\{commit\}/$new_commit}"
        print_status "$remote_advanced_msg"
    fi

    emit_summary_event "version_check" "target" "$app_display_name" "status" "up_to_date" "current_version" "$new_commit" "latest_version" "$verified_remote_commit"
    show_oh_my_bash_installation_info
    return 0
}

oh_my_bash_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"

    check_oh_my_bash_ready
    local readiness_status=$?
    if [ "$readiness_status" -ne 0 ]; then
        return "$readiness_status"
    fi

    local current_commit
    current_commit=$(get_current_commit)
    if [ -z "$current_commit" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_get_version")
        emit_summary_event "version_check" "target" "$(get_oh_my_bash_display_name)" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        return 1
    fi

    local remote_commit
    remote_commit=$(get_remote_commit)
    if [ -z "$remote_commit" ]; then
        emit_summary_event "version_check" "target" "$(get_oh_my_bash_display_name)" "status" "unknown" "current_version" "$current_commit" "latest_version" "unknown"
        print_error "Failed to fetch remote commit information"
        return 1
    fi

    CURRENT_VERSION="$current_commit"
    LATEST_VERSION="$remote_commit"
    APP_DISPLAY_NAME=$(get_oh_my_bash_display_name)

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
        print_status "oh-my-bash update available: $current_commit → $remote_commit"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$current_commit" "latest_version" "$remote_commit"
    fi

    return 0
}

update_oh_my_bash() {
    oh_my_bash_version_check
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
        "print_status '$updating_msg' && perform_oh_my_bash_update '$CURRENT_VERSION' '$LATEST_VERSION'"; then
        ask_continue
        return 1
    fi
}

update_oh_my_bash
