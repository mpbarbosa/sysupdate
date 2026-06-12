#!/bin/bash
#
# sysupdate_status.sh - Quickshell status backend for the sysupdate widget
#
# Emits one line of JSON with the count of pending OS package updates.
# Local-only: relies on the existing apt/pacman cache, never makes network calls.
#
# Output: {"system": <count>, "package_manager": "apt"|"pacman"|"unknown"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib/core_lib.sh"

package_manager=$(detect_package_manager)

case "$package_manager" in
    apt)
        count=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
        ;;
    pacman)
        count=$(pacman -Qu 2>/dev/null | wc -l)
        ;;
    *)
        count=0
        ;;
esac

printf '{"system": %d, "package_manager": "%s"}\n' "$count" "$package_manager"
