#!/bin/bash
#
# pacman_manager.sh - Pacman Package Manager Operations (Arch Linux)
#
# Handles all Pacman package operations including updates, upgrades,
# cache management, and orphan removal.
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

#=============================================================================
# PACMAN PACKAGE MANAGER FUNCTIONS (Arch Linux)
#=============================================================================

update_pacman_database() {
    print_operation_header "Updating package database from repositories..."
    
    if run_with_sudo pacman -Sy --noconfirm; then
        print_success "Package database updated successfully"
    else
        print_error "Failed to update package database"
        return 1
    fi
}

check_pacman_updates() {
    print_operation_header "Checking available Pacman package updates..."

    local updates_available
    updates_available=$(pacman -Qu 2>/dev/null | wc -l)

    if [ "$updates_available" -eq 0 ]; then
        print_success "All packages are up to date"
        emit_summary_event "pacman_updates" "package_manager" "pacman" "status" "up_to_date" "total_updates" "0"
        return 1
    fi

    print_status "Found $updates_available package(s) to upgrade"
    emit_summary_event "pacman_updates" "package_manager" "pacman" "status" "update_available" "total_updates" "$updates_available"
    return 0
}

# Upgrade all pacman packages
upgrade_pacman_packages() {
    print_operation_header "Upgrading installed packages..."
    
    if ! check_pacman_updates; then
        return 0
    fi
    
    if run_with_sudo pacman -Su --noconfirm; then
        print_success "Package upgrade completed successfully"
    else
        print_error "Package upgrade failed"
        return 1
    fi
}

# Clean pacman cache
clean_pacman_cache() {
    print_operation_header "Cleaning package cache..."
    
    # Remove uninstalled packages from cache
    if run_with_sudo pacman -Sc --noconfirm; then
        print_success "Package cache cleaned successfully"
    else
        print_warning "Failed to clean package cache"
    fi
    
    # Show cache size
    local cache_size=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    if [ -n "$cache_size" ]; then
        print_status "Current cache size: $cache_size"
    fi
}

# Remove orphaned packages (packages installed as dependencies but no longer needed)
remove_pacman_orphans() {
    print_operation_header "Removing orphaned packages..."
    
    local orphans=$(pacman -Qdtq 2>/dev/null)
    
    if [ -z "$orphans" ]; then
        print_success "No orphaned packages found"
        return 0
    fi
    
    local orphan_count=$(echo "$orphans" | wc -l)
    print_status "Found $orphan_count orphaned package(s)"
    
    if run_with_sudo pacman -Rns --noconfirm $orphans; then
        print_success "Orphaned packages removed successfully"
    else
        print_warning "Failed to remove some orphaned packages"
    fi
}

# List all pacman packages
list_pacman_packages() {
    local detailed="${1:-false}"
    
    print_operation_header "Listing installed Pacman packages..."
    
    local total=$(pacman -Q | wc -l)
    print_status "Total Pacman packages: $total"
    
    if [ "$detailed" = "--detailed" ]; then
        print_status "Package details:"
        pacman -Q
    fi
}

# Check for pacman configuration issues
check_pacman_config() {
    print_operation_header "Checking Pacman configuration..."
    
    # Check if pacman.conf exists and is valid
    if [ ! -f /etc/pacman.conf ]; then
        print_error "Pacman configuration file not found"
        return 1
    fi
    
    # Check if pacman database is locked
    if [ -f /var/lib/pacman/db.lck ]; then
        print_warning "Pacman database is locked"
        print_status "If no pacman process is running, remove the lock file with:"
        echo "  sudo rm /var/lib/pacman/db.lck"
        return 1
    fi
    
    print_success "Pacman configuration OK"
}
