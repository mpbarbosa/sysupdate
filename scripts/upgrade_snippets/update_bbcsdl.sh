#!/bin/bash
#
# update_bbcsdl.sh - BBC BASIC for SDL 2.0 Update Manager
# SNIPPET_ID: bbcsdl
# SNIPPET_NAME: BBC BASIC for SDL 2.0 (bbcsdl)
#
# Handles version checking and updates for BBC BASIC for SDL 2.0, the
# cross-platform BBC BASIC interpreter and IDE by Richard Russell.
#
# Reference: https://www.bbcbasic.co.uk/bbcsdl/index.html
# Source:    https://github.com/rtrussell/BBCSDL
#
# Version: 0.1.0-alpha
# Date: 2026-11-16
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-11-16) - Initial alpha version
#                            - Current version read from the executable's
#                              embedded banner (no --version flag exists)
#                            - Latest version read from the vendor changelog,
#                              the channel the download zip is served from
#                            - Replaces the install directory from the
#                              arch-matched zip, with bounded backups
#

# Load upgrade utilities library
BBCSDL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$BBCSDL_SCRIPT_DIR/../lib" && pwd)"
CONFIG_FILE="$BBCSDL_SCRIPT_DIR/bbcsdl.yaml"
source "$LIB_DIR/upgrade_utils.sh"

set -u
set -o pipefail

# How many <install_dir>.backup.<timestamp> directories to keep after a
# verified-successful update, when update.backup_retention says nothing usable.
BBCSDL_BACKUP_RETENTION_DEFAULT=2

# Set by backup_bbcsdl so the failure path can put the old tree back.
BBCSDL_BACKUP_DIR=""

#=============================================================================
# INSTALLATION DISCOVERY
#=============================================================================

# Expand a leading "~/" in a configured path against $HOME. Config values are
# read as data, never eval'd, so tilde expansion has to be done by hand.
expand_bbcsdl_path() {
    local path="$1"
    printf '%s' "${path/#\~\//$HOME/}"
}

# True when the file starts with the ELF magic number.
is_bbcsdl_elf() {
    local path="$1"
    [ -f "$path" ] || return 1
    local magic
    magic=$(head -c 4 "$path" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    [ "$magic" = "7f454c46" ]
}

# Resolve `bbcsdl` on PATH to the actual BBC BASIC executable.
#
# The vendor's own mkicon.sh, and most hand-rolled installs, put a one-line
# wrapper on PATH that execs the real binary out of the unpacked directory,
# because bbcsdl loads lib/ and examples/ relative to its own location and so
# cannot simply be copied into /usr/local/bin. `readlink -f` does not see
# through a wrapper like that, so the exec target is read out of it.
resolve_bbcsdl_binary() {
    local launcher
    launcher=$(command -v bbcsdl 2>/dev/null) || return 1
    launcher=$(readlink -f "$launcher" 2>/dev/null || printf '%s' "$launcher")

    if is_bbcsdl_elf "$launcher"; then
        printf '%s' "$launcher"
        return 0
    fi

    # A wrapper script: take the first exec'd path, expand $HOME/${HOME} in it,
    # and accept it only if it really is an executable.
    local target
    target=$(sed -n 's/^[[:space:]]*exec[[:space:]]\{1,\}"\{0,1\}\([^"[:space:]]*\)"\{0,1\}.*/\1/p' \
        "$launcher" 2>/dev/null | head -1)

    if [ -n "$target" ]; then
        target="${target//\$\{HOME\}/$HOME}"
        target="${target//\$HOME/$HOME}"
        target=$(expand_bbcsdl_path "$target")
        if is_bbcsdl_elf "$target"; then
            printf '%s' "$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")"
            return 0
        fi
    fi

    return 1
}

# A directory is the BBC BASIC installation only if it holds the executable
# AND at least one of the archive's own markers (lib/, bbcsdl.bbc).
#
# This guard is not cosmetic: the update replaces the directory wholesale, so
# accepting the directory of a stray `bbcsdl` copy in /usr/local/bin would mean
# backing up and replacing /usr/local/bin itself.
is_bbcsdl_install_dir() {
    local dir="$1"
    [ -d "$dir" ] || return 1
    [ -f "$dir/bbcsdl" ] || return 1

    local markers
    markers=$(get_config "update.install_dir_markers")
    local marker
    for marker in $markers; do
        if [ -e "$dir/$marker" ]; then
            return 0
        fi
    done

    return 1
}

# The directory holding the resolved executable, when it looks like a BBC BASIC
# installation.
get_bbcsdl_install_dir() {
    local binary="$1"
    local dir
    dir=$(dirname "$binary")

    if is_bbcsdl_install_dir "$dir"; then
        printf '%s' "$dir"
        return 0
    fi

    return 1
}

#=============================================================================
# VERSION DISCOVERY
#=============================================================================

