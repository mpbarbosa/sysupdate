#!/bin/bash
#
# update_tmux.sh - Tmux Update Manager
# SNIPPET_ID: tmux
# SNIPPET_NAME: tmux Terminal Multiplexer
#
# Handles version checking and updates for tmux terminal multiplexer.
# Reference: https://github.com/tmux/tmux
#
# Version: 1.1.0-alpha
# Date: 2025-11-25
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-25) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 3: Custom Update Logic
#                            - Simplified main function structure
#                            - Follows check_kitty_update.sh pattern
#   0.x.x (2025-11-24)     - Previous iterations with config extraction
#
# Dependencies:
#   - libevent 2.x (https://github.com/libevent/libevent/releases/latest)
#   - ncurses (https://invisible-mirror.net/archives/ncurses/)
#   - C compiler (gcc or clang)
#   - make, pkg-config, yacc/bison
#   - autoconf, automake (for building from source)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/tmux.yaml"

show_tmux_build_instructions() {
    print_status "Build from source instructions:"

    local deps
    deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | paste -sd ',' - | sed 's/,/, /g')
    print_status "1. Install dependencies: $deps"

    local clone_cmd
    clone_cmd=$(get_config "build_instructions.steps[0].command")
    print_status "2. Clone: $clone_cmd"

    local build_cmd
    build_cmd=$(get_config "build_instructions.steps[1].command")
    print_status "3. Build: $build_cmd"

    local install_cmd
    install_cmd=$(get_config "build_instructions.steps[2].command")
    print_status "4. Install: $install_cmd"

    local ref_url
    ref_url=$(get_config "build_instructions.reference.url")
    print_status "Reference: $ref_url"
}

offer_tmux_source_build() {
    local latest_version="$1"
    local build_prompt
    build_prompt=$(get_config "prompts.build_from_source.message")

    if prompt_yes_no "$build_prompt"; then
        build_tmux_from_source "$latest_version"
    else
        show_tmux_build_instructions
        return 0
    fi
}

verify_tmux_package_manager_update() {
    local current_before_update="$1"
    local latest_version="$2"
    local current_after_update

    current_after_update=$(get_current_version_from_config)
    if [ -z "$current_after_update" ]; then
        print_error "Failed to verify active tmux version after package manager update"
        return 1
    fi

    print_status "Verified version: $current_after_update"

    if [ "$current_after_update" = "$current_before_update" ]; then
        print_warning "Package manager did not change the active tmux version"
        return 2
    fi

    compare_versions "$current_after_update" "$latest_version"
    local version_cmp=$?

    if [ $version_cmp -eq 2 ]; then
        print_warning "Package manager updated tmux to $current_after_update, but latest release is $latest_version"
        emit_summary_event "version_check" "target" "tmux" "status" "update_available" "current_version" "$current_after_update" "latest_version" "$latest_version"
        return 2
    fi

    if [ $version_cmp -eq 1 ]; then
        print_success "tmux updated via package manager: $current_before_update → $current_after_update"
        print_status "Active tmux version is newer than the latest tagged release"
        emit_summary_event "version_check" "target" "tmux" "status" "ahead_of_latest" "current_version" "$current_after_update" "latest_version" "$latest_version"
    else
        print_success "tmux updated via package manager: $current_before_update → $current_after_update"
        emit_summary_event "version_check" "target" "tmux" "status" "up_to_date" "current_version" "$current_after_update" "latest_version" "$latest_version"
    fi

    show_installation_info "tmux" "tmux"
    return 0
}

