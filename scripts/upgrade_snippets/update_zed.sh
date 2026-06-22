#!/bin/bash
#
# update_zed.sh - Zed Editor Update Manager
# SNIPPET_ID: zed
# SNIPPET_NAME: Zed Editor
#
# Handles version checking and updates for the Zed code editor.
# Reference: https://github.com/zed-industries/zed
#
# Updates by re-running the official install.sh installer, which refreshes the
# standalone ~/.local/zed.app install fronted by the `zed` CLI launcher.
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Uses zed-industries/zed releases for version checks
#                            - Updates through the official curl installer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/zed.yaml"

update_zed() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_installer_script_update; then
        return 1
    fi
}

update_zed
