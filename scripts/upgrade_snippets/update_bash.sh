#!/bin/bash
#
# update_bash.sh - Bash Shell Update Manager
# SNIPPET_ID: bash
# SNIPPET_NAME: Bash Shell
#
# Handles version checking and updates for bash shell.
# Reference: https://www.gnu.org/software/bash/
#
# Version: 1.1.0-alpha
# Date: 2025-11-27
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.1.0-alpha (2025-11-27) - Changed to Git repository source
#                            - Uses git://git.savannah.gnu.org/bash.git
#                            - Tag-based version detection
#   1.0.0-alpha (2025-11-27) - Aligned with upgrade script pattern v1.1.0
#                            - Uses Method 3: Custom Update Logic
#                            - Based on update_tmux.sh pattern
#                            - GNU FTP-based version detection
#
# Dependencies:
#   - git (version control)
#   - build-essential (gcc or clang)
#   - autoconf (configure script generation)
#   - bison (parser generator)
#   - libncurses-dev (terminal handling)
#   - texinfo (documentation generation)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/bash.yaml"

# Get latest bash version from Git repository tags
get_latest_bash_version() {
    local git_url
    git_url=$(get_config "version.git_url")
    
    # Fetch tags from repository and extract the latest version
    local latest_tag
    latest_tag=$(git ls-remote --tags "$git_url" | \
        grep -oP 'refs/tags/bash-\K[0-9]+\.[0-9]+(?=\^\{\}|$)' | \
        sort -V | tail -n1)
    
    if [ -z "$latest_tag" ]; then
        return 1
    fi
    
    echo "$latest_tag"
    return 0
}

build_bash_from_source() {
    local version=$1
    local build_dir
    local run_tests=${2:-false}
    
    local building_msg
    building_msg=$(get_config "messages.build.building")
    building_msg="${building_msg/\{version\}/$version}"
    print_status "$building_msg"
    
    # Check for required build dependencies
    if ! check_build_dependencies git make bison autoconf; then
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
    build_dir=$(create_build_directory "bash")
    local original_dir
    original_dir=$(pwd)
    cd "$build_dir" || return 1
    
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
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    cd bash || return 1
    
    # Checkout specific version if provided
    if [ -n "$version" ]; then
        local checkout_msg
        checkout_msg=$(get_config "messages.build.checkout_version")
        checkout_msg="${checkout_msg/\{version\}/$version}"
        print_status "$checkout_msg"
        if ! git checkout "bash-${version}" 2>/dev/null; then
            local checkout_failed
            checkout_failed=$(get_config "messages.build.checkout_failed")
            checkout_failed="${checkout_failed/\{version\}/$version}"
            print_warning "$checkout_failed"
        fi
    fi
    
    # Run autoconf to generate configure script
    local autoconf_msg
    autoconf_msg=$(get_config "messages.build.running_autoconf")
    print_status "$autoconf_msg"
    if ! autoconf; then
        local autoconf_failed
        autoconf_failed=$(get_config "messages.build.autoconf_failed")
        print_error "$autoconf_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Configure
    local configure_msg
    configure_msg=$(get_config "messages.build.running_configure")
    print_status "$configure_msg"
    if ! ./configure --prefix=/usr/local; then
        local configure_failed
        configure_failed=$(get_config "messages.build.configure_failed")
        print_error "$configure_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Build
    local make_msg
    make_msg=$(get_config "messages.build.building_make")
    print_status "$make_msg"
    if ! make; then
        local make_failed
        make_failed=$(get_config "messages.build.make_failed")
        print_error "$make_failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Run tests if requested
    if [ "$run_tests" = true ]; then
        local testing_msg
        testing_msg=$(get_config "messages.build.testing")
        print_status "$testing_msg"
        if ! make test; then
            local test_failed
            test_failed=$(get_config "messages.build.test_failed")
            print_warning "$test_failed"
        fi
    fi
    
    # Install
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
    
    local new_shell_info
    new_shell_info=$(get_config "messages.build.new_shell_info")
    print_status "$new_shell_info"
    
    show_installation_info "bash" "Bash Shell"
    
    return 0
}

