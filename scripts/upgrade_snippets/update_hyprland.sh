#!/bin/bash
#
# update_hyprland.sh - Hyprland Update Manager
# SNIPPET_ID: hyprland
# SNIPPET_NAME: Hyprland Wayland Compositor
#
# Handles version checking and updates for Hyprland wayland compositor.
# Reference: https://github.com/hyprwm/Hyprland
#
# Version: 1.0.0-alpha
# Date: 2025-12-14
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-12-14) - Initial version following upgrade script pattern v1.2.0
#                            - Uses Method 3: Custom Update Logic
#                            - Supports both source build and git pull update
#
# Dependencies:
#   - git
#   - gcc/clang
#   - cmake >= 3.19
#   - ninja
#   - pkg-config
#   - wayland-protocols
#   - wayland
#   - libxkbcommon
#   - libglvnd (OpenGL)
#   - cairo
#   - pango
#   - pixman
#   - libdrm
#   - hyprland-protocols (build dependency)
#   - aquamarine (build dependency)
#

# Load upgrade utilities library
HYPRLAND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$HYPRLAND_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$HYPRLAND_SCRIPT_DIR/hyprland.yaml"

# Build Hyprland from source
build_hyprland_from_source() {
    local version=$1
    local build_dir
    
    local building_msg
    building_msg=$(get_config "messages.build.building")
    building_msg="${building_msg/\{version\}/$version}"
    print_status "$building_msg"
    
    # Check for required build dependencies
    if ! check_build_dependencies git cmake ninja pkg-config make; then
        local install_deps
        install_deps=$(get_config "messages.build.install_deps")
        print_status "$install_deps"
        return 1
    fi
    
    # Check for compiler
    if ! command -v g++ &> /dev/null && ! command -v clang++ &> /dev/null; then
        local missing_compiler
        missing_compiler=$(get_config "messages.build.missing_compiler")
        print_error "$missing_compiler"
        local install_compiler
        install_compiler=$(get_config "messages.build.install_compiler")
        print_status "$install_compiler"
        return 1
    fi
    
    # Create build directory
    build_dir=$(create_build_directory "hyprland")
    local original_dir
    original_dir=$(pwd)
    cd "$build_dir" || return 1
    
    # Clone repository
    local cloning_msg
    cloning_msg=$(get_config "messages.build.cloning")
    print_status "$cloning_msg"
    local clone_url
    clone_url=$(get_config "messages.build.clone_url")
    if ! git clone --recursive "$clone_url"; then
        local clone_failed
        clone_failed=$(get_config "messages.build.clone_failed")
        print_error "$clone_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    cd Hyprland || return 1
    
    # Checkout specific version if provided
    if [ -n "$version" ]; then
        local checkout_msg
        checkout_msg=$(get_config "messages.build.checkout_version")
        checkout_msg="${checkout_msg/\{version\}/$version}"
        print_status "$checkout_msg"
        
        # Try with 'v' prefix first (GitHub tags format), then without
        local git_tag="v$version"
        if ! git checkout "$git_tag" 2>/dev/null; then
            if ! git checkout "$version" 2>/dev/null; then
                local checkout_failed
                checkout_failed=$(get_config "messages.build.checkout_failed")
                checkout_failed="${checkout_failed/\{version\}/$version}"
                print_warning "$checkout_failed"
            fi
        fi
    fi
    
    # Update submodules
    local submodule_msg
    submodule_msg=$(get_config "messages.build.updating_submodules")
    print_status "$submodule_msg"
    if ! git submodule update --init --recursive; then
        local submodule_failed
        submodule_failed=$(get_config "messages.build.submodule_failed")
        print_error "$submodule_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Build process with GCC compatibility flags
    local make_msg
    make_msg=$(get_config "messages.build.building_make")
    print_status "$make_msg"
    if ! CXXFLAGS="-Wno-error=unused-result" make all; then
        local make_failed
        make_failed=$(get_config "messages.build.make_failed")
        print_error "$make_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    local installing_msg
    installing_msg=$(get_config "messages.build.installing")
    print_status "$installing_msg"
    if ! sudo make install; then
        local install_failed
        install_failed=$(get_config "messages.build.install_failed")
        print_error "$install_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Cleanup
    cleanup_build_directory "$build_dir" "$original_dir"
    
    local success_msg
    success_msg=$(get_config "messages.build.build_success")
    print_success "$success_msg"
    show_installation_info "Hyprland" "Hyprland"
    
    return 0
}

