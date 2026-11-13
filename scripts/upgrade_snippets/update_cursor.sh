#!/bin/bash
#
# update_cursor.sh - Cursor IDE Update Manager
# SNIPPET_ID: cursor
# SNIPPET_NAME: Cursor IDE
#
# Handles version checking and updates for Cursor IDE.
# Supports .deb package and AppImage installations.
#
# Reference: https://www.cursor.com/
#
# Version: 0.1.0-alpha
# Date: 2026-05-18
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-05-18) - Initial alpha version
#                            - Auto-detects deb vs AppImage install
#                            - Latest version resolved from download redirect URL
#

# Load upgrade utilities library
CURSOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$CURSOR_SCRIPT_DIR/../lib" && pwd)"
CONFIG_FILE="$CURSOR_SCRIPT_DIR/cursor.yaml"
# shellcheck source=../lib/upgrade_utils.sh
# shellcheck disable=SC1091
source "$LIB_DIR/upgrade_utils.sh"

verbose_enabled() {
    [ "${VERBOSE:-0}" -eq 1 ] || [ "${VERBOSE_MODE:-false}" = "true" ]
}

get_cursor_command_path() {
    local cursor_path
    cursor_path=$(command -v cursor 2>/dev/null) || return 1
    readlink -f "$cursor_path" 2>/dev/null || printf '%s\n' "$cursor_path"
}

