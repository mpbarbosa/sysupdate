#!/bin/bash
#
# snap_manager.sh - Snap Package Manager Operations
# SNIPPET_ID: snap
# SNIPPET_NAME: Snap Package Manager
#
# Handles Snap package updates and management.
#
# Version: 0.4.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi

update_snap_packages() {
    if ! command -v snap &> /dev/null; then
        print_warning "📱 Snap package manager not installed - skipping Snap updates"
        print_status "🐧 Snap is primarily available on Ubuntu and Ubuntu-based distributions"
        print_status "💡 If you need Snap: install with 'sudo apt install snapd'"
        return 0
    fi
    
    print_operation_header "🔄 Initiating Snap package update process..."
    
    if ! snap list &> /dev/null; then
        print_warning "Snap daemon not accessible or no packages installed"
        print_status "Check if snapd service is running: 'systemctl status snapd'"
        return 0
    fi
    
    local snap_count=$(snap list | wc -l)
    if [ "$snap_count" -le 1 ]; then
        print_warning "No snap packages currently installed - skipping updates"
        print_status "Install snap packages with: 'snap install <package-name>'"
        emit_summary_event "snap_updates" "package_manager" "snap" "status" "up_to_date" "total_updates" "0"
        return 0
    fi
    
    print_status "Found $((snap_count - 1)) snap packages installed"
    
    if [ "$CHECK_ONLY_MODE" = true ]; then
        local pending_refreshes
        pending_refreshes=$(snap refresh --list 2>/dev/null | tail -n +2)
        local pending_count
        pending_count=$(echo "$pending_refreshes" | grep -c .)
        if [ "$pending_count" -eq 0 ]; then
            print_success "All Snap packages are up to date"
            emit_summary_event "snap_updates" "package_manager" "snap" "status" "up_to_date" "total_updates" "0"
        else
            print_status "Found $pending_count snap package(s) with pending refresh"
            emit_summary_event "snap_updates" "package_manager" "snap" "status" "update_available" "total_updates" "$pending_count"
        fi
    else
        print_status "Snap automatically updates in the background, but forcing refresh now..."
        
        if run_with_sudo snap refresh 2>&1 | grep -q "All snaps up to date"; then
            print_success "All Snap packages are up to date"
        else
            print_success "Snap packages refreshed successfully"
        fi
    fi
    
    ask_continue
}

update_snap_packages