# Update existing Hyprland git installation
update_hyprland_git() {
    local version=$1
    local hyprland_src
    
    # Try common locations for Hyprland source
    for loc in "$HOME/Hyprland" "$HOME/.local/src/Hyprland" "/opt/Hyprland"; do
        if [ -d "$loc/.git" ]; then
            hyprland_src="$loc"
            break
        fi
    done
    
    if [ -z "$hyprland_src" ]; then
        local no_git
        no_git=$(get_config "messages.update.no_git_install")
        print_warning "$no_git"
        return 1
    fi
    
    local updating_msg
    updating_msg=$(get_config "messages.update.updating_git")
    updating_msg="${updating_msg/\{path\}/$hyprland_src}"
    print_status "$updating_msg"
    
    cd "$hyprland_src" || return 1
    
    # Fetch latest changes
    local fetching_msg
    fetching_msg=$(get_config "messages.update.fetching")
    print_status "$fetching_msg"
    if ! git fetch --all --tags; then
        local fetch_failed
        fetch_failed=$(get_config "messages.update.fetch_failed")
        print_error "$fetch_failed"
        return 1
    fi
    
    # Checkout and pull
    if [ -n "$version" ]; then
        local checkout_msg
        checkout_msg=$(get_config "messages.update.checkout_version")
        checkout_msg="${checkout_msg/\{version\}/$version}"
        print_status "$checkout_msg"
        
        # Try with 'v' prefix first (GitHub tags format), then without
        local git_tag="v$version"
        if ! git checkout "$git_tag" 2>/dev/null; then
            if ! git checkout "$version" 2>/dev/null; then
                local checkout_failed
                checkout_failed=$(get_config "messages.update.checkout_failed")
                print_error "$checkout_failed"
                return 1
            fi
        fi
    else
        local pulling_msg
        pulling_msg=$(get_config "messages.update.pulling")
        print_status "$pulling_msg"
        if ! git pull; then
            local pull_failed
            pull_failed=$(get_config "messages.update.pull_failed")
            print_error "$pull_failed"
            return 1
        fi
    fi
    
    # Update submodules
    local submodule_msg
    submodule_msg=$(get_config "messages.build.updating_submodules")
    print_status "$submodule_msg"
    if ! git submodule update --init --recursive; then
        local submodule_failed
        submodule_failed=$(get_config "messages.build.submodule_failed")
        print_error "$submodule_failed"
        return 1
    fi
    
    # Rebuild with GCC compatibility flags
    local make_msg
    make_msg=$(get_config "messages.build.building_make")
    print_status "$make_msg"
    if ! CXXFLAGS="-Wno-error=unused-result" make all; then
        local make_failed
        make_failed=$(get_config "messages.build.make_failed")
        print_error "$make_failed"
        return 1
    fi
    
    local installing_msg
    installing_msg=$(get_config "messages.build.installing")
    print_status "$installing_msg"
    if ! sudo make install; then
        local install_failed
        install_failed=$(get_config "messages.build.install_failed")
        print_error "$install_failed"
        return 1
    fi
    
    local success_msg
    success_msg=$(get_config "messages.update.update_success")
    print_success "$success_msg"
    show_installation_info "Hyprland" "Hyprland"
    
    return 0
}

