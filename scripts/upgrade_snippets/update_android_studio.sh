#!/bin/bash
#
# update_android_studio.sh - Android Studio Update Manager
# SNIPPET_ID: android-studio
# SNIPPET_NAME: Android Studio
#
# Reports the installed Android Studio build against the newest build Google
# publishes for the stable channel.
#
# Android Studio is a manual /opt install (no apt/snap package) and sysupdate
# does NOT attempt to download the ~1 GB tarball or swap /opt in place — the
# IDE applies its own updates reliably through Help > Check for Updates. What
# this snippet does is tell you whether that is worth doing: it reads the same
# feed the IDE's updater uses (updates.xml) so a build that is a full release
# behind cannot sit on the dashboard looking like an all-clear.
#
# Statuses emitted:
#   not_installed  - nothing at $ANDROID_STUDIO_HOME
#   unknown        - the feed or the installed build could not be read (retryable)
#   up_to_date     - installed build is at, or ahead of, the channel's newest
#   self_managed   - a newer build exists, but only the IDE can install it
#
# Version: 0.2.0-alpha
# Date: 2026-09-25
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-06-21) - Initial alpha version
#                            - Reports installed build from product-info.json
#                            - Informational only; update via the IDE's built-in updater
#   0.2.0-alpha (2026-09-25) - Resolve the newest stable build from updates.xml
#                            - Report up_to_date / self_managed / unknown instead of
#                              always claiming self_managed with no latest version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

ANDROID_STUDIO_DISPLAY_NAME="Android Studio"
ANDROID_STUDIO_HOME="${ANDROID_STUDIO_HOME:-/opt/android-studio}"
ANDROID_STUDIO_DOWNLOAD_URL="https://developer.android.com/studio"
# The feed the IDE's own updater polls. Overridable so tests never reach out.
ANDROID_STUDIO_UPDATES_URL="${ANDROID_STUDIO_UPDATES_URL:-https://dl.google.com/android/studio/patches/updates.xml}"
# updates.xml carries one <channel> per release track; "release" is stable.
ANDROID_STUDIO_CHANNEL_STATUS="${ANDROID_STUDIO_CHANNEL_STATUS:-release}"

# Installed build, e.g. "AI-251.25410.109.2511.13752376". product-info.json's
# `version` is already the feed's build number with the "AI-" product code on
# the front, so the two sides compare directly.
get_android_studio_version() {
    local product_info="$ANDROID_STUDIO_HOME/product-info.json"
    if [ -f "$product_info" ]; then
        get_config "version" "$product_info"
    fi
}

# Build numbers inside the <channel> whose status attribute is $1, one per line.
# Both <channel ...> and <build ...> are single-line elements in this feed; the
# <message> CDATA between them is skipped because only <build lines are read.
extract_android_studio_channel_builds() {
    local channel_status="$1"

    awk -v want="$channel_status" '
        /<channel[[:space:]]/ { inside = ($0 ~ ("status=\"" want "\"")); next }
        /<\/channel>/         { inside = 0; next }
        inside && /<build[[:space:]]/ {
            if (match($0, /number="[^"]*"/)) {
                print substr($0, RSTART + 8, RLENGTH - 9)
            }
        }
    '
}

# Newest build Google advertises on the configured channel, or empty + non-zero
# when the feed could not be fetched or held nothing that parses as a build.
get_android_studio_latest_build() {
    local feed
    feed=$(curl -fsSL --max-time 20 "$ANDROID_STUDIO_UPDATES_URL" 2>/dev/null) || return 1

    local build
    # Keep only well-formed "AI-<dotted digits>" numbers before picking the
    # highest, so a malformed or truncated feed cannot leak a bogus "latest".
    # select_highest_semver_tag drops the AI- prefix, so put it back.
    build=$(printf '%s\n' "$feed" \
        | extract_android_studio_channel_builds "$ANDROID_STUDIO_CHANNEL_STATUS" \
        | grep -E '^AI-[0-9]+(\.[0-9]+)+$' \
        | select_highest_semver_tag)

    [ -n "$build" ] || return 1
    printf 'AI-%s' "$build"
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
    print_status "Installed build: ${current_version:-unknown}"

    local latest_version
    latest_version=$(get_android_studio_latest_build) || latest_version=""

    # Either half missing means the check itself failed — a network miss, a
    # rate limit, an unreadable product-info.json. That is retryable, so report
    # "unknown" rather than a verdict we did not actually reach.
    if [ -z "$current_version" ] || [ -z "$latest_version" ]; then
        emit_summary_event "version_check" "target" "$ANDROID_STUDIO_DISPLAY_NAME" \
            "status" "unknown" "current_version" "${current_version:-unknown}" \
            "latest_version" "${latest_version:-unknown}"
        print_warning "Could not determine whether $ANDROID_STUDIO_DISPLAY_NAME is current"
        print_status "Full installer downloads: $ANDROID_STUDIO_DOWNLOAD_URL"
        ask_continue
        return 0
    fi

    print_status "Latest ${ANDROID_STUDIO_CHANNEL_STATUS} build: $latest_version"

    # Strip the shared "AI-" product code so both sides are plain dotted
    # numerics and compare_versions can hand them to dpkg.
    compare_versions "${current_version#AI-}" "${latest_version#AI-}"
    local comparison=$?

    if [ "$comparison" -ne 2 ]; then
        emit_summary_event "version_check" "target" "$ANDROID_STUDIO_DISPLAY_NAME" \
            "status" "up_to_date" "current_version" "$current_version" \
            "latest_version" "$latest_version"
        print_success "$ANDROID_STUDIO_DISPLAY_NAME is up to date ($current_version)"
        ask_continue
        return 0
    fi

    # A newer build exists but sysupdate cannot install it: the IDE patches
    # itself in place and the alternative is a ~1 GB tarball swap. Report
    # "self_managed" (not "update_available", which offers consumers an Upgrade
    # button that could only re-run this check).
    emit_summary_event "version_check" "target" "$ANDROID_STUDIO_DISPLAY_NAME" \
        "status" "self_managed" "current_version" "$current_version" \
        "latest_version" "$latest_version"
    print_warning "$ANDROID_STUDIO_DISPLAY_NAME update available: $current_version -> $latest_version"
    print_status "Install it from the IDE: Help > Check for Updates."
    print_status "Full installer downloads: $ANDROID_STUDIO_DOWNLOAD_URL"
    ask_continue
    return 0
}

update_android_studio
