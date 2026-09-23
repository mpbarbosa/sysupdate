#!/bin/bash
#
# pip_manager.sh - Python pip Package Manager Operations
# SNIPPET_ID: pip
# SNIPPET_NAME: Python pip Package Manager
#
# Handles Python package updates via pip.
#
# Scope: user-site packages only. Both the `pip3 list --outdated --user`
# inventory and the `pip3 install --user` upgrade address
# ~/.local/lib/pythonX.Y/site-packages; the distro's dist-packages tree is
# never written to.
#
# Version: 0.6.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

# upgrade_utils.sh carries the PEP 668 probes and the pip output classifier
# (pip_environment_is_externally_managed, pip_supports_break_system_packages,
# pip_failure_reason) plus get_remediation. It sources core_lib.sh itself.
PIP_MANAGER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$PIP_MANAGER_SCRIPT_DIR/../lib" && pwd)/upgrade_utils.sh"

CONFIG_FILE="$PIP_MANAGER_SCRIPT_DIR/pip.yaml"

# Fallback when pip.yaml is unreadable or yq is missing.
PIP_EXTERNALLY_MANAGED_FALLBACK_REMEDIATION="This Python is externally managed (PEP 668) and pip is too old for --break-system-packages — upgrade pip itself, or move these packages into a venv or pipx."

update_pip_packages() {
    if ! command -v pip3 &> /dev/null; then
        print_warning "Python pip3 not installed - skipping pip updates"
        print_status "Install pip: sudo apt install python3-pip"
        return 0
    fi

    print_operation_header "Updating Python pip packages..."
    print_status "Checking for outdated packages..."

    # Check only user-installed packages (--user flag)
    # This avoids conflicts with system packages managed by apt
    local outdated
    outdated=$(pip3 list --outdated --user 2>/dev/null | tail -n +3)
    if [ -z "$outdated" ]; then
        print_success "All user pip packages are up to date"
        emit_summary_event "pip_updates" "package_manager" "pip" "status" "up_to_date" "total_updates" "0"
        ask_continue
        return 0
    fi

    print_status "Found outdated user packages:"
    echo "$outdated" | head -10
    local outdated_count
    outdated_count=$(echo "$outdated" | wc -l)

    # PEP 668: on Debian-derived systems the stdlib carries an
    # EXTERNALLY-MANAGED marker and *every* install — including --user, which
    # only ever writes to ~/.local — is refused unless
    # --break-system-packages is passed. Decide this once, up front, so the
    # run either upgrades for real or reports honestly that it cannot,
    # instead of failing every package one at a time.
    local install_args=(--user)
    if pip_environment_is_externally_managed; then
        if pip_supports_break_system_packages pip3; then
            install_args+=(--break-system-packages)
            print_status "PEP 668: interpreter is externally managed — adding --break-system-packages"
            print_status "   Writes stay in the user site (~/.local); the distro's dist-packages tree is untouched"
        else
            local remediation
            remediation=$(get_remediation "externally_managed" "")
            [ -z "$remediation" ] && remediation="$PIP_EXTERNALLY_MANAGED_FALLBACK_REMEDIATION"

            print_warning "Cannot upgrade user pip packages on this host"
            print_status "$remediation"
            emit_summary_event "pip_updates" "package_manager" "pip" "status" "externally_managed" \
                "total_updates" "$outdated_count" "remediation" "$remediation"
            ask_continue
            return 0
        fi
    fi

    emit_summary_event "pip_updates" "package_manager" "pip" "status" "update_available" "total_updates" "$outdated_count"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - skipping pip update action"
        ask_continue
        return 0
    fi

    if [ "$QUIET_MODE" != false ]; then
        print_status "Quiet mode - skipping interactive pip updates"
        ask_continue
        return 0
    fi

    if ! prompt_yes_no "Update all outdated pip packages?" "N"; then
        print_status "Skipping pip package updates"
        ask_continue
        return 0
    fi

    print_status "Updating pip packages..."

    local success_count=0
    local fail_count=0
    local total_packages="$outdated_count"
    local updated_packages=""

    # Track the distinct causes seen, so the closing advice describes what
    # actually went wrong rather than guessing at build dependencies.
    local saw_build_failure=false

    # Use process substitution to preserve variables in parent shell
    while read -r package; do
        if [ -n "$package" ]; then
            print_status "📦 Updating $package..."
            local pip_output
            # Exit status, not a grep for "Successfully installed": pip is
            # authoritative about its own result, and the captured output is
            # what makes an accurate failure reason possible below.
            if pip_output=$(pip3 install -U "$package" "${install_args[@]}" 2>&1); then
                success_count=$((success_count + 1))
                updated_packages="${updated_packages}${package} "
                print_success "✅ $package updated successfully"
            else
                fail_count=$((fail_count + 1))
                local reason
                reason=$(pip_failure_reason "$pip_output")
                case "$reason" in
                    'build failed'*) saw_build_failure=true ;;
                esac
                print_warning "⚠️  Failed to update $package — $reason"
            fi
        fi
    done < <(echo "$outdated" | awk '{print $1}')

    echo ""
    print_status "📊 Update Summary: $success_count succeeded, $fail_count failed out of $total_packages packages"

    # Verify the packages that reported success are actually importable by pip
    if [ "$success_count" -gt 0 ]; then
        print_status "🔍 Verifying installed packages..."
        local verification_failed=0

        for package in $updated_packages; do
            if ! pip3 show "$package" &>/dev/null; then
                print_warning "⚠️  Package $package is not properly installed"
                verification_failed=$((verification_failed + 1))
            fi
        done

        if [ "$verification_failed" -eq 0 ]; then
            print_success "✅ All updated packages verified successfully"
        else
            print_warning "⚠️  $verification_failed package(s) failed verification"
        fi
    fi

    echo ""
    if [ "$fail_count" -eq 0 ]; then
        print_success "✅ All pip packages updated successfully"
    else
        print_warning "⚠️  $fail_count package(s) failed to update — see the reason next to each package above"
        # Only offer the build-toolchain hint when something actually failed to
        # compile. Printing it for a PEP 668 refusal sent users to install
        # python3-dev for a problem no compiler could have solved.
        if [ "$saw_build_failure" = true ]; then
            print_status "💡 Packages that failed to build need: sudo apt install python3-dev build-essential"
        fi
    fi

    ask_continue
}

update_pip_packages