# Read the version out of the executable's embedded banner, e.g.
# "BBC BASIC for Linux version 1.44a". bbcsdl has no --version flag — it is a
# windowed IDE, and running it to ask would open a window — so the file is read
# rather than executed. `grep -a` is used instead of `strings` so the check does
# not depend on binutils being installed.
get_current_bbcsdl_version() {
    local binary="$1"
    [ -n "$binary" ] && [ -f "$binary" ] || return 1

    local banner_regex
    banner_regex=$(get_config "version.binary_regex")
    local version_regex
    version_regex=$(get_config "version.binary_version_regex")

    if [ -z "$banner_regex" ] || [ -z "$version_regex" ]; then
        return 1
    fi

    local version
    version=$(LC_ALL=C grep -aoE "$banner_regex" "$binary" 2>/dev/null | head -1 | \
        grep -oE "$version_regex" | head -1)

    if [ -z "$version" ]; then
        return 1
    fi

    printf '%s' "$version"
}

# True when a string is a released BBC BASIC version ("1.44a", "1.43c").
is_valid_bbcsdl_version() {
    local candidate="$1"
    local version_regex
    version_regex=$(get_config "version.version_regex")
    [ -n "$version_regex" ] || return 1
    [[ "$candidate" =~ $version_regex ]]
}

# Resolve the latest RELEASED version from the vendor changelog table.
#
# The upstream GitHub repository is deliberately not used: it publishes neither
# releases nor tags, and include/version.h on master tracks the development
# head, which runs ahead of the published archive (1.44b vs 1.44a at the time of
# writing). Checking against it would report an update on every run that the
# download cannot satisfy. The site's changelog is the channel the zip itself is
# published on, so that is what is read.
#
# Each changelog row's first cell holds one released version, bare in recent
# rows and wrapped in a link to the release announcement in older ones; both
# shapes are matched. Whole-cell matches only — that is what keeps the download
# table's "(21.6 Mbytes)" out of the candidates — and the highest version wins
# rather than the first row, so a reordered table cannot yield a stale answer.
get_latest_bbcsdl_version() {
    local url
    url=$(get_config "version.changelog_url")
    local cell_regex
    cell_regex=$(get_config "version.changelog_cell_regex")

    if [ -z "$url" ] || [ -z "$cell_regex" ]; then
        return 1
    fi

    local version
    version=$(curl -fsSL --max-time 30 "$url" 2>/dev/null | \
        tr -d '\r' | \
        grep -oE "$cell_regex" | \
        grep -oE '[0-9]+\.[0-9]+[a-z]?' | \
        sort -V | \
        tail -1)

    if [ -z "$version" ] || ! is_valid_bbcsdl_version "$version"; then
        return 1
    fi

    printf '%s' "$version"
}

# The download for this CPU. The vendor publishes x86 ("linux") and Raspberry Pi
# ("rpi") editions only; anything else has no published build.
get_bbcsdl_asset_url() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)       arch="x86_64" ;;
        i386|i486|i586|i686) arch="i686" ;;
        aarch64|arm64)      arch="aarch64" ;;
        armv6l|armv7l|armhf) arch="armv7l" ;;
        *) return 1 ;;
    esac

    local url
    url=$(get_config "update.assets.$arch")
    if [ -z "$url" ]; then
        return 1
    fi

    printf '%s' "$url"
}

#=============================================================================
# UPDATE
#=============================================================================

get_bbcsdl_backup_retention() {
    get_backup_retention "$BBCSDL_BACKUP_RETENTION_DEFAULT"
}

# A home-directory installation must not demand a sudo password to update, and a
# system-wide one must not fail for want of it, so the privilege decision is made
# per install directory: sudo only where the parent directory is not writable.
# Echoes "run_with_sudo" or nothing; callers expand it as a command prefix.
get_bbcsdl_privilege_prefix() {
    local install_dir="$1"
    local parent
    parent=$(dirname "$install_dir")

    if [ -w "$parent" ] && { [ ! -e "$install_dir" ] || [ -w "$install_dir" ]; }; then
        printf '%s' ""
    else
        printf '%s' "run_with_sudo"
    fi
}

# Move the current installation aside. Sets BBCSDL_BACKUP_DIR for the restore
# path.
backup_bbcsdl() {
    local install_dir="$1"
    local -a privileged=()
    local prefix
    prefix=$(get_bbcsdl_privilege_prefix "$install_dir")
    [ -n "$prefix" ] && privileged=("$prefix")

    print_status "$(get_config "messages.backing_up")"

    local backup_dir
    backup_dir="${install_dir}.backup.$(date +%Y%m%d_%H%M%S)"

    if ! "${privileged[@]}" mv "$install_dir" "$backup_dir"; then
        print_error "Failed to back up the existing BBC BASIC for SDL 2.0 installation"
        return 1
    fi

    BBCSDL_BACKUP_DIR="$backup_dir"
    print_success "Backed up to $backup_dir"
    return 0
}

