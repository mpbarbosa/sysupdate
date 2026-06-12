#!/bin/bash
#
# system_update.sh - Comprehensive Package Management and System Update Script
#
# This script provides comprehensive package management across multiple package managers
# including APT, Snap, Rust/Cargo, pip (Python), and npm (Node.js). It automates the
# process of updating, upgrading, and maintaining packages while providing intelligent
# error handling and user interaction.
#
# Features:
# - Multi-package-manager support (apt, pacman, snap, cargo, pip, npm)
# - Interactive and quiet modes
# - Intelligent handling of kept back packages
# - Comprehensive package listing and statistics
# - Application update checking (Calibre, Ghostty, GitHub Copilot CLI, Anthropic Claude CLI, Oh My Zsh)
# - Detailed error analysis and recovery suggestions
# - Progress tracking and user confirmation options
# - Modular architecture with separated package manager modules
#
# Usage:
#   ./system_update.sh [OPTIONS]
#
# Options:
#   -q, --quiet       Run in quiet mode (no user prompts)
#   -s, --simple      Simple mode (skip cleanup)
#   -f, --full        Full mode (run system_summary.sh first + dist-upgrade)
#   -c, --cleanup     Cleanup only mode
#   -l, --list        List all installed packages
#   --list-detailed   List all packages with detailed information
#   --verbose         Enable verbose output mode
#   -v, --version     Show version information
#   -h, --help        Show help message
#
# Dependencies:
#   - sudo access for system package operations
#   - Various package managers (detected automatically)
#   - Network connectivity for package updates
#
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

#=============================================================================
# SCRIPT VERSION AND METADATA
#=============================================================================
readonly SCRIPT_VERSION="0.5.0"
readonly SCRIPT_NAME="system_update.sh"
readonly SCRIPT_DESCRIPTION="Comprehensive Package Management and System Update Script"
readonly SCRIPT_AUTHOR="mpb"
readonly SCRIPT_REPOSITORY="https://github.com/mpbarbosa/sysupdate"

#=============================================================================
# DETERMINE SCRIPT DIRECTORY AND SOURCE LIBRARIES
#=============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source all library modules
source "$LIB_DIR/core_lib.sh"
source "$LIB_DIR/app_managers.sh"
source "$LIB_DIR/apt_manager.sh"
source "$LIB_DIR/pacman_manager.sh"
source "$LIB_DIR/dpkg_manager.sh"

#=============================================================================
# GLOBAL FLAGS AND CONFIGURATION
#=============================================================================
QUIET_MODE=false
SIMPLE_MODE=false
FULL_MODE=false
CLEANUP_ONLY=false
LIST_PACKAGES=false
LIST_DETAILED=false
VERBOSE_MODE=false
LIST_SNIPPETS=false
LOG_HISTORY=false
LOG_HISTORY_LIMIT=20
SNIPPET_ID_FILTER=""
JSON_EVENTS=false
CHECK_ONLY_MODE=false
ORIGINAL_ARGS=("$@")
RUN_EVENTS_ACTIVE=false
RUN_STARTED_AT=$(date +%s)

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

show_version() {
    echo -e "${BLUE}${SCRIPT_NAME}${NC} - ${SCRIPT_DESCRIPTION}"
    echo -e "${CYAN}Version:${NC} ${SCRIPT_VERSION}"
    echo -e "${CYAN}Author:${NC} ${SCRIPT_AUTHOR}"
    echo -e "${CYAN}Repository:${NC} ${SCRIPT_REPOSITORY}"
    echo -e "${CYAN}License:${NC} MIT"
    echo ""
    echo -e "${YELLOW}Features:${NC}"
    echo "  • Multi-package-manager support (APT, Pacman, Snap, Rust/Cargo, Python pip, Node.js npm)"
    echo "  • Interactive and quiet modes with hierarchical output formatting"
    echo "  • Intelligent handling of kept back packages and dependency conflicts"
    echo "  • Comprehensive package listing, statistics, and application update checking"
    echo "  • Modular architecture with separated package manager modules"
    echo ""
    echo -e "${GREEN}Package Managers Supported:${NC}"
    echo "  📦 APT/DPKG    🏹 Pacman     🦀 Rust/Cargo"
    echo "  📱 Snap        🐍 Python pip 📗 Node.js npm"
    echo "  🐱 Kitty       📚 Calibre    👻 Ghostty"
    echo "  🤖 GitHub Copilot CLI       🧠 Anthropic Claude CLI"
    echo "  🐚 Oh My Zsh"
}

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Comprehensive system update and package management script supporting multiple
package managers including APT, Pacman, Snap, Cargo, pip, and npm.

