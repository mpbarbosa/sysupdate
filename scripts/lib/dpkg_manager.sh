#!/bin/bash
#
# dpkg_manager.sh - DPKG Package Manager Operations
#
# Handles DPKG package maintenance and status checking operations.
#
# Version: 0.4.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

# Source core library if not already sourced
if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi

maintain_dpkg_packages() {
    print_operation_header "Maintaining DPKG packages..."
    
    local dpkg_list="/var/lib/dpkg/status"
    if [ ! -f "$dpkg_list" ]; then
        print_warning "DPKG status file not found"
        return 1
    fi
    
    local package_count=$(grep -c "^Package:" "$dpkg_list" 2>/dev/null)
    print_status "Total DPKG packages tracked: $package_count"
    
    local broken_count=$(dpkg -l | grep -c '^.H' 2>/dev/null)
    broken_count=${broken_count:-0}
    if [ "$broken_count" -gt 0 ]; then
        print_warning "Found $broken_count packages in broken state"
        print_status "Run: sudo apt-get install -f"
    else
        print_success "All DPKG packages are properly installed"
    fi
    
    ask_continue
}
