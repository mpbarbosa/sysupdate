#!/bin/bash
#
# pip_manager.sh - Python pip Package Manager Operations
# SNIPPET_ID: pip
# SNIPPET_NAME: Python pip Package Manager
#
# Handles Python package updates via pip.
#
# Version: 0.5.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi

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
    local outdated=$(pip3 list --outdated --user 2>/dev/null | tail -n +3)
    if [ -z "$outdated" ]; then
        print_success "All user pip packages are up to date"
        emit_summary_event "pip_updates" "package_manager" "pip" "status" "up_to_date" "total_updates" "0"
    else
        print_status "Found outdated user packages:"
        echo "$outdated" | head -10
        local outdated_count
        outdated_count=$(echo "$outdated" | wc -l)
        emit_summary_event "pip_updates" "package_manager" "pip" "status" "update_available" "total_updates" "$outdated_count"
        
        if [ "$CHECK_ONLY_MODE" = true ]; then
                print_status "Check-only mode - skipping pip update action"
        elif [ "$QUIET_MODE" = false ]; then
                if prompt_yes_no "Update all outdated pip packages?" "N"; then
                        print_status "Updating pip packages..."
                        
                        local success_count=0
                        local fail_count=0
                        local total_packages=$(echo "$outdated" | wc -l)
                        local failed_packages=""
                        
                        # Use process substitution to preserve variables in parent shell
                        while read -r package; do
                            if [ -n "$package" ]; then
                                print_status "📦 Updating $package..."
                                if pip3 install -U "$package" --user 2>&1 | grep -q "Successfully installed\|Requirement already satisfied"; then
                                    success_count=$((success_count + 1))
                                    print_success "✅ $package updated successfully"
                                else
                                    fail_count=$((fail_count + 1))
                                    failed_packages="${failed_packages}${package} "
                                    print_warning "⚠️  Failed to update $package (skipping)"
                                fi
                            fi
                        done < <(echo "$outdated" | awk '{print $1}')
                        
                        echo ""
                        print_status "📊 Update Summary: $success_count succeeded, $fail_count failed out of $total_packages packages"
                        
                        # Verify installed packages are properly installed
                        if [ $success_count -gt 0 ]; then
                            print_status "🔍 Verifying installed packages..."
                            local verification_failed=0
                            
                            while read -r package; do
                                if [ -n "$package" ]; then
                                    # Skip packages that failed to install
                                    if echo "$failed_packages" | grep -qw "$package"; then
                                        continue
                                    fi
                                    
                                    # Check if package can be imported or shown
                                    if ! pip3 show "$package" &>/dev/null; then
                                        print_warning "⚠️  Package $package is not properly installed"
                                        verification_failed=$((verification_failed + 1))
                                    fi
                                fi
                            done < <(echo "$user_packages" | awk '{print $1}')
                            
                            if [ $verification_failed -eq 0 ]; then
                                print_success "✅ All updated packages verified successfully"
                            else
                                print_warning "⚠️  $verification_failed package(s) failed verification"
                            fi
                        fi
                        
                        echo ""
                        if [ $fail_count -eq 0 ]; then
                            print_success "✅ All pip packages updated successfully"
                        else
                            print_warning "⚠️  $fail_count package(s) failed to update (possibly due to missing build dependencies)"
                            print_status "💡 Failed packages may require system dependencies: sudo apt install python3-dev build-essential"
                        fi
                else
                    print_status "Skipping pip package updates"
                fi
            else
                print_status "Quiet mode - skipping interactive pip updates"
            fi
    fi
    
    ask_continue
}

update_pip_packages