Options:
    -q, --quiet         Run in quiet mode (no user prompts)
    -s, --simple        Simple mode (skip cleanup operations)
    -f, --full          Full mode (run system_summary.sh from same directory + dist-upgrade)
    -c, --cleanup       Cleanup only mode (just run cleanup operations)
    -l, --list          List all installed packages
    --list-detailed     List all packages with detailed information
    --list-snippets     List all upgrade snippets with their IDs
    --log-history       Print persisted run history as JSONL
    --log-history-limit <n>  Limit log history output (default: 20)
    --snippet <id>      Run only the upgrade snippet with the given ID
    --check-only        Run read-only update discovery checks
    --json-events       Emit JSONL events to stderr alongside normal output
    --verbose           Enable verbose output mode
    -v, --version       Show version information
    -h, --help          Show this help message

Examples:
    $SCRIPT_NAME                        # Run with interactive prompts
    $SCRIPT_NAME -q                     # Run quietly without prompts
    $SCRIPT_NAME -f                     # Full system upgrade
    $SCRIPT_NAME -l                     # List installed packages
    $SCRIPT_NAME -c                     # Cleanup only
    $SCRIPT_NAME --list-snippets        # List all available upgrade snippets
    $SCRIPT_NAME --log-history          # Print the last 20 persisted log entries
    $SCRIPT_NAME --snippet chrome       # Run only the Google Chrome upgrade snippet
    $SCRIPT_NAME --snippet pip -q       # Run pip upgrade snippet quietly
    $SCRIPT_NAME --check-only           # Run read-only update discovery checks
    $SCRIPT_NAME --json-events          # Emit machine-readable JSONL events

Package Managers:
    • APT/DPKG (Debian/Ubuntu)
    • Pacman (Arch Linux)
    • Snap (Universal packages)
    • Rust/Cargo
    • Python pip
    • Node.js npm
    • Kitty terminal
    • Calibre e-book manager
    • Ghostty
    • GitHub Copilot CLI
    • Anthropic Claude CLI
    • Oh My Zsh

Author: $SCRIPT_AUTHOR
Repository: $SCRIPT_REPOSITORY
License: MIT
EOF
}

list_all_packages() {
    local detailed="${1:-}"
    
    print_section_header "INSTALLED PACKAGES SUMMARY"
    
    PKG_MANAGER=$(detect_package_manager)
    
    if [ "$PKG_MANAGER" = "apt" ]; then
        print_operation_header "APT Packages:"
        local apt_count=$(apt list --installed 2>/dev/null | wc -l)
        print_status "Total APT packages: $apt_count"
        
        if [ "$detailed" = "--detailed" ]; then
            apt list --installed 2>/dev/null | head -50
        fi
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        print_operation_header "Pacman Packages:"
        local pacman_count=$(pacman -Q | wc -l)
        print_status "Total Pacman packages: $pacman_count"
        
        if [ "$detailed" = "--detailed" ]; then
            pacman -Q | head -50
        fi
    fi
    
    if command -v snap &> /dev/null; then
        print_operation_header "Snap Packages:"
        snap list 2>/dev/null | head -20
    fi
    
    if command -v cargo &> /dev/null; then
        print_operation_header "Cargo Packages:"
        cargo install --list 2>/dev/null | head -20
    fi
    
    if command -v pip3 &> /dev/null; then
        print_operation_header "Python pip Packages:"
        local pip_count
        pip_count=$(pip3 list 2>/dev/null | wc -l)
        print_status "Total pip packages: $pip_count"
        
        if [ "$detailed" = "--detailed" ]; then
            pip3 list 2>/dev/null | head -30
        fi
    fi
    
    if command -v npm &> /dev/null; then
        print_operation_header "Node.js Global Packages:"
        npm list -g --depth=0 2>/dev/null | head -20
    fi
}

show_log_history() {
    if [ ! -f "$SYSUPDATE_LOG_FILE" ]; then
        print_warning "No persisted run history found at $SYSUPDATE_LOG_FILE"
        return 0
    fi

    tail -n "$LOG_HISTORY_LIMIT" "$SYSUPDATE_LOG_FILE"
}

