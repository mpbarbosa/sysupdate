#!/bin/bash
#
# update_oh_my_posh.sh - Oh My Posh Update Manager
# SNIPPET_ID: oh-my-posh
# SNIPPET_NAME: Oh My Posh
#
# Handles version checking and updates for Oh My Posh, a prompt theme engine.
# Reference: https://github.com/JanDeDobbeleer/oh-my-posh
#
# Note: distinct from the `oh-my-bash` and `oh-my-zsh` snippets — Oh My Posh is
# a standalone cross-shell prompt engine, not a shell framework.
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Uses JanDeDobbeleer/oh-my-posh releases for version checks
#                            - Updates through the built-in `oh-my-posh upgrade` command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/oh_my_posh.yaml"

# Oh My Posh updates via its official install script (config-driven). We do NOT
# use the built-in `oh-my-posh upgrade`: it exits 0 without acting on major
# version jumps (e.g. "use --force"), and even `upgrade --force` is a no-op for a
# manual ~/.local/bin install — so the previous command-based snippet reported a
# phantom "updated" while the binary never changed. The installer reliably
# fetches the latest release and replaces the binary in place; the shared
# handler then verifies the installed version actually advanced.
update_oh_my_posh() {
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    handle_installer_script_update
}

update_oh_my_posh
