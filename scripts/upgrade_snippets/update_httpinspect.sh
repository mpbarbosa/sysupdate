#!/bin/bash
#
# update_httpinspect.sh - httpinspect Update Manager
# SNIPPET_ID: httpinspect
# SNIPPET_NAME: httpinspect (live HTTP traffic inspector)
#
# Handles version checking and updates for httpinspect, an eBPF + JavaScript
# source app run through the `yeet` runtime (`yeet run .`). Upstream ships no
# binaries, releases, or tags, so the local git commit is the "version" and the
# update is a fast-forward `git pull` followed by a `make` rebuild of the eBPF
# object and JS bundle.
#
# Reference: https://github.com/yeet-src/httpinspect
#
# Version: 0.1.0-alpha
# Date: 2026-06-24
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-24) - Initial alpha version
#                            - Git commit-based update detection
#                            - Fast-forward git pull + `make` rebuild
#                            - Locates the checkout via $HTTPINSPECT_DIR (default
#                              ~/.local/share/httpinspect)
#

HTTPINSPECT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTTPINSPECT_LIB_DIR="$(cd "$HTTPINSPECT_SCRIPT_DIR/../lib" && pwd)"
source "$HTTPINSPECT_LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$HTTPINSPECT_SCRIPT_DIR/httpinspect.yaml"

# Minimum kernel for the TCX traffic-control attach point httpinspect's eBPF
# program uses (landed in Linux 6.6). Plain (not readonly) so re-sourcing the
# snippet never trips a "readonly variable" error.
HTTPINSPECT_MIN_KERNEL="6.6"
# Location of the kernel BTF blob (CO-RE metadata). Overridable so the preflight
# can be exercised in tests without a real /sys mount.
HTTPINSPECT_BTF_PATH="${HTTPINSPECT_BTF_PATH:-/sys/kernel/btf/vmlinux}"

# Verify the host kernel can actually load and attach httpinspect's eBPF program
# before we bother pulling/rebuilding source that could not run here:
#   * kernel >= 6.6     -> the TCX eBPF attach point
#   * BTF present       -> CO-RE relocation (/sys/kernel/btf/vmlinux)
# Emits a warning + an "unsupported_platform" summary event when a requirement is
# unmet. Returns 0 when supported (or bypassed via HTTPINSPECT_SKIP_KERNEL_CHECK=1),
# 1 otherwise.
check_httpinspect_kernel_support() {
    if [ "${HTTPINSPECT_SKIP_KERNEL_CHECK:-}" = "1" ]; then
        return 0
    fi

    local unmet=0
    local min_major=6 min_minor=6

    # Parse major.minor from `uname -r` (e.g. "7.0.0-27-generic" -> 7, 0).
    local kernel_release major minor rest
    kernel_release=$(uname -r 2>/dev/null)
    major=${kernel_release%%.*}
    rest=${kernel_release#*.}
    minor=${rest%%.*}

    if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]]; then
        local unknown_msg
        unknown_msg=$(get_config "messages.unknown_kernel")
        unknown_msg=${unknown_msg//\{kernel\}/${kernel_release:-unknown}}
        unknown_msg=${unknown_msg//\{min_version\}/$HTTPINSPECT_MIN_KERNEL}
        print_warning "$unknown_msg"
        unmet=1
    elif [ "$major" -lt "$min_major" ] || { [ "$major" -eq "$min_major" ] && [ "$minor" -lt "$min_minor" ]; }; then
        local old_kernel_msg
        old_kernel_msg=$(get_config "messages.unsupported_kernel")
        old_kernel_msg=${old_kernel_msg//\{kernel\}/$kernel_release}
        old_kernel_msg=${old_kernel_msg//\{min_version\}/$HTTPINSPECT_MIN_KERNEL}
        print_warning "$old_kernel_msg"
        unmet=1
    fi

    # BTF is exposed at /sys/kernel/btf/vmlinux when the kernel is built with
    # CONFIG_DEBUG_INFO_BTF=y; without it CO-RE relocation cannot happen.
    if [ ! -r "$HTTPINSPECT_BTF_PATH" ]; then
        local btf_msg
        btf_msg=$(get_config "messages.missing_btf")
        btf_msg=${btf_msg//\{path\}/$HTTPINSPECT_BTF_PATH}
        print_warning "$btf_msg"
        unmet=1
    fi

    if [ "$unmet" -ne 0 ]; then
        local hint_msg
        hint_msg=$(get_config "messages.unsupported_platform_hint")
        [ -n "$hint_msg" ] && print_status "$hint_msg"
        emit_summary_event "version_check" "target" "httpinspect" "status" "unsupported_platform" "current_version" "unknown" "latest_version" "unknown"
        return 1
    fi

    return 0
}

# Resolve the checkout directory: $HTTPINSPECT_DIR wins, else the default.
get_httpinspect_install_dir() {
    if [ -n "${HTTPINSPECT_DIR:-}" ]; then
        echo "$HTTPINSPECT_DIR"
        return 0
    fi
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/httpinspect"
}

show_httpinspect_install_help() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)

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

is_httpinspect_git_checkout() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)
    git -C "$install_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

has_httpinspect_commit_history() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)
    git -C "$install_dir" rev-parse --verify HEAD >/dev/null 2>&1
}

has_httpinspect_origin_remote() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)
    [ -n "$(git -C "$install_dir" config --get remote.origin.url 2>/dev/null)" ]
}

