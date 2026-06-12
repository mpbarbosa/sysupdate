#!/bin/bash
#
# npm_manager.sh - Node.js npm Package Manager Operations
# SNIPPET_ID: npm-packages
# SNIPPET_NAME: Node.js Global npm Packages
#
# Handles Node.js global package updates via npm.
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

update_npm_packages() {
    if ! command -v npm &> /dev/null; then
        print_warning "Node.js npm not installed - skipping npm updates"
        print_status "Install npm: sudo apt install nodejs npm"
        return 0
    fi
    
    print_operation_header "Updating Node.js npm packages..."
    print_status "Checking globally installed npm packages..."
    
    local outdated=$(npm outdated -g --depth=0 2>/dev/null)
    if [ -z "$outdated" ]; then
        print_success "All global npm packages are up to date"
        emit_summary_event "npm_updates" "package_manager" "npm" "status" "up_to_date" "total_updates" "0"
    else
        print_status "Found outdated global packages:"
        echo "$outdated"
        local outdated_count
        outdated_count=$(echo "$outdated" | tail -n +2 | grep -c .)
        emit_summary_event "npm_updates" "package_manager" "npm" "status" "update_available" "total_updates" "$outdated_count"
        
        if [ "$CHECK_ONLY_MODE" = true ]; then
            print_status "Check-only mode - skipping npm update action"
        elif [ "$QUIET_MODE" = false ]; then
            if prompt_yes_no "Update all global npm packages?" "N"; then
                print_status "Updating global npm packages..."
                npm update -g 2>&1 | head -30
                print_success "Global npm packages updated"
            else
                print_status "Skipping npm package updates"
            fi
        else
            print_status "Quiet mode - skipping interactive npm updates"
        fi
    fi
    
    ask_continue
}

update_npm_packages