#=============================================================================
# ARGUMENT PARSING
#=============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -s|--simple)
            SIMPLE_MODE=true
            shift
            ;;
        -f|--full)
            FULL_MODE=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP_ONLY=true
            shift
            ;;
        -l|--list)
            LIST_PACKAGES=true
            shift
            ;;
        --list-detailed)
            LIST_PACKAGES=true
            LIST_DETAILED=true
            shift
            ;;
        --verbose)
            VERBOSE_MODE=true
            shift
            ;;
        --json-events)
            JSON_EVENTS=true
            shift
            ;;
        --check-only)
            CHECK_ONLY_MODE=true
            shift
            ;;
        --list-snippets)
            LIST_SNIPPETS=true
            shift
            ;;
        --log-history)
            LOG_HISTORY=true
            shift
            ;;
        --log-history-limit)
            if [ -z "${2:-}" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --log-history-limit requires a numeric argument"
                usage
                exit 1
            fi
            LOG_HISTORY_LIMIT="$2"
            shift 2
            ;;
        --snippet)
            if [ -z "${2:-}" ]; then
                echo "Error: --snippet requires an ID argument"
                usage
                exit 1
            fi
            SNIPPET_ID_FILTER="$2"
            shift 2
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

emit_run_lifecycle_event() {
    local event_type="$1"
    local exit_code="$2"

    emit_event "$event_type" \
        "script" "$SCRIPT_NAME" \
        "repository" "$SCRIPT_REPOSITORY" \
        "cwd" "$PWD" \
        "args" "${ORIGINAL_ARGS[*]}" \
        "quiet_mode" "$QUIET_MODE" \
        "simple_mode" "$SIMPLE_MODE" \
        "full_mode" "$FULL_MODE" \
        "cleanup_only" "$CLEANUP_ONLY" \
        "list_packages" "$LIST_PACKAGES" \
        "list_detailed" "$LIST_DETAILED" \
        "list_snippets" "$LIST_SNIPPETS" \
        "log_history" "$LOG_HISTORY" \
        "log_history_limit" "$LOG_HISTORY_LIMIT" \
        "snippet_id_filter" "$SNIPPET_ID_FILTER" \
        "check_only_mode" "$CHECK_ONLY_MODE" \
        "json_events" "$JSON_EVENTS" \
        "exit_code" "$exit_code"
}

resolve_run_action() {
    if [ "$LIST_SNIPPETS" = true ]; then
        echo "list-snippets"
    elif [ "$LIST_PACKAGES" = true ]; then
        echo "list-packages"
    elif [ "$CLEANUP_ONLY" = true ]; then
        echo "cleanup"
    elif [ -n "$SNIPPET_ID_FILTER" ] && [ "$CHECK_ONLY_MODE" = true ]; then
        echo "snippet-check"
    elif [ -n "$SNIPPET_ID_FILTER" ]; then
        echo "snippet-run"
    elif [ "$CHECK_ONLY_MODE" = true ]; then
        echo "check-only-run"
    else
        echo "update-run"
    fi
}

resolve_run_target() {
    if [ -n "$SNIPPET_ID_FILTER" ]; then
        echo "$SNIPPET_ID_FILTER"
    else
        echo "$SCRIPT_NAME"
    fi
}

format_run_duration() {
    local duration_seconds="$1"

    if [ "$duration_seconds" -lt 60 ]; then
        printf '%ss' "$duration_seconds"
    else
        printf '%sm %ss' "$((duration_seconds / 60))" "$((duration_seconds % 60))"
    fi
}

handle_run_exit() {
    local exit_code=$?
    local finished_at
    finished_at=$(date +%s)
    local duration_seconds=$((finished_at - RUN_STARTED_AT))
    local duration
    duration=$(format_run_duration "$duration_seconds")
    local run_status="failed"
    if [ "$exit_code" -eq 0 ]; then
        run_status="success"
    fi
    local action
    action=$(resolve_run_action)
    local target
    target=$(resolve_run_target)
    local details
    details="Completed ${action} with exit code ${exit_code}. Args: ${ORIGINAL_ARGS[*]:-(none)}"

    if [ "$RUN_EVENTS_ACTIVE" = true ]; then
        if [ "$exit_code" -eq 0 ]; then
            emit_run_lifecycle_event "run.completed" "$exit_code"
        else
            emit_run_lifecycle_event "run.failed" "$exit_code"
        fi
    fi

    emit_log_event "$action" "$target" "$run_status" \
        "category" "system" \
        "details" "$details" \
        "duration" "$duration" \
        "exit_code" "$exit_code"
}

trap handle_run_exit EXIT

#=============================================================================
# MAIN EXECUTION
#=============================================================================

if [ "$CHECK_ONLY_MODE" = true ]; then
    QUIET_MODE=true
fi

if [ "$JSON_EVENTS" = true ]; then
    enable_json_events
    RUN_EVENTS_ACTIVE=true
    emit_run_lifecycle_event "run.started" "0"
fi

# Load .bashrc if available
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"

# Handle list snippets mode
if [ "$LIST_SNIPPETS" = true ]; then
    list_upgrade_snippets
    exit 0