# Put the previous installation back after a failed install.
restore_bbcsdl_backup() {
    local install_dir="$1"

    if [ -z "$BBCSDL_BACKUP_DIR" ] || [ ! -d "$BBCSDL_BACKUP_DIR" ]; then
        return 0
    fi

    local -a privileged=()
    local prefix
    prefix=$(get_bbcsdl_privilege_prefix "$install_dir")
    [ -n "$prefix" ] && privileged=("$prefix")

    print_warning "Restoring the previous BBC BASIC for SDL 2.0 installation..."
    "${privileged[@]}" rm -rf -- "$install_dir"
    if "${privileged[@]}" mv "$BBCSDL_BACKUP_DIR" "$install_dir"; then
        print_success "Restored $install_dir from $BBCSDL_BACKUP_DIR"
        BBCSDL_BACKUP_DIR=""
    else
        print_error "Failed to restore from $BBCSDL_BACKUP_DIR — it is still on disk"
    fi
}

# Keep only the newest N backups this snippet has left behind.
#
# Call only after an update has been verified, never on the restore path where
# the backup is still the installation.
prune_bbcsdl_backups() {
    local install_dir="$1"
    local keep_path="${2:-}"

    prune_timestamped_backups \
        "${install_dir}.backup." \
        "dir" \
        "$(get_bbcsdl_backup_retention)" \
        "BBC BASIC for SDL 2.0" \
        "$keep_path" \
        "$(get_bbcsdl_privilege_prefix "$install_dir")"
}

# Download and unpack the archive into a staging directory, and return that
# directory's path on stdout.
stage_bbcsdl_archive() {
    local download_url="$1"

    local temp_file
    temp_file=$(mktemp "/tmp/bbcsdl-update-XXXXXX.zip") || return 1

    local downloading_msg
    downloading_msg=$(get_config "messages.downloading")
    print_status "${downloading_msg/\{version\}/$LATEST_VERSION}" >&2

    if ! download_with_progress "$download_url" "$temp_file" >&2; then
        print_error "Failed to download the BBC BASIC for SDL 2.0 archive" >&2
        rm -f "$temp_file"
        return 1
    fi

    local staging_dir
    staging_dir=$(mktemp -d "/tmp/bbcsdl-stage-XXXXXX") || { rm -f "$temp_file"; return 1; }

    print_status "$(get_config "messages.extracting")" >&2
    if ! unzip -q -o "$temp_file" -d "$staging_dir" >&2; then
        print_error "Failed to extract the BBC BASIC for SDL 2.0 archive" >&2
        rm -f "$temp_file"
        rm -rf "$staging_dir"
        return 1
    fi

    rm -f "$temp_file"

    # The archive unpacks flat, but tolerate a future build that wraps
    # everything in a single top-level directory.
    if [ ! -f "$staging_dir/bbcsdl" ]; then
        local inner
        inner=$(find "$staging_dir" -maxdepth 2 -type f -name bbcsdl -print -quit 2>/dev/null)
        if [ -n "$inner" ]; then
            staging_dir=$(dirname "$inner")
        else
            print_error "The downloaded archive does not contain a bbcsdl executable" >&2
            rm -rf "$staging_dir"
            return 1
        fi
    fi

    printf '%s' "$staging_dir"
}

# Refuse to install an archive that is not actually an upgrade.
#
# The download URL is a fixed "current edition" path, not a versioned one, so
# the file behind it and the version the changelog announces are refreshed
# independently. For a window after a release the zip can still be the previous
# build. Installing it anyway would spend a backup generation to reinstall what
# is already there, and the post-update verification would then fail for a
# reason that has nothing to do with the install.
verify_staged_bbcsdl_version() {
    local staging_dir="$1"

    local staged_version
    staged_version=$(get_current_bbcsdl_version "$staging_dir/bbcsdl")

    if [ -z "$staged_version" ]; then
        print_error "Could not read the version of the downloaded BBC BASIC for SDL 2.0 build"
        return 1
    fi

    print_status "Downloaded build reports version: $staged_version"

    compare_versions "$staged_version" "$CURRENT_VERSION"
    local cmp_result=$?
    if [ "$cmp_result" -ne 1 ]; then
        print_error "The published archive is still $staged_version, not newer than the installed $CURRENT_VERSION"
        print_error "The vendor announced $LATEST_VERSION but has not refreshed the download yet — try again later"
        return 1
    fi

    if [ "$staged_version" != "$LATEST_VERSION" ]; then
        print_warning "The archive contains $staged_version, while the vendor announced $LATEST_VERSION"
    fi

    return 0
}