build_tmux_from_source() {
    local version=$1
    local build_dir
    local original_dir

    local building_msg
    building_msg=$(get_config "messages.build.building")
    building_msg="${building_msg/\{version\}/$version}"
    print_status "$building_msg"
    
    # Check for required build dependencies
    if ! check_build_dependencies git make pkg-config autoconf automake; then
        local install_deps
        install_deps=$(get_config "messages.build.install_deps")
        print_status "$install_deps"
        return 1
    fi
    
    # Check for compiler
    if ! command -v gcc &> /dev/null && ! command -v clang &> /dev/null; then
        local missing_compiler
        missing_compiler=$(get_config "messages.build.missing_compiler")
        print_error "$missing_compiler"
        local install_compiler
        install_compiler=$(get_config "messages.build.install_compiler")
        print_status "$install_compiler"
        return 1
    fi
    
    # Create build directory
    build_dir=$(create_build_directory "tmux")
    original_dir=$(pwd)
    (
        cd "$build_dir" || exit 1

        # Clone repository
        local cloning_msg
        cloning_msg=$(get_config "messages.build.cloning")
        print_status "$cloning_msg"
        local clone_url
        clone_url=$(get_config "messages.build.clone_url")
        if ! git clone "$clone_url"; then
            local clone_failed
            clone_failed=$(get_config "messages.build.clone_failed")
            print_error "$clone_failed"
            exit 1
        fi

        cd tmux || exit 1

        # Checkout specific version if provided
        if [ -n "$version" ]; then
            local checkout_msg
            checkout_msg=$(get_config "messages.build.checkout_version")
            checkout_msg="${checkout_msg/\{version\}/$version}"
            print_status "$checkout_msg"
            if ! git checkout "$version" 2>/dev/null; then
                local checkout_failed
                checkout_failed=$(get_config "messages.build.checkout_failed")
                checkout_failed="${checkout_failed/\{version\}/$version}"
                print_warning "$checkout_failed"
            fi
        fi

        # Build process
        local autogen_msg
        autogen_msg=$(get_config "messages.build.running_autogen")
        print_status "$autogen_msg"
        if ! sh autogen.sh; then
            local autogen_failed
            autogen_failed=$(get_config "messages.build.autogen_failed")
            print_error "$autogen_failed"
            exit 1
        fi

        local configure_msg
        configure_msg=$(get_config "messages.build.running_configure")
        print_status "$configure_msg"
        if ! ./configure; then
            local configure_failed
            configure_failed=$(get_config "messages.build.configure_failed")
            print_error "$configure_failed"
            exit 1
        fi

        local make_msg
        make_msg=$(get_config "messages.build.building_make")
        print_status "$make_msg"
        if ! make; then
            local make_failed
            make_failed=$(get_config "messages.build.make_failed")
            print_error "$make_failed"
            exit 1
        fi

        local installing_msg
        installing_msg=$(get_config "messages.build.installing")
        print_status "$installing_msg"
        if ! run_with_sudo make install; then
            local install_failed
            install_failed=$(get_config "messages.build.install_failed")
            print_error "$install_failed"
            exit 1
        fi
    )
    local build_exit_code=$?
    cleanup_build_directory "$build_dir" "$original_dir"

    if [ $build_exit_code -ne 0 ]; then
        return 1
    fi

    local success_msg
    success_msg=$(get_config "messages.build.build_success")

    verify_configured_update_result "$CURRENT_VERSION" "$version" "$success_msg"
}

# Perform tmux update with method selection
perform_tmux_update() {
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
        build_tmux_from_source "$latest_version"
    else
        # Try package manager update
        local current_before_update="$CURRENT_VERSION"
        if update_via_package_manager "tmux" "tmux"; then
            verify_tmux_package_manager_update "$current_before_update" "$latest_version"
            local verify_status=$?
            if [ $verify_status -eq 2 ]; then
                offer_tmux_source_build "$latest_version"
            elif [ $verify_status -ne 0 ]; then
                return 1
            fi
        else
            print_warning "Package manager update failed"
            offer_tmux_source_build "$latest_version"
        fi
    fi
}

# Update tmux terminal multiplexer
# Uses Method 3: Custom Update Logic (see upgrade_script_pattern_documentation.md)
update_tmux() {
    # Perform config-driven version check
    if ! config_driven_version_check; then
        return 0
    fi

    local latest_version="${LATEST_VERSION:-}"

    # Handle update workflow with custom perform_tmux_update logic
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_tmux_update '$latest_version'"; then
        ask_continue
        return 1
    fi
}

update_tmux
