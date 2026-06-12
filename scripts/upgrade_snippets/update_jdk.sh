#!/bin/bash
#
# update_jdk.sh - OpenJDK Update Manager
# SNIPPET_ID: jdk
# SNIPPET_NAME: Java Development Kit (JDK)
#
# Installs or upgrades the newest OpenJDK package available via apt and
# switches the active Java alternatives to the updated JDK.
#
# Version: 0.1.1-alpha
# Date: 2026-05-10
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.1-alpha (2026-05-10) - Fixes JDK activation when apt metadata points to
#                            - a metapackage directory instead of bin/java paths
#                            - Selects the highest Java version from alternatives
#   0.1.0-alpha (2026-05-10) - Initial version
#                            - Detects latest OpenJDK apt package
#                            - Installs/upgrades via apt
#                            - Updates java/javac and related alternatives
#
# Dependencies:
#   - apt-cache / apt-get
#   - dpkg
#   - update-alternatives
#

set -u
set -o pipefail

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
# shellcheck source=../lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$LIB_DIR/upgrade_utils.sh"

normalize_apt_version() {
    local version="$1"

    echo "$version" | sed -E 's/^[0-9]+://; s/[+~-].*$//'
}

compare_jdk_versions() {
    local current_version="$1"
    local latest_version="$2"
    local normalized_current
    local normalized_latest

    normalized_current=$(normalize_apt_version "$current_version")
    normalized_latest=$(normalize_apt_version "$latest_version")

    compare_versions "$normalized_current" "$normalized_latest"
}

report_jdk_version_status() {
    local current_version="$1"
    local latest_version="$2"

    print_status "Current version: $current_version"
    print_status "Latest version: $latest_version"

    if [ -z "$latest_version" ]; then
        print_error "Failed to fetch latest version"
        return 1
    fi

    compare_jdk_versions "$current_version" "$latest_version"
    local cmp_result=$?

    if [ "$cmp_result" -eq 2 ]; then
        print_warning "OpenJDK update available: $current_version → $latest_version"
        return 2
    elif [ "$cmp_result" -eq 1 ]; then
        print_status "OpenJDK version is newer than latest release"
        return 1
    fi

    print_success "OpenJDK is up to date"
    return 0
}

get_current_jdk_version() {
    if command -v javac &>/dev/null; then
        javac --version 2>/dev/null | awk '{print $2}'
        return 0
    fi

    if command -v java &>/dev/null; then
        java --version 2>/dev/null | head -1 | sed -nE 's/.* ([0-9]+(\.[0-9]+)+).*/\1/p'
        return 0
    fi

    echo ""
}

find_latest_jdk_package() {
    apt-cache search --names-only '^openjdk-[0-9]+-jdk$' 2>/dev/null | \
        awk '{print $1}' | \
        sort -t- -k2,2n | \
        tail -1
}

get_candidate_jdk_version() {
    local package_name="$1"
    local candidate

    candidate=$(apt-cache policy "$package_name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    normalize_apt_version "$candidate"
}

is_valid_jdk_dir() {
    local jdk_dir="$1"

    [ -n "$jdk_dir" ] || return 1
    [ -d "$jdk_dir" ] || return 1
    [ -x "$jdk_dir/bin/java" ] || [ -x "$jdk_dir/bin/javac" ] || \
        [ -x "$jdk_dir/jre/bin/java" ] || [ -x "$jdk_dir/jre/bin/javac" ]
}

extract_jdk_dir_from_path() {
    local candidate_path="$1"

    case "$candidate_path" in
        */bin/java|*/bin/javac|*/jre/bin/java|*/jre/bin/javac)
            echo "${candidate_path%/bin/*}"
            ;;
        *)
            echo "$candidate_path" | sed -nE 's#(.*/usr/lib/jvm/[^/]+).*#\1#p'
            ;;
    esac
}

extract_jdk_version_from_dir() {
    local jdk_dir="$1"

    echo "$jdk_dir" | sed -nE 's#^.*/(java-|jdk-)([0-9]+(\.[0-9]+)*).*#\2#p'
}