# Perform Hyprland update with method selection
perform_hyprland_update() {
    local latest_version="$1"
    
    # Read prompts from config
    local prompt_msg
    local prompt_opts
    local prompt_default
    prompt_msg=$(get_config "prompts.update_method.message")
    prompt_opts=$(get_config "prompts.update_method.options")
    prompt_default=$(get_config "prompts.update_method.default")
    
    # Ask for update method
    local method
    method=$(prompt_choice "$prompt_msg" "$prompt_opts" "$prompt_default")
    
    if [[ "$method" =~ ^[Ss]$ ]]; then
        # Fresh source build
        build_hyprland_from_source "$latest_version"
    elif [[ "$method" =~ ^[Gg]$ ]]; then
        # Update existing git installation
        if ! update_hyprland_git "$latest_version"; then
            # Fallback to fresh build
            local fallback_msg
            fallback_msg=$(get_config "messages.update.fallback_to_build")
            print_status "$fallback_msg"
            if prompt_yes_no "Build from source?"; then
                build_hyprland_from_source "$latest_version"
            fi
        fi
    else
        # Package manager update
        local current_before_update="$CURRENT_VERSION"
        if update_via_package_manager "hyprland" "start-hyprland"; then
            # Check if version actually changed
            local current_after_update
            local version_cmd
            version_cmd=$(get_config "version.command")
            local version_regex
            version_regex=$(get_config "version.regex")
            current_after_update=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
            
            if [ "$current_after_update" != "$current_before_update" ]; then
                print_success "🎯 Hyprland updated via package manager: $current_before_update → $current_after_update"
                show_installation_info "Hyprland" "Hyprland"
            else
                # Package manager didn't upgrade to latest version
                print_warning "⚠️ Package manager has Hyprland but not the latest version ($latest_version)"
                local build_prompt
                build_prompt=$(get_config "prompts.build_from_source.message")
                if prompt_yes_no "$build_prompt"; then
                    build_hyprland_from_source "$latest_version"
                else
                    # Display build instructions from config
                    print_status "ℹ️ Build from source instructions:"
                    
                    # Get dependencies list
                    local deps
                    deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | tr '\n' ', ' | sed 's/, $//')
                    print_status "1️⃣ Install dependencies: $deps"
                    
                    # Get build steps
                    local clone_cmd
                    clone_cmd=$(get_config "build_instructions.steps[0].command")
                    print_status "2️⃣ Clone: $clone_cmd"
                    
                    local build_cmd
                    build_cmd=$(get_config "build_instructions.steps[1].command")
                    print_status "3️⃣ Build: $build_cmd"
                    
                    local install_cmd
                    install_cmd=$(get_config "build_instructions.steps[2].command")
                    print_status "4️⃣ Install: $install_cmd"
                    
                    local ref_url
                    ref_url=$(get_config "build_instructions.reference.url")
                    print_status "📖 Reference: $ref_url"
                fi
            fi
        else
            # No package manager found, offer source build
            local build_prompt
            build_prompt=$(get_config "prompts.build_from_source.message")
            if prompt_yes_no "$build_prompt"; then
                build_hyprland_from_source "$latest_version"
            else
                # Display build instructions from config
                print_status "ℹ️ Build from source instructions:"
                
                # Get dependencies list
                local deps
                deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | tr '\n' ', ' | sed 's/, $//')
                print_status "1️⃣ Install dependencies: $deps"
                
                # Get build steps
                local clone_cmd
                clone_cmd=$(get_config "build_instructions.steps[0].command")
                print_status "2️⃣ Clone: $clone_cmd"
                
                local build_cmd
                build_cmd=$(get_config "build_instructions.steps[1].command")
                print_status "3️⃣ Build: $build_cmd"
                
                local install_cmd
                install_cmd=$(get_config "build_instructions.steps[2].command")
                print_status "4️⃣ Install: $install_cmd"
                
                local ref_url
                ref_url=$(get_config "build_instructions.reference.url")
                print_status "📖 Reference: $ref_url"
            fi
        fi
    fi
}

#=============================================================================
# update-alternatives-aware update path
#
# When Hyprland is managed by an update-alternatives group (the two-install
# setup from scripts/setup-hyprland-alternatives.sh: apt /usr/bin/Hyprland +
# upstream /opt/hyprland behind a /usr/local/bin generic link), an update must
# refresh the UPSTREAM candidate in place at its isolated prefix — never the apt
# candidate, and never a /usr/local source build (that is what broke Hyprland
# before; see docs/hyprland-status.md). We delegate the rebuild to the same
# setup script so the isolated-prefix + RPATH logic stays single-sourced.
#=============================================================================

# Is Hyprland currently managed by an update-alternatives group?
hyprland_is_alternatives_managed() {
    command -v update-alternatives >/dev/null 2>&1 || return 1
    update-alternatives --query Hyprland >/dev/null 2>&1
}

# Print the currently active alternative value (resolved binary), or "".
hyprland_alt_active_value() {
    update-alternatives --query Hyprland 2>/dev/null | awk '/^Value: /{print $2}'
}

# Print the upstream (non-apt) alternative target path, or "".
# Prefers the /opt/hyprland layout; falls back to any non-/usr/bin candidate.
hyprland_alt_upstream_target() {
    local candidates
    candidates=$(update-alternatives --query Hyprland 2>/dev/null \
                   | awk '/^Alternative: /{print $2}' \
                   | grep -v '^/usr/bin/Hyprland$')
    printf '%s\n' "$candidates" | grep '/opt/hyprland/bin/Hyprland$' | head -1 && return 0
    printf '%s\n' "$candidates" | grep -v '^$' | head -1
}

