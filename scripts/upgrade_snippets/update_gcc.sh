#!/bin/bash
#
# update_gcc.sh - GCC (C/C++ compiler) Update Manager
# SNIPPET_ID: gcc
# SNIPPET_NAME: GCC (gcc/g++, apt)
#
# Updates the system C and C++ compilers through apt, the channel they are
# installed from on Debian/Ubuntu. Tracks the `gcc` metapackage and upgrades
# `gcc` and `g++` together - they come from one source package (gcc-defaults)
# and always carry the same version. See gcc.yaml for the version-comparison
# rationale (apt package version on both sides, epoch and Debian revision
# stripped - never `gcc --version`).
# Reference: https://gcc.gnu.org/
#
# Version: 0.1.0-alpha
# Date: 2026-10-31
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-10-31) - Initial alpha version, apt-based

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/gcc.yaml"

# The upstream release apt records for a package, with the epoch and the Debian
# revision stripped: "4:15.2.0-5ubuntu1" -> "15.2.0".
#
# Both are apt bookkeeping rather than upstream version, and both have to go for
# the comparison to be sound: compare_versions only reaches dpkg's comparator
# for a plain dotted-numeric version and compares dotted components as text
# otherwise, which would put "4:9" above "4:10".
#
# The value comes from an external command, so it is returned only when it
# reduces to a dotted-numeric version - "(none)", for a package dpkg knows but
# has not installed, is rejected rather than compared.
# Usage: gcc_apt_version <package> <Installed|Candidate>
gcc_apt_version() {
    local package="$1"
    local field="$2"

    local version
    version=$(apt-cache policy "$package" 2>/dev/null \
        | awk -v want="${field}:" '$1 == want { print $2; exit }' \
        | sed -E 's/^[0-9]+://; s/-[^-]*$//')

    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1

    printf '%s\n' "$version"
}

# True when apt is available to answer for the toolchain at all. On a non-apt
# system gcc is usually present but managed by another package manager, so this
# is a skip (warning + event), not a failure.
gcc_apt_is_available() {
    if command -v apt-cache &> /dev/null && command -v apt-get &> /dev/null; then
        return 0
    fi

    print_warning "$(get_config "messages.unsupported_platform")"
    emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unsupported_platform" "current_version" "unknown" "latest_version" "unknown"
    return 1
}

# The three-part release a compiler driver reports for itself, e.g. "15.2.0".
# -dumpfullversion only exists from GCC 7 on; before that -dumpversion carried
# the full release, so try both before giving up.
# Usage: compiler_release gcc|g++
compiler_release() {
    "$1" -dumpfullversion 2>/dev/null \
        || "$1" -dumpversion 2>/dev/null \
        || echo "unknown"
}

# Report which compilers the metapackage version actually resolves to.
#
# The `gcc` package version says which gcc-N is the default, not what is on the
# system: several gcc-N/g++-N can be installed side by side, and C++ is the half
# of the toolchain that can be missing entirely - a system can carry gcc with no
# g++ at all, which the metapackage version alone would never reveal.
report_active_compilers() {
    local cc_path cxx_path

    cc_path=$(readlink -f "$(command -v gcc)" 2>/dev/null)
    print_status "Active gcc: $(compiler_release gcc) (${cc_path:-unknown})"

    if ! command -v g++ &> /dev/null; then
        print_warning "$(get_config "messages.missing_cxx")"
        return 0
    fi

    cxx_path=$(readlink -f "$(command -v g++)" 2>/dev/null)
    print_status "Active g++: $(compiler_release g++) (${cxx_path:-unknown})"
}

perform_gcc_update() {
    local update_cmd
    update_cmd=$(get_config "update.update_command")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local installing_msg
    installing_msg=$(get_config "messages.installing")

    print_status "$installing_msg"

    local update_output
    if ! update_output=$(eval "$update_cmd" 2>&1); then
        [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"
        print_error "Failed to update $APP_DISPLAY_NAME"
        return 1
    fi

    [ -n "$update_output" ] && echo "$update_output" | tail -"${output_lines:-20}"

    # apt can exit 0 without advancing the version (already latest, held, or
    # kept back by an unmet dependency). Verify the installed metapackage
    # actually reached the candidate; prints "Verified version: X", emits the
    # summary event, and reports an honest failure if it did not move.
    if ! verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"; then
        return 1
    fi

    report_active_compilers
}

update_gcc() {
    APP_DISPLAY_NAME=$(get_config "application.display_name")
    [ -n "$APP_DISPLAY_NAME" ] || APP_DISPLAY_NAME="GCC"

    print_operation_header "$(get_config "messages.checking_updates")"

    if ! gcc_apt_is_available; then
        ask_continue
        return 0
    fi

    # Emits the not_installed summary event and asks to continue on its own.
    if ! check_app_installed_or_help "$(get_config "application.command")" \
        "$APP_DISPLAY_NAME" "$(get_config "messages.install_help")"; then
        return 0
    fi

    CURRENT_VERSION=$(get_current_version_from_config)
    if [ -z "$CURRENT_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_version")"
        ask_continue
        return 1
    fi

    # Resolved here rather than through config_driven_version_check: that path's
    # get_apt_latest_version keeps the epoch, so only the current side would
    # have it stripped and every comparison would be against a different format.
    LATEST_VERSION=$(gcc_apt_version "$(get_config "version.package_name")" "Candidate")

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    report_active_compilers

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_gcc_update"; then
        ask_continue
        return 1
    fi
}

update_gcc