get_jdk_dir_from_package() {
    local package_name="$1"
    local jdk_dir

    jdk_dir=$(dpkg -L "$package_name" 2>/dev/null | awk '
        /\/bin\/javac$/ {
            sub(/\/bin\/javac$/, "", $0)
            print
            exit
        }
    ')

    if [ -n "$jdk_dir" ]; then
        echo "$jdk_dir"
        return 0
    fi

    jdk_dir=$(dpkg -L "$package_name" 2>/dev/null | awk '
        /\/bin\/java$/ {
            sub(/\/bin\/java$/, "", $0)
            print
            exit
        }
    ')

    if [ -n "$jdk_dir" ]; then
        echo "$jdk_dir"
        return 0
    fi

    while IFS= read -r candidate_path; do
        [ -n "$candidate_path" ] || continue
        jdk_dir=$(extract_jdk_dir_from_path "$candidate_path")
        if is_valid_jdk_dir "$jdk_dir"; then
            echo "$jdk_dir"
            return 0
        fi
    done < <(
        dpkg -L "$package_name" 2>/dev/null | awk '
            match($0, /\/usr\/lib\/jvm\/[^\/]+/) {
                print substr($0, RSTART, RLENGTH)
            }
        ' | sort -u
    )

    echo ""
}

get_fallback_jdk_dir_from_alternatives() {
    local candidate_path=""
    local jdk_dir=""
    local best_dir=""
    local best_version=""
    local current_version=""
    local cmp_result=0

    while IFS= read -r candidate_path; do
        [ -n "$candidate_path" ] || continue

        jdk_dir=$(extract_jdk_dir_from_path "$candidate_path")
        if ! is_valid_jdk_dir "$jdk_dir"; then
            continue
        fi

        current_version=$(extract_jdk_version_from_dir "$jdk_dir")
        if [ -z "$best_dir" ]; then
            best_dir="$jdk_dir"
            best_version="$current_version"
            continue
        fi

        if [ -z "$best_version" ]; then
            if [ -n "$current_version" ]; then
                best_dir="$jdk_dir"
                best_version="$current_version"
            fi
            continue
        fi

        [ -n "$current_version" ] || continue

        compare_versions "$best_version" "$current_version"
        cmp_result=$?
        if [ "$cmp_result" -eq 2 ]; then
            best_dir="$jdk_dir"
            best_version="$current_version"
        fi
    done < <(
        {
            update-alternatives --list java 2>/dev/null || true
            update-alternatives --list javac 2>/dev/null || true
        } | sort -u
    )

    echo "$best_dir"
}

set_alternative_if_available() {
    local name="$1"
    local jdk_dir="$2"
    local candidate=""

    if [ -x "$jdk_dir/bin/$name" ]; then
        candidate="$jdk_dir/bin/$name"
    elif [ -x "$jdk_dir/jre/bin/$name" ]; then
        candidate="$jdk_dir/jre/bin/$name"
    else
        return 1
    fi

    if ! update-alternatives --list "$name" >/dev/null 2>&1; then
        return 1
    fi

    if ! update-alternatives --list "$name" 2>/dev/null | grep -Fxq "$candidate"; then
        return 1
    fi

    sudo update-alternatives --set "$name" "$candidate" >/dev/null
}

activate_jdk_alternatives() {
    local jdk_dir="$1"
    local updated_count=0
    local primary_tools=(java javac)
    local tool_name

    for tool_name in "${primary_tools[@]}"; do
        if set_alternative_if_available "$tool_name" "$jdk_dir"; then
            print_status "Activated $tool_name from $jdk_dir"
            updated_count=$((updated_count + 1))
        fi
    done

    while IFS= read -r tool_name; do
        [ -n "$tool_name" ] || continue

        case "$tool_name" in
            java|javac) continue ;;
        esac

        if set_alternative_if_available "$tool_name" "$jdk_dir"; then
            updated_count=$((updated_count + 1))
        fi
    done < <(
        update-alternatives --get-selections 2>/dev/null | \
            awk '$3 ~ /^\/usr\/lib\/jvm\// {print $1}' | \
            sort -u
    )

    if [ "$updated_count" -eq 0 ]; then
        print_error "No JDK alternatives were updated for $jdk_dir"
        return 1
    fi

    print_success "Updated $updated_count JDK alternative(s)"
    return 0
}

show_active_jdk_summary() {
    if command -v java &>/dev/null; then
        print_status "Active java: $(readlink -f "$(command -v java)")"
        print_status "java version: $(java --version 2>/dev/null | head -1)"
    fi

    if command -v javac &>/dev/null; then
        print_status "Active javac: $(readlink -f "$(command -v javac)")"
        print_status "javac version: $(javac --version 2>/dev/null)"
    fi
}

update_jdk() {
    print_operation_header "Checking for OpenJDK updates..."

    if ! command -v apt-cache &>/dev/null || ! command -v apt-get &>/dev/null; then
        print_error "This script currently supports apt-based systems only"
        ask_continue
        return 1
    fi

    if ! command -v update-alternatives &>/dev/null; then
        print_error "update-alternatives is required but was not found"
        ask_continue
        return 1
    fi

    local latest_package
    latest_package=$(find_latest_jdk_package)

    if [ -z "$latest_package" ]; then
        print_error "Failed to find an OpenJDK package in apt repositories"
        ask_continue
        return 1
    fi

    local current_version
    current_version=$(get_current_jdk_version)
    local latest_version
    latest_version=$(get_candidate_jdk_version "$latest_package")
    local version_status=2

    if [ -n "$current_version" ]; then
        report_jdk_version_status "$current_version" "$latest_version"
        version_status=$?

        if [ "$version_status" -ne 2 ]; then
            ask_continue
            return 0
        fi
    else
        print_warning "No active JDK detected. Latest available package: $latest_package (${latest_version:-unknown})"
    fi

    if ! prompt_yes_no "Install or upgrade $latest_package and activate it?"; then
        print_status "Skipping JDK update"
        ask_continue
        return 0
    fi

    print_status "Refreshing apt metadata..."
    if ! sudo apt-get update; then
        print_error "Failed to refresh apt package lists"
        ask_continue
        return 1
    fi

    print_status "Installing/upgrading $latest_package..."
    if ! sudo apt-get install -y "$latest_package"; then
        print_error "Failed to install or upgrade $latest_package"
        ask_continue
        return 1
    fi

    local jdk_dir
    jdk_dir=$(get_jdk_dir_from_package "$latest_package")
    if [ -z "$jdk_dir" ]; then
        jdk_dir=$(get_fallback_jdk_dir_from_alternatives)
    fi

    if [ -z "$jdk_dir" ] || [ ! -d "$jdk_dir" ]; then
        print_error "Failed to determine the installed JDK directory"
        ask_continue
        return 1
    fi

    if ! activate_jdk_alternatives "$jdk_dir"; then
        ask_continue
        return 1
    fi

    print_success "OpenJDK updated and activated from $jdk_dir"
    show_active_jdk_summary
    ask_continue
    return 0
}

update_jdk
