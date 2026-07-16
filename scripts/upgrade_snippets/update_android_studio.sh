#!/bin/bash
#
# update_android_studio.sh - Android Studio Update Manager
# SNIPPET_ID: android-studio
# SNIPPET_NAME: Android Studio
#
# Reports the installed Android Studio build and points to the upgrade path.
#
# Android Studio is a manual /opt install (no apt/snap package) and Google does
# not publish a stable machine-readable "latest version" feed for the IDE, so
# this snippet does NOT attempt to scrape a remote version or auto-download the
# ~1 GB tarball. Android Studio updates itself reliably through its built-in
# updater (Help > Check for Updates); this snippet surfaces the installed build
# and the download page so the manual path is one step away.
#
# Version: 0.1.0-alpha
# Date: 2026-06-21
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Reports installed build from product-info.json
#                            - Informational only; update via the IDE's built-in updater

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

ANDROID_STUDIO_DISPLAY_NAME="Android Studio"
ANDROID_STUDIO_HOME="/opt/android-studio"
ANDROID_STUDIO_DOWNLOAD_URL="https://developer.android.com/studio"

get_android_studio_version() {
    local product_info="$ANDROID_STUDIO_HOME/product-info.json"
    if [ -f "$product_info" ]; then
        get_config "version" "$product_info"
    fi
}

update_android_studio() {
    print_operation_header "Checking Android Studio..."

    if [ ! -d "$ANDROID_STUDIO_HOME" ]; then
        emit_summary_event "version_check" "target" "$ANDROID_STUDIO_DISPLAY_NAME" \
            "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$ANDROID_STUDIO_DISPLAY_NAME not found at $ANDROID_STUDIO_HOME"
        print_status "Download Android Studio: $ANDROID_STUDIO_DOWNLOAD_URL"
        ask_continue
        return 0
    fi

    local current_version
    current_version=$(get_android_studio_version)
    current_version="${current_version:-unknown}"
    print_status "Installed build: $current_version"

    # Google publishes no stable machine-readable latest-version feed for the
    # IDE, and Android Studio updates itself via Help > Check for Updates. This
    # is informational, not a failure: report "self_managed" (not "unknown", which
    # consumers treat as a fetch failure and render as a red/RETRY card).
    emit_summary_event "version_check" "target" "$ANDROID_STUDIO_DISPLAY_NAME" \
        "status" "self_managed" "current_version" "$current_version" "latest_version" "unknown"

    print_status "Android Studio updates in place via Help > Check for Updates."
    print_status "Full installer downloads: $ANDROID_STUDIO_DOWNLOAD_URL"
    ask_continue
    return 0
}

update_android_studio