# Update the upstream Hyprland build behind update-alternatives by rebuilding it
# at the latest release into its isolated prefix (via setup-hyprland-alternatives.sh),
# then make it the active selection.
perform_hyprland_alternatives_update() {
    local latest_version="$1"

    local target
    target=$(hyprland_alt_upstream_target)
    if [ -z "$target" ]; then
        print_error "Could not resolve the upstream Hyprland target from update-alternatives"
        return 1
    fi

    local setup_script="$HYPRLAND_SCRIPT_DIR/../setup-hyprland-alternatives.sh"
    if [ ! -f "$setup_script" ]; then
        print_error "Setup script not found: $setup_script"
        return 1
    fi

    # The rebuild writes under /opt and update-alternatives needs root. Bail early
    # in a non-interactive context with no cached credentials so the UI can prompt.
    if ! sudo_can_run; then
        emit_sudo_required_event "bash setup-hyprland-alternatives.sh --ref v$latest_version" "false"
        print_error "Sudo credentials required to rebuild the upstream Hyprland at /opt/hyprland"
        print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
        return 1
    fi

    local output_lines
    output_lines=$(get_config "update.output_lines")
    output_lines="${output_lines:-40}"

    local ref="v$latest_version"
    print_status "Rebuilding upstream Hyprland ($ref) into the isolated /opt prefix via setup-hyprland-alternatives.sh..."
    local out rc
    out=$(run_with_sudo bash "$setup_script" --ref "$ref" 2>&1)
    rc=$?
    emit_captured_output "$out" "$output_lines"
    if [ "$rc" -ne 0 ]; then
        print_error "Upstream Hyprland rebuild failed"
        return 1
    fi

    # Make the freshly-rebuilt upstream active if it isn't (e.g. apt was selected).
    local active
    active=$(hyprland_alt_active_value)
    if [ "$active" != "$target" ]; then
        print_status "Switching active Hyprland to the updated upstream build..."
        run_with_sudo update-alternatives --set Hyprland "$target" >/dev/null 2>&1 || \
            print_warning "Could not switch the active Hyprland selection to $target"
    fi

    hash -r 2>/dev/null || true

    local success_msg
    success_msg=$(get_config "messages.update.update_success")
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "${success_msg:-Hyprland update completed}"
}

# Update Hyprland wayland compositor
# Uses Method 3: Custom Update Logic (see upgrade_script_pattern_documentation.md)
update_hyprland() {
    # Perform config-driven version check
    if ! config_driven_version_check; then
        # If Hyprland is installed but its version can't be read (a broken binary
        # — e.g. missing/incompatible shared libraries after a system upgrade), a
        # rebuild is exactly what repairs it. Offer one instead of just bailing.
        local app_cmd
        app_cmd=$(get_config "application.command")
        if command -v "${app_cmd:-Hyprland}" >/dev/null 2>&1; then
            print_warning "${APP_DISPLAY_NAME:-Hyprland} is installed but its version could not be read — the binary may be broken (e.g. missing shared libraries)."
            if [ "${CHECK_ONLY_MODE:-false}" = true ]; then
                print_status "Check-only mode - a rebuild (skipped here) would repair it"
                ask_continue
                return 0
            fi
            if prompt_yes_no "Rebuild/reinstall ${APP_DISPLAY_NAME:-Hyprland} to repair it?"; then
                local repair_version
                repair_version=$(get_github_latest_version \
                    "$(get_config version.github_owner)" "$(get_config version.github_repo)")
                # Under update-alternatives, repair the isolated /opt upstream build,
                # not a /usr/local source build.
                if hyprland_is_alternatives_managed; then
                    perform_hyprland_alternatives_update "$repair_version"
                else
                    perform_hyprland_update "$repair_version"
                fi
            fi
        fi
        ask_continue
        return 0
    fi

    # Handle update workflow. Under update-alternatives, refresh the isolated /opt
    # upstream candidate in place; otherwise fall back to the legacy method chooser.
    local update_callback="perform_hyprland_update '$LATEST_VERSION'"
    if hyprland_is_alternatives_managed; then
        update_callback="perform_hyprland_alternatives_update '$LATEST_VERSION'"
    fi
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "$update_callback"; then
        ask_continue
        return 1
    fi
}

update_hyprland