fi

# Handle persisted log history mode
if [ "$LOG_HISTORY" = true ]; then
    show_log_history
    exit 0
fi

# Handle list packages mode
if [ "$LIST_PACKAGES" = true ]; then
    echo "=========================================="
    if [ "$LIST_DETAILED" = true ]; then
        list_all_packages --detailed
    else
        list_all_packages
    fi
    exit 0
fi

# Execute system_summary.sh if full mode is enabled
if [ "$FULL_MODE" = true ]; then
    print_status "Full mode enabled - executing system_summary.sh first..."
    if [ -f "$SCRIPT_DIR/system_summary.sh" ]; then
        if bash "$SCRIPT_DIR/system_summary.sh"; then
            true
        else
            print_warning "system_summary.sh execution failed, continuing with operations..."
        fi
    else
        print_warning "system_summary.sh not found in same directory, skipping..."
    fi
    ask_continue
fi

# Handle cleanup only mode
if [ "$CLEANUP_ONLY" = true ]; then
    print_status "Running in cleanup-only mode"
    PKG_MANAGER=$(detect_package_manager)
    
    if [ "$PKG_MANAGER" = "pacman" ]; then
        source "$LIB_DIR/pacman_manager.sh"
        clean_pacman_cache
        remove_pacman_orphans
    elif [ "$PKG_MANAGER" = "apt" ]; then
        cleanup
    fi
    exit 0
fi

# When a specific snippet is requested, skip package manager updates
if [ -n "$SNIPPET_ID_FILTER" ]; then
    print_section_header "LOAD UPGRADE SNIPPETS"
    source_upgrade_snippets
    exit 0
fi

# Detect package manager
PKG_MANAGER=$(detect_package_manager)

if [ "$CHECK_ONLY_MODE" = true ]; then
    print_status "Check-only mode enabled - running read-only discovery checks"

    if [ "$PKG_MANAGER" = "pacman" ]; then
        print_section_header "PACMAN PACKAGE MANAGER"
        check_pacman_config
        check_pacman_updates
    elif [ "$PKG_MANAGER" = "apt" ]; then
        check_broken_packages
        print_section_header "APT PACKAGE MANAGER"
        check_unattended_upgrades
        check_updates_available
        
        print_section_header "DPKG PACKAGE MANAGER"
        maintain_dpkg_packages
    else
        print_warning "No supported package manager detected (apt or pacman)"
    fi

    print_section_header "LOAD UPGRADE SNIPPETS"
    source_upgrade_snippets
    exit 0
fi

# Package Manager Specific Operations
if [ "$PKG_MANAGER" = "pacman" ]; then
    print_section_header "PACMAN PACKAGE MANAGER"
    check_pacman_config
    update_pacman_database
    upgrade_pacman_packages
elif [ "$PKG_MANAGER" = "apt" ]; then
    check_broken_packages
    print_section_header "APT PACKAGE MANAGER"
    check_unattended_upgrades
    update_package_list
    upgrade_packages
    
    print_section_header "DPKG PACKAGE MANAGER"
    maintain_dpkg_packages
else
    print_warning "No supported package manager detected (apt or pacman)"
fi

# Load upgrade snippets
print_section_header "LOAD UPGRADE SNIPPETS"
source_upgrade_snippets

# System Upgrade Operations (only in full mode)
if [ "$FULL_MODE" = true ]; then
    print_section_header "SYSTEM UPGRADE"
    if [ "$PKG_MANAGER" = "apt" ]; then
        full_upgrade
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        print_status "Full system upgrade already performed with pacman -Syu"
    fi
fi

# Cleanup unless in simple mode
if [ "$SIMPLE_MODE" = false ]; then
    if [ "$PKG_MANAGER" = "pacman" ]; then
        clean_pacman_cache
        remove_pacman_orphans
    elif [ "$PKG_MANAGER" = "apt" ]; then
        cleanup
    fi
fi

# Final status
echo "=========================================="
print_success "Comprehensive system update and package management script completed successfully!"

# Show summary of installed packages
print_status "Summary of installed packages:"
if [ "$PKG_MANAGER" = "pacman" ]; then
    pacman -Q | wc -l | awk '{print "Total installed packages: " $1}'
elif [ "$PKG_MANAGER" = "apt" ]; then
    apt list --installed 2>/dev/null | wc -l | awk '{print "Total installed packages: " $1}'
fi

# Check if reboot is required
if [ -f /var/run/reboot-required ]; then
    print_warning "A system reboot is required to complete the updates."
    echo "You can reboot now using: sudo reboot"
fi

exit 0
