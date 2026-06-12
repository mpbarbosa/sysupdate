#!/bin/bash
#
# check_kitty_update.sh - Kitty terminal emulator update manager
# SNIPPET_ID: kitty
# SNIPPET_NAME: Kitty Terminal Emulator
#
# Handles version checking and updates for Kitty terminal.
# Reference: https://github.com/kovidgoyal/kitty
#
# Version: 0.1.0-alpha
# Date: 2025-11-25
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2025-11-25) - Initial alpha version with upgrade script pattern
#                            - Migrated from hardcoded to config-driven approach
#                            - Uses config_driven_version_check() from upgrade_utils.sh
#                            - All strings externalized to kitty.yaml
#                            - Not ready for production use
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/kitty.yaml"

# Update Kitty terminal emulator
check_kitty_update() {
    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Handle installer script update (extracted to upgrade_utils.sh)
    if handle_installer_script_update; then
        # Post-installation: Handle old system installation
        local local_bin="$HOME/.local/bin"
        local kitty_app="$HOME/.local/kitty.app/bin/kitty"
        local system_kitty="/usr/bin/kitty"
        
        if [ -f "$kitty_app" ]; then
            mkdir -p "$local_bin"
            ln -sf "$kitty_app" "$local_bin/kitty"
            print_success "Updated kitty symlink in $local_bin"
            
            # Check if old system installation exists and takes precedence
            if [ -f "$system_kitty" ] || [ -L "$system_kitty" ]; then
                local system_version=$("$system_kitty" --version 2>/dev/null | head -1 | sed -E 's/.*\s([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
                local new_version=$("$kitty_app" --version 2>/dev/null | head -1 | sed -E 's/.*\s([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
                
                if [ "$system_version" != "$new_version" ]; then
                    print_warning "Old kitty installation found at $system_kitty (v$system_version)"
                    print_status "New version (v$new_version) installed at $kitty_app"
                    
                    if prompt_yes_no "Remove old system kitty installation?"; then
                        print_status "Removing old kitty installation..."
                        sudo apt remove --purge kitty -y 2>/dev/null || \
                        sudo rm -f "$system_kitty" /usr/lib/kitty /usr/share/man/man1/kitty.1.gz 2>/dev/null
                        print_success "Old kitty installation removed"
                    else
                        print_warning "To use new version, ensure $local_bin comes before /usr/bin in PATH"
                        print_status "Or run: hash -r && kitty --version to verify"
                    fi
                fi
            fi
        fi
    fi
}

check_kitty_update