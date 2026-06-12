#!/bin/bash
#
# update_kotlin.sh - Kotlin Update Manager
# SNIPPET_ID: kotlin
# SNIPPET_NAME: Kotlin Compiler
#
# Installs or upgrades the newest Kotlin package available via apt and
# switches the active Kotlin alternatives to the updated version.
#
# Version: 0.1.0-alpha
# Date: 2026-05-10
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-10) - Initial version
#                            - Installs/upgrades Kotlin via apt
#                            - Activates kotlin/kotlinc with update-alternatives
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
source "$LIB_DIR/upgrade_utils.sh"

normalize_apt_version() {
    local version="$1"

    echo "$version" | sed -E 's/^[0-9]+://; s/[+~-].*$//'
}

extract_kotlin_version() {
    local raw_output="$1"

    echo "$raw_output" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

get_current_kotlin_version() {
    local output=""
    local version=""

    if command -v kotlinc &>/dev/null; then
        output=$(kotlinc -version 2>&1 | head -1)
        version=$(extract_kotlin_version "$output")
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi

    if command -v kotlin &>/dev/null; then
        output=$(kotlin -version 2>&1 | head -1)
        version=$(extract_kotlin_version "$output")
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi

    echo ""
}

get_candidate_kotlin_version() {
    local candidate

    candidate=$(apt-cache policy kotlin 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
        echo ""
        return 1
    fi

    normalize_apt_version "$candidate"
}

get_kotlin_home_from_package() {
    local kotlin_home

    kotlin_home=$(dpkg -L kotlin 2>/dev/null | awk '
        /^\/usr\/bin\// {next}
        /\/bin\/kotlinc$/ {
            sub(/\/bin\/kotlinc$/, "", $0)
            print
            exit
        }
    ')

    if [ -n "$kotlin_home" ]; then
        echo "$kotlin_home"
        return 0
    fi

    dpkg -L kotlin 2>/dev/null | awk '
        /^\/usr\/bin\// {next}
        /\/bin\/kotlin$/ {
            sub(/\/bin\/kotlin$/, "", $0)
            print
            exit
        }
    '
}

get_fallback_kotlin_home() {
    local kotlin_path

    kotlin_path=$(update-alternatives --list kotlinc 2>/dev/null | sort -V | tail -1)
    if [ -n "$kotlin_path" ]; then
        echo "${kotlin_path%/bin/kotlinc}"
        return 0
    fi

    if command -v kotlinc &>/dev/null; then
        kotlin_path=$(readlink -f "$(command -v kotlinc)")
        echo "${kotlin_path%/bin/kotlinc}"
        return 0
    fi

    echo ""
}

ensure_alternative_registered() {
    local name="$1"
    local candidate="$2"
    local link_path="/usr/bin/$name"

    if update-alternatives --list "$name" >/dev/null 2>&1; then
        if update-alternatives --list "$name" 2>/dev/null | grep -Fxq "$candidate"; then
            return 0
        fi
    fi

    sudo update-alternatives --install "$link_path" "$name" "$candidate" 100 >/dev/null
}

set_alternative_if_available() {
    local name="$1"
    local kotlin_home="$2"
    local candidate="$kotlin_home/bin/$name"

    if [ ! -x "$candidate" ]; then
        return 1
    fi

    if ! ensure_alternative_registered "$name" "$candidate"; then
        return 1
    fi

    sudo update-alternatives --set "$name" "$candidate" >/dev/null
}

activate_kotlin_alternatives() {
    local kotlin_home="$1"
    local updated_count=0
    local tool_name
    local tools=(kotlin kotlinc kapt kotlin-dce-js)

    for tool_name in "${tools[@]}"; do
        if set_alternative_if_available "$tool_name" "$kotlin_home"; then
            print_status "Activated $tool_name from $kotlin_home"
            updated_count=$((updated_count + 1))
        fi
    done

    if [ "$updated_count" -eq 0 ]; then
        print_error "No Kotlin alternatives were updated for $kotlin_home"
        return 1
    fi

    print_success "Updated $updated_count Kotlin alternative(s)"
    return 0
}

show_active_kotlin_summary() {
    if command -v kotlin &>/dev/null; then
        print_status "Active kotlin: $(readlink -f "$(command -v kotlin)")"
        print_status "kotlin version: $(kotlin -version 2>&1 | head -1)"
    fi

    if command -v kotlinc &>/dev/null; then
        print_status "Active kotlinc: $(readlink -f "$(command -v kotlinc)")"
        print_status "kotlinc version: $(kotlinc -version 2>&1 | head -1)"
    fi
}

update_kotlin() {
    print_operation_header "Checking for Kotlin updates..."

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

    local current_version=""
    local latest_version=""
    local version_status=2

    current_version=$(get_current_kotlin_version)
    latest_version=$(get_candidate_kotlin_version)

    if [ -z "$latest_version" ]; then
        print_error "Failed to find the Kotlin package in apt repositories"
        ask_continue
        return 1
    fi

    if [ -n "$current_version" ]; then
        compare_and_report_versions "$current_version" "$latest_version" "Kotlin"
        version_status=$?

        if [ "$version_status" -ne 2 ]; then
            ask_continue
            return 0
        fi
    else
        print_warning "Kotlin is not currently installed. Latest available version: ${latest_version}"
    fi

    if ! prompt_yes_no "Install or upgrade Kotlin and activate it?"; then
        print_status "Skipping Kotlin update"
        ask_continue
        return 0
    fi

    print_status "Refreshing apt metadata..."
    if ! sudo apt-get update; then
        print_error "Failed to refresh apt package lists"
        ask_continue
        return 1
    fi

    print_status "Installing/upgrading Kotlin..."
    if ! sudo apt-get install -y kotlin; then
        print_error "Failed to install or upgrade Kotlin"
        ask_continue
        return 1
    fi

    local kotlin_home
    kotlin_home=$(get_kotlin_home_from_package)
    if [ -z "$kotlin_home" ]; then
        kotlin_home=$(get_fallback_kotlin_home)
    fi

    if [ -z "$kotlin_home" ] || [ ! -d "$kotlin_home" ]; then
        print_error "Failed to determine the installed Kotlin home directory"
        ask_continue
        return 1
    fi

    if ! activate_kotlin_alternatives "$kotlin_home"; then
        ask_continue
        return 1
    fi

    print_success "Kotlin updated and activated from $kotlin_home"
    show_active_kotlin_summary
    ask_continue
    return 0
}

update_kotlin