# Perform bash update with method selection
perform_bash_update() {
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
        # Ask about running tests
        local test_prompt
        test_prompt=$(get_config "prompts.run_tests.message")
        local run_tests=false
        if prompt_yes_no "$test_prompt"; then
            run_tests=true
        fi
        build_bash_from_source "$latest_version" "$run_tests"
    else
        # Try package manager update
        if ! update_via_package_manager "bash"; then
            # No package manager found, offer source build
            local build_prompt
            build_prompt=$(get_config "prompts.build_from_source.message")
            if prompt_yes_no "$build_prompt"; then
                # Ask about running tests
                local test_prompt
                test_prompt=$(get_config "prompts.run_tests.message")
                local run_tests=false
                if prompt_yes_no "$test_prompt"; then
                    run_tests=true
                fi
                build_bash_from_source "$latest_version" "$run_tests"
            else
                # Display build instructions from config
                print_status "Build from source instructions:"
                
                # Get dependencies list
                local deps
                deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | tr '\n' ', ' | sed 's/, $//')
                print_status "1. Install dependencies: $deps"
                
                # Get build steps
                local step_num=2
                local num_steps
                num_steps=$(yq -r '.build_instructions.steps | length' "$CONFIG_FILE")
                for ((i=0; i<num_steps; i++)); do
                    local action
                    local command
                    action=$(yq -r ".build_instructions.steps[$i].action" "$CONFIG_FILE")
                    command=$(yq -r ".build_instructions.steps[$i].command" "$CONFIG_FILE")
                    command="${command/\{version\}/$latest_version}"
                    print_status "$step_num. $action: $command"
                    ((step_num++))
                done
                
                local ref_url
                ref_url=$(get_config "build_instructions.reference.git_url")
                print_status "Git repository: $ref_url"
            fi
        else
            print_success "bash updated via package manager"
            show_installation_info "bash" "Bash Shell"
        fi
    fi
}

# Custom version check for Git-based source
bash_version_check() {
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_status "$checking_msg"
    
    # Get current version
    local version_cmd
    local version_regex
    version_cmd=$(get_config "version.command")
    version_regex=$(get_config "version.regex")
    
    local current_version
    current_version=$(eval "$version_cmd" 2>/dev/null | grep -oP "$version_regex" | head -n1)
    
    if [ -z "$current_version" ]; then
        local failed_msg
        failed_msg=$(get_config "messages.failed_get_version")
        emit_summary_event "version_check" "target" "Bash Shell" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$failed_msg"
        return 1
    fi
    
    # Extract major.minor from version (e.g., 5.2.37 -> 5.2)
    local current_major_minor
    current_major_minor=$(echo "$current_version" | grep -oP '^[0-9]+\.[0-9]+')
    
    # Get latest version from Git tags
    local latest_version
    latest_version=$(get_latest_bash_version)
    
    if [ -z "$latest_version" ]; then
        emit_summary_event "version_check" "target" "Bash Shell" "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        print_error "Failed to fetch latest bash version from Git repository"
        return 1
    fi
    
    # Export for use by other functions
    export CURRENT_VERSION="$current_version"
    export LATEST_VERSION="$latest_version"
    export APP_DISPLAY_NAME="Bash Shell"
    
    # Compare versions and set numeric VERSION_STATUS
    # 0 = equal, 1 = current > latest, 2 = update available
    if [ "$current_major_minor" = "$latest_version" ]; then
        export VERSION_STATUS=0
        print_success "bash is up-to-date (v$current_version, latest branch: bash-$latest_version)"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version"
    else
        export VERSION_STATUS=2
        print_status "bash update available: v$current_version → bash-$latest_version"
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "update_available" "current_version" "$current_version" "latest_version" "$latest_version"
    fi
    
    return 0
}

# Update bash shell
# Uses Method 3: Custom Update Logic (see upgrade_script_pattern_documentation.md)
update_bash() {
    # Perform custom version check (Git-based)
    if ! bash_version_check; then
        ask_continue
        return 0
    fi
    
    # Skip if already up-to-date
    if [ "$VERSION_STATUS" -eq 0 ]; then
        ask_continue
        return 0
    fi
    
    # Handle update workflow with custom perform_bash_update logic
    local updating_msg
    updating_msg=$(get_config "messages.updating")
    local app_name
    app_name=$(get_config "application.name")
    
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "print_status '$updating_msg' && \
         perform_bash_update '$LATEST_VERSION' && \
         show_installation_info '$app_name' '$APP_DISPLAY_NAME'"; then
        ask_continue
        return 1
    fi
}

update_bash
