#!/bin/bash
#
# run_update.sh - Quickshell launcher for system_update.sh
#
# Quickshell's Qt.resolvedUrl() cannot reference paths outside the quickshell/
# config directory (".." resolves to "qrc:/qs-blackhole"), so this same-directory
# wrapper exec's the real script using bash's own relative path resolution.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../../scripts/system_update.sh" "$@"
