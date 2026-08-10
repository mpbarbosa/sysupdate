#!/bin/bash
#
# check_kitty_update.sh - Kitty terminal emulator update manager
# SNIPPET_ID: kitty
# SNIPPET_NAME: Kitty Terminal Emulator
#
# Handles version checking and updates for Kitty terminal.
# Reference: https://github.com/kovidgoyal/kitty
#
# Version: 0.2.0-alpha
# Date: 2026-08-10
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.2.0-alpha (2026-08-10) - update-alternatives-aware update path:
#                            - When kitty is managed by update-alternatives
#                              (two-install setup, see scripts/setup-kitty-alternatives.sh),
#                              refresh the UPSTREAM build in place at its alternative
#                              target (e.g. /opt/kitty.app) via the installer, then
#                              ensure that build is the active selection.
#                            - Removed the destructive `apt remove --purge kitty`
#                              post-step (it would delete the apt half of the
#                              alternatives group and leave a dangling entry).
#                            - Removed manual ~/.local/bin/kitty symlink creation
#                              (the generic alternatives link now owns that).
#                            - Legacy single-install setups still update via the
#                              upstream installer to ~/.local (no apt purge).
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

#=============================================================================
# update-alternatives helpers
#
# The recommended coexistence setup (scripts/setup-kitty-alternatives.sh) puts a
# `kitty` alternatives group behind a generic link (default /usr/local/bin/kitty),
# with the apt build (/usr/bin/kitty) and the upstream build (/opt/kitty.app/bin/kitty)
# as the two candidates and `kitten` slaved to it. This snippet tracks the UPSTREAM
# build (version.source = github), so an update must refresh that specific candidate
# in place — not whatever happens to be active, and never the apt candidate.
#=============================================================================

# Is kitty currently managed by an update-alternatives group?
kitty_is_alternatives_managed() {
    command -v update-alternatives >/dev/null 2>&1 || return 1
    update-alternatives --query kitty >/dev/null 2>&1
}

# Print the currently active alternative value (resolved binary), or "".
kitty_alt_active_value() {
    update-alternatives --query kitty 2>/dev/null | awk '/^Value: /{print $2}'
}

# Print the upstream (non-apt) alternative target path, or "".
# Prefers a kitty.app-layout candidate; falls back to any non-/usr/bin candidate.
kitty_alt_upstream_target() {
    local candidates
    candidates=$(update-alternatives --query kitty 2>/dev/null \
                   | awk '/^Alternative: /{print $2}' \
                   | grep -v '^/usr/bin/kitty$')
    printf '%s\n' "$candidates" | grep 'kitty\.app/bin/kitty$' | head -1 && return 0
    printf '%s\n' "$candidates" | grep -v '^$' | head -1
}

# Update the upstream kitty build behind update-alternatives, in place at its
# alternative target, then ensure it is the active selection.
perform_kitty_alternatives_update() {
    local target
    target=$(kitty_alt_upstream_target)
    if [ -z "$target" ]; then
        print_error "Could not resolve the upstream kitty target from update-alternatives"
        return 1
    fi

    # target = <dest>/kitty.app/bin/kitty  ->  app_root=<dest>/kitty.app, dest=<dest>
    local app_root dest
    app_root=$(dirname "$(dirname "$target")")
    dest=$(dirname "$app_root")

    # The installer writes under $dest and update-alternatives needs root. In a
    # non-interactive context with no cached credentials this can't succeed, so
    # bail before downloading and emit sudo.required so the UI can re-authenticate.
    if ! sudo_can_run; then
        emit_sudo_required_event "sh <kitty installer> dest=$dest" "false"
        print_error "Sudo credentials required to update the upstream kitty at $app_root"
        print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
        return 1
    fi

    local installer_url downloading_msg success_msg output_lines
    installer_url=$(get_config "update.installer_url")
    downloading_msg=$(get_config "messages.downloading_installer")
    success_msg=$(get_config "messages.update_success")
    output_lines=$(get_config "update.output_lines")
    output_lines="${output_lines:-20}"

    if [ -z "$installer_url" ]; then
        print_error "Installer update configuration is incomplete"
        return 1
    fi

    local installer_script
    installer_script=$(mktemp "/tmp/sysupdate-kitty-installer-XXXXXX.sh") || return 1

    print_status "$downloading_msg"
    local dl_out dl_rc
    dl_out=$(curl -fsSL "$installer_url" -o "$installer_script" 2>&1)
    dl_rc=$?
    emit_captured_output "$dl_out" "$output_lines"
    if [ "$dl_rc" -ne 0 ]; then
        rm -f "$installer_script"
        print_error "Failed to download the kitty installer"
        return 1
    fi

    # Refresh the upstream build in place. `dest=` installs to $dest/kitty.app and
    # `launch=n` keeps the installer from starting kitty afterwards.
    print_status "Installing upstream kitty into $app_root (dest=$dest)..."
    local inst_out inst_rc
    inst_out=$(run_with_sudo sh "$installer_script" "dest=$dest" launch=n 2>&1)
    inst_rc=$?
    rm -f "$installer_script"
    emit_captured_output "$inst_out" "$output_lines"
    if [ "$inst_rc" -ne 0 ]; then
        print_error "kitty installer failed"
        return 1
    fi

    # The alternative path is unchanged, so its entry still points at the refreshed
    # binary. If the upstream build is not the active selection (e.g. the user
    # switched to apt), make it active so the update actually takes effect.
    local active
    active=$(kitty_alt_active_value)
    if [ "$active" != "$target" ]; then
        print_status "Switching active kitty to the updated upstream build..."
        run_with_sudo update-alternatives --set kitty "$target" >/dev/null 2>&1 || \
            print_warning "Could not switch the active kitty selection to $target"
    fi

    hash -r 2>/dev/null || true
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

# Update Kitty terminal emulator
check_kitty_update() {
    # Perform config-driven version check (reads the active `kitty --version`,
    # which under alternatives is the selected build, vs the upstream github release).
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi

    if kitty_is_alternatives_managed; then
        # Two-install setup: refresh the upstream candidate in place, alternatives-aware.
        handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
            "perform_kitty_alternatives_update"
    else
        # Legacy single-install setup: update via the upstream installer (to ~/.local).
        handle_installer_script_update
    fi
}

check_kitty_update
