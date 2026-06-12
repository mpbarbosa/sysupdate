#!/bin/bash
#
# check_calibre_update.sh - Calibre Update Manager
# SNIPPET_ID: calibre
# SNIPPET_NAME: Calibre e-book Manager
#
# Handles version checking and updates for Calibre e-book manager.
# Reference: https://github.com/kovidgoyal/calibre
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
#                            - All strings externalized to calibre.yaml
#                            - Not ready for production use
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/calibre.yaml"

# Update Calibre e-book manager
check_calibre_update() {
    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Handle installer script update (extracted to upgrade_utils.sh)
    handle_installer_script_update
}

check_calibre_update