# Move the staged tree into place and mark the archive's executables runnable.
install_staged_bbcsdl() {
    local staging_dir="$1"
    local install_dir="$2"

    local -a privileged=()
    local prefix
    prefix=$(get_bbcsdl_privilege_prefix "$install_dir")
    [ -n "$prefix" ] && privileged=("$prefix")

    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "${installing_msg/\{path\}/$install_dir}"

    if ! "${privileged[@]}" mv "$staging_dir" "$install_dir"; then
        print_error "Failed to install the new BBC BASIC for SDL 2.0 tree to $install_dir"
        return 1
    fi

    # mktemp -d creates the staging directory 0700; the installation has to be
    # readable by whoever runs bbcsdl, which for a system-wide install is not
    # the user running the update.
    "${privileged[@]}" chmod 0755 "$install_dir" || \
        print_warning "Failed to set permissions on $install_dir"

    local executables
    executables=$(get_config "update.executables")
    local executable
    for executable in $executables; do
        if [ -f "$install_dir/$executable" ]; then
            "${privileged[@]}" chmod +x "$install_dir/$executable" || \
                print_warning "Failed to mark $install_dir/$executable executable"
        fi
    done

    return 0
}

perform_bbcsdl_update() {
    if ! command -v unzip &>/dev/null; then
        print_error "$(get_config "messages.missing_unzip")"
        return 1
    fi

    local download_url
    if ! download_url=$(get_bbcsdl_asset_url); then
        print_error "$(get_config "messages.unsupported_arch")"
        return 1
    fi

    local staging_dir
    if ! staging_dir=$(stage_bbcsdl_archive "$download_url"); then
        return 1
    fi

    if ! verify_staged_bbcsdl_version "$staging_dir"; then
        rm -rf "$staging_dir"
        return 1
    fi

    if ! backup_bbcsdl "$BBCSDL_INSTALL_DIR"; then
        rm -rf "$staging_dir"
        return 1
    fi

    if ! install_staged_bbcsdl "$staging_dir" "$BBCSDL_INSTALL_DIR"; then
        rm -rf "$staging_dir"
        restore_bbcsdl_backup "$BBCSDL_INSTALL_DIR"
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.update_success")
    if ! verify_configured_bbcsdl_result "${success_msg/\{version\}/$LATEST_VERSION}"; then
        restore_bbcsdl_backup "$BBCSDL_INSTALL_DIR"
        return 1
    fi

    prune_bbcsdl_backups "$BBCSDL_INSTALL_DIR" "$BBCSDL_BACKUP_DIR"
    return 0
}

# Re-read the version from the installed executable and emit the closing
# summary event. upgrade_utils' verify_configured_update_result is not reusable
# here: it re-runs version.command, and this snippet has none.
verify_configured_bbcsdl_result() {
    local success_msg="$1"

    local installed_version
    installed_version=$(get_current_bbcsdl_version "$BBCSDL_INSTALL_DIR/bbcsdl")

    if [ -z "$installed_version" ]; then
        print_error "Failed to verify the active $APP_DISPLAY_NAME version after update"
        return 1
    fi

    print_status "Verified version: $installed_version"

    compare_versions "$installed_version" "$CURRENT_VERSION"
    if [ $? -ne 1 ]; then
        print_error "$APP_DISPLAY_NAME version did not advance: still $installed_version"
        return 1
    fi

    emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
        "status" "up_to_date" "current_version" "$installed_version" \
        "latest_version" "$installed_version"

    print_success "$success_msg"
    show_installation_info "bbcsdl" "$APP_DISPLAY_NAME"
    return 0
}

#=============================================================================
# ENTRY POINT
#=============================================================================

update_bbcsdl() {
    APP_DISPLAY_NAME=$(get_config "application.display_name")

    print_operation_header "$(get_config "messages.checking_updates")"

    if ! command -v bbcsdl &>/dev/null; then
        print_warning "$APP_DISPLAY_NAME is not installed"
        echo -e "$(get_config "messages.install_help")"
        ask_continue
        return 0
    fi

    local binary
    if ! binary=$(resolve_bbcsdl_binary); then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
            "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_binary")"
        ask_continue
        return 1
    fi

    if ! BBCSDL_INSTALL_DIR=$(get_bbcsdl_install_dir "$binary"); then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
            "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_install_dir")"
        print_error "  ↳ $(dirname "$binary") does not look like a BBC BASIC installation"
        ask_continue
        return 1
    fi

    if ! CURRENT_VERSION=$(get_current_bbcsdl_version "$binary"); then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
            "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_version")"
        print_error "  ↳ no version banner found in $binary"
        ask_continue
        return 1
    fi

    if ! LATEST_VERSION=$(get_latest_bbcsdl_version); then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" \
            "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_latest_version")"
        ask_continue
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_bbcsdl_update"; then
        ask_continue
        return 1
    fi

    return 0
}

update_bbcsdl