extract_cursor_semver() {
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Detect how Cursor is installed: "deb", "appimage", or "unknown"
detect_cursor_install_method() {
    local appimage_dir
    appimage_dir=$(get_config "update.appimage_install_dir")
    local cursor_path
    cursor_path=$(get_cursor_command_path)

    if [[ "$cursor_path" == *.AppImage ]] || [[ "$cursor_path" == "$appimage_dir/cursor.AppImage" ]]; then
        echo "appimage"
    elif dpkg-query -W -f='${Status}' cursor 2>/dev/null | grep -q 'install ok installed'; then
        echo "deb"
    else
        echo "unknown"
    fi
}

# Resolve the latest available version by following the download redirect URL.
# The redirect target filename embeds the version, e.g.:
#   Cursor-3.4.20-x86_64.AppImage
get_cursor_latest_version() {
    local version_url
    version_url=$(get_config "version.download_url_version")

    local redirect_url
    redirect_url=$(curl -sI "$version_url" 2>/dev/null | \
                   grep -i '^location:' | awk '{print $2}' | tr -d '\r')

    echo "$redirect_url" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

get_cursor_deb_version() {
    if [ -x "/usr/bin/cursor" ]; then
        local version
        version=$(/usr/bin/cursor --version 2>/dev/null | extract_cursor_semver)
        if [ -n "$version" ]; then
            printf '%s\n' "$version"
            return 0
        fi
    fi

    dpkg-query -W -f='${Version}\n' cursor 2>/dev/null | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' | head -1
}

# How many cursor.AppImage.backup.<timestamp> files to keep after a
# verified-successful update, when update.backup_retention says nothing usable.
CURSOR_BACKUP_RETENTION_DEFAULT=2

# Cursor's backup is a file where Postman's is a directory; the rules for what
# is safe to delete are shared in lib/upgrade_utils.sh.
prune_cursor_backups() {
    local keep_file="${1:-}"
    local install_dir
    install_dir=$(get_config "update.appimage_install_dir")
    if [ -z "$install_dir" ]; then
        return 0
    fi

    prune_timestamped_backups \
        "$install_dir/cursor.AppImage.backup." \
        file \
        "$(get_backup_retention "$CURSOR_BACKUP_RETENTION_DEFAULT")" \
        "Cursor" \
        "$keep_file"
}

# Read the version the AppImage records about itself, without mounting it.
#
# `cursor --version` launches the app, which needs the image's squashfs
# mounted. Where unprivileged FUSE is denied the run dies with
#   /usr/bin/fusermount: mount failed: Operation not permitted
# and prints no version at all -- the machine this was found on reported
# "Failed to get current Cursor version" on every run for that reason.
#
# The type2 runtime can still extract individual files with no mount
# whatsoever, and the bundled .desktop carries X-AppImage-Version. Measured at
# 0.02s against a 313 MB image, so this runs BEFORE the launch probe below
# rather than as its fallback.
cursor_appimage_desktop_version() {
    local appimage="$1"
    local workdir version

    [ -n "$appimage" ] && [ -x "$appimage" ] || return 1
    command -v timeout &>/dev/null || return 1
    workdir=$(mktemp -d 2>/dev/null) || return 1

    # --appimage-extract writes squashfs-root/ into the CURRENT directory, so
    # it has to run somewhere disposable rather than wherever we were invoked.
    ( cd "$workdir" && timeout 30s "$appimage" --appimage-extract '*.desktop' ) >/dev/null 2>&1

    version=$(grep -hs '^X-AppImage-Version=' "$workdir"/squashfs-root/*.desktop 2>/dev/null \
                  | head -1 | cut -d= -f2- | extract_cursor_semver)

    rm -rf -- "$workdir"

    [ -n "$version" ] || return 1
    printf '%s\n' "$version"
}

get_cursor_appimage_version() {
    local cursor_path
    cursor_path=$(get_cursor_command_path)

    if [ -z "$cursor_path" ]; then
        return 1
    fi

    local version
    version=$(printf '%s\n' "$cursor_path" | extract_cursor_semver)
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
        return 0
    fi

    # Embedded metadata first: it needs no mount, so it is the only read that
    # still works where FUSE is denied, and it is faster than launching the app.
    version=$(cursor_appimage_desktop_version "$cursor_path")
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
        return 0
    fi

    if ! command -v timeout &>/dev/null; then
        return 1
    fi

    local probe_output
    probe_output=$(timeout 8s "$cursor_path" --no-sandbox --version 2>&1 || true)

    version=$(printf '%s\n' "$probe_output" | sed -nE 's@.*updateURL .*?/cursor/([0-9]+\.[0-9]+\.[0-9]+)/.*@\1@p' | head -1)
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
        return 0
    fi

    printf '%s\n' "$probe_output" | extract_cursor_semver
}

# Check versions and populate CURRENT_VERSION, LATEST_VERSION, VERSION_STATUS, APP_DISPLAY_NAME
check_cursor_version() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"
    APP_DISPLAY_NAME=$(get_config "application.display_name")

    # Verify Cursor is installed
    if verbose_enabled; then
        print_status "Verifying Cursor installation..."
    fi
    if ! command -v cursor &>/dev/null; then
        local install_help
        install_help=$(get_config "messages.install_help")
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_error "Cursor IDE is not installed"
        echo -e "$install_help"
        ask_continue
        return 1
    fi
    if verbose_enabled; then
        print_success "Cursor installation detected"
    fi

    local install_method
    install_method=$(detect_cursor_install_method)

    # Get current version
    if verbose_enabled; then
        print_status "Retrieving current version..."
    fi
    case "$install_method" in
        deb)
            CURRENT_VERSION=$(get_cursor_deb_version)
            ;;
        appimage)
            CURRENT_VERSION=$(get_cursor_appimage_version)
            ;;
        *)
            CURRENT_VERSION=$(cursor --version 2>/dev/null | head -1 | extract_cursor_semver)
            ;;
    esac

    if [ -z "$CURRENT_VERSION" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_version")
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        # Say WHY. Every read path above sends stderr to /dev/null, so the one
        # line that explains the failure -- typically an AppImage that cannot
        # mount ("fusermount: mount failed: Operation not permitted") -- was
        # being swallowed, leaving a bare "Failed to get current Cursor
        # version" with nothing to act on. Bounded, because where FUSE *does*
        # work this launches the editor.
        if command -v timeout &>/dev/null; then
            local probe_err
            probe_err=$(timeout 15s cursor --version 2>&1 >/dev/null \
                            | grep -vE '^[[:space:]]*$' | head -2)
            if [ -n "$probe_err" ]; then
                while IFS= read -r _line; do
                    [ -n "$_line" ] && print_error "  ↳ $_line"
                done <<< "$probe_err"
            fi
        fi
        ask_continue
        return 1
    fi

    # Get latest version
    if verbose_enabled; then
        print_status "Fetching latest version from download server..."
    fi
    LATEST_VERSION=$(get_cursor_latest_version)
    if [ -z "$LATEST_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_warning "Could not determine latest version — skipping update check"
        ask_continue
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    return 0
}

# Update Cursor installed via .deb package
perform_cursor_update_deb() {
    local temp_deb
    temp_deb=$(get_config "update.temp_file_deb")
    local download_url
    download_url=$(get_config "update.download_url_deb")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    local fix_deps
    fix_deps=$(get_config "update.fix_dependencies")

    local downloading_msg
    downloading_msg=$(get_config "messages.downloading_deb")
    print_status "$downloading_msg"

    if ! download_with_progress "$download_url" "$temp_deb"; then
        print_error "Failed to download Cursor .deb package"
        rm -f "$temp_deb"
        return 1
    fi

    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "$installing_msg"

    if ! sudo dpkg -i "$temp_deb" 2>&1 | tail -"$output_lines"; then
        print_warning "dpkg reported errors — attempting to fix dependencies..."
        eval "sudo $fix_deps" 2>/dev/null
    fi

    rm -f "$temp_deb"

    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"
    show_installation_info "cursor" "$APP_DISPLAY_NAME"
    return 0
}

# Update Cursor installed as an AppImage
perform_cursor_update_appimage() {
    local temp_appimage
    temp_appimage=$(get_config "update.temp_file_appimage")
    local download_url
    download_url=$(get_config "update.download_url_appimage")
    local install_dir
    install_dir=$(get_config "update.appimage_install_dir")
    local symlink
    symlink=$(get_config "update.appimage_symlink")

    local downloading_msg
    downloading_msg=$(get_config "messages.downloading_appimage")
    print_status "$downloading_msg"

    if ! download_with_progress "$download_url" "$temp_appimage"; then
        print_error "Failed to download Cursor AppImage"
        rm -f "$temp_appimage"
        return 1
    fi

    # Back up and replace the existing AppImage. `backup` is declared out here
    # so the prune below can be told which file belongs to the run in flight.
    local backup=""
    if [[ -f "$install_dir/cursor.AppImage" ]]; then
        local backing_up_msg
        backing_up_msg=$(get_config "messages.backing_up")
        print_status "$backing_up_msg"
        backup="$install_dir/cursor.AppImage.backup.$(date +%Y%m%d_%H%M%S)"
        sudo mv "$install_dir/cursor.AppImage" "$backup" || {
            print_error "Failed to back up existing AppImage"
            rm -f "$temp_appimage"
            return 1
        }
    fi

    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "$installing_msg"

    sudo mkdir -p "$install_dir"
    sudo mv "$temp_appimage" "$install_dir/cursor.AppImage"
    sudo chmod +x "$install_dir/cursor.AppImage"

    # Ensure symlink is in place
    if [[ ! -e "$symlink" ]]; then
        local symlink_msg
        symlink_msg=$(get_config "messages.creating_symlink")
        print_status "$symlink_msg"
        sudo ln -sf "$install_dir/cursor.AppImage" "$symlink"
    fi

    # Refresh desktop entry
    create_cursor_desktop_entry "$install_dir"

    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"
    show_installation_info "cursor" "$APP_DISPLAY_NAME"

    # Only now that the new image is in place: every run moved the old one
    # aside and nothing ever removed it. Measured on one machine, 50 images
    # and 15 GB in /opt/Cursor.
    prune_cursor_backups "$backup"
    return 0
}

# Write a .desktop entry so Cursor appears in app launchers
create_cursor_desktop_entry() {
    local install_dir="$1"
    local desktop_msg
    desktop_msg=$(get_config "messages.creating_desktop")
    print_status "$desktop_msg"

    local desktop_file="$HOME/.local/share/applications/cursor.desktop"
    mkdir -p "$(dirname "$desktop_file")"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Cursor
Exec=$install_dir/cursor.AppImage --no-sandbox %U
Icon=$install_dir/cursor.png
Type=Application
Categories=Development;TextEditor;IDE;
MimeType=text/plain;inode/directory;
Terminal=false
StartupWMClass=Cursor
EOF

    chmod +x "$desktop_file"
}

# Main entry point
update_cursor() {
    if ! check_cursor_version; then
        return 0
    fi

    if [ "$VERSION_STATUS" -ne 2 ]; then
        handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS"
        return 0
    fi

    local install_method
    install_method=$(detect_cursor_install_method)

    case "$install_method" in
        deb)
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
                "perform_cursor_update_deb"; then
                ask_continue
                return 1
            fi
            ;;
        appimage)
            if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
                "perform_cursor_update_appimage"; then
                ask_continue
                return 1
            fi
            ;;
        *)
            print_error "Could not detect Cursor installation method"
            local install_help
            install_help=$(get_config "messages.install_help")
            echo -e "$install_help"
            ask_continue
            return 1
            ;;
    esac
}

update_cursor