check_httpinspect_ready() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)

    if [ ! -d "$install_dir" ]; then
        local not_installed_msg
        not_installed_msg=$(get_config "messages.not_installed")
        not_installed_msg="${not_installed_msg/\{path\}/$install_dir}"
        emit_summary_event "version_check" "target" "httpinspect" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_status "$not_installed_msg"
        show_httpinspect_install_help
        return 2
    fi

    if ! is_httpinspect_git_checkout; then
        local not_git_msg
        not_git_msg=$(get_config "messages.not_git_repo")
        emit_summary_event "version_check" "target" "httpinspect" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$not_git_msg"
        show_httpinspect_install_help
        return 3
    fi

    if ! has_httpinspect_commit_history; then
        local empty_repo_msg
        empty_repo_msg=$(get_config "messages.empty_git_repo")
        emit_summary_event "version_check" "target" "httpinspect" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$empty_repo_msg"
        show_httpinspect_install_help
        return 3
    fi

    if ! has_httpinspect_origin_remote; then
        local missing_remote_msg
        missing_remote_msg=$(get_config "messages.missing_git_remote")
        emit_summary_event "version_check" "target" "httpinspect" "status" "invalid_installation" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$missing_remote_msg"
        show_httpinspect_install_help
        return 3
    fi

    return 0
}

# Return a fixed 8-char commit prefix so it compares cleanly with the remote
# prefix below. `git rev-parse --short` picks a variable (often 7-char) length,
# which would never equal the 8-char remote prefix even at the same commit.
get_httpinspect_current_commit() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)
    local full_sha
    full_sha=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null) || return 1
    printf '%.8s\n' "$full_sha"
}

get_httpinspect_remote_commit() {
    local install_dir
    install_dir=$(get_httpinspect_install_dir)

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

# Rebuild the eBPF object + JS bundle after pulling. The Makefile fetches its
# own deps, so a system C toolchain is not required. Returns non-zero on failure
# but does not roll back the pull; the working tree is left at the new commit.
rebuild_httpinspect() {
    local install_dir="$1"

    local rebuild_command
    rebuild_command=$(get_config "update.rebuild_command")
    if [ -z "$rebuild_command" ]; then
        return 0
    fi

    local rebuilding_msg
    rebuilding_msg=$(get_config "messages.rebuilding")
    print_status "$rebuilding_msg"

    local output_lines
    output_lines=$(get_config "update.output_lines")

    local rebuild_output
    rebuild_output=$(cd "$install_dir" && eval "$rebuild_command" 2>&1)
    local rebuild_exit_code=$?
    emit_captured_output "$rebuild_output" "$output_lines"

    if [ "$rebuild_exit_code" -ne 0 ]; then
        local rebuild_failed_msg
        rebuild_failed_msg=$(get_config "messages.rebuild_failed")
        rebuild_failed_msg="${rebuild_failed_msg/\{path\}/$install_dir}"
        print_error "$rebuild_failed_msg"
        return 1
    fi

    return 0
}

perform_httpinspect_update() {
    local previous_commit="$1"
    local expected_remote_commit="$2"
    local install_dir
    install_dir=$(get_httpinspect_install_dir)

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
    new_commit=$(get_httpinspect_current_commit)
    if [ -z "$new_commit" ]; then
        print_error "Failed to verify updated httpinspect commit"
        return 1
    fi

    if [ -n "$previous_commit" ] && [ "$new_commit" = "$previous_commit" ]; then
        print_error "httpinspect commit did not change after update"
        return 1
    fi

    local verified_remote_commit
    verified_remote_commit=$(get_httpinspect_remote_commit)
    if [ -z "$verified_remote_commit" ]; then
        print_error "Failed to verify remote httpinspect commit after update"
        return 1
    fi

    if [ "$new_commit" != "$verified_remote_commit" ]; then
        print_error "httpinspect update did not reach the remote branch head"
        return 1
    fi

    # Rebuild the eBPF object + JS bundle so the new commit is actually runnable.
    if ! rebuild_httpinspect "$install_dir"; then
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

    emit_summary_event "version_check" "target" "httpinspect" "status" "up_to_date" "current_version" "$new_commit" "latest_version" "$verified_remote_commit"
    return 0
}

httpinspect_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"

    # Gate on kernel/BTF support before touching install state or the network:
    # pulling + rebuilding source that cannot load here is pointless.
    if ! check_httpinspect_kernel_support; then
        return 4
    fi

    check_httpinspect_ready
    local readiness_status=$?
    if [ "$readiness_status" -ne 0 ]; then
        return "$readiness_status"
    fi

    local current_commit
    current_commit=$(get_httpinspect_current_commit)
    if [ -z "$current_commit" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_get_version")
        emit_summary_event "version_check" "target" "httpinspect" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        return 1
    fi

    local remote_commit
    remote_commit=$(get_httpinspect_remote_commit)
    if [ -z "$remote_commit" ]; then
        emit_summary_event "version_check" "target" "httpinspect" "status" "unknown" "current_version" "$current_commit" "latest_version" "unknown"
        print_error "Failed to fetch remote commit information"
        return 1
    fi

    CURRENT_VERSION="$current_commit"
    LATEST_VERSION="$remote_commit"
    APP_DISPLAY_NAME="httpinspect"

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
        print_status "httpinspect update available: $current_commit → $remote_commit"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$current_commit" "latest_version" "$remote_commit"
    fi

    return 0
}

update_httpinspect() {
    httpinspect_version_check
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
        "print_status '$updating_msg' && perform_httpinspect_update '$CURRENT_VERSION' '$LATEST_VERSION'"; then
        ask_continue
        return 1
    fi
}

update_httpinspect
