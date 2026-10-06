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
#   1.2.0-alpha (2026-10-06) - Version lookup survives an unreachable Savannah:
#                              git's connection errors are captured instead of
#                              leaking to the console, every probe is bounded by
#                              a timeout, https and the GNU release listing are
#                              tried as fallbacks, and a lookup that finds no
#                              source reports "unknown" with the reason rather
#                              than a bare failure
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

# Seconds any single remote probe may take. git.savannah.gnu.org has
# multi-day outages, and a connection to an unreachable host otherwise sits in
# TCP retries for minutes with the whole update run blocked behind it.
SYSUPDATE_BASH_REMOTE_TIMEOUT="${SYSUPDATE_BASH_REMOTE_TIMEOUT:-20}"

# Results of the last version lookup. These are set by functions that must NOT
# be called in a subshell (`$(...)` would discard the assignments) - hence the
# set-a-global style rather than echoing the version.
BASH_LATEST_VERSION=""
BASH_VERSION_LOOKUP_ERROR=""

# Run a command under `timeout` when the system has one. Some minimal
# containers do not ship coreutils' timeout; there we still run the probe, just
# unbounded, rather than failing the check outright.
run_bash_probe() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$SYSUPDATE_BASH_REMOTE_TIMEOUT" "$@"
        return $?
    fi
    "$@"
}

# First non-empty line of a captured stderr file, trimmed to one console line.
# git prints several lines per unreachable address ("errno=No route to host",
# one per A/AAAA record); the first carries the reason.
summarize_probe_error() {
    local stderr_file="$1"

    [ -s "$stderr_file" ] || return 0
    grep -m1 -E '[^[:space:]]' "$stderr_file" 2>/dev/null \
        | tr -d '\r' \
        | cut -c1-200
}

# Read bash-X.Y tags from one git remote.
# Args: <git-url>. Sets BASH_LATEST_VERSION on success, BASH_VERSION_LOOKUP_ERROR
# on failure; must not run in a subshell. Returns 1 if the remote did not answer.
#
# git writes connection failures to stderr, which otherwise land in the run's
# output as bare "git.savannah.gnu.org[0: ...]: errno=No route to host" lines -
# no context, and the dashboard console shows them with nothing naming bash.
# Capture them instead and let the caller report one summarised reason.
fetch_bash_version_from_git_remote() {
    local git_url="$1"
    local stderr_file tags rc reason

    [ -n "$git_url" ] || return 1

    stderr_file=$(mktemp "${TMPDIR:-/tmp}/bash-ls-remote-XXXXXX") || {
        BASH_VERSION_LOOKUP_ERROR="could not create a temporary file for the version probe"
        return 1
    }

    # GIT_TERMINAL_PROMPT=0: a remote that answers but asks for credentials must
    # not block a headless run on a prompt nobody is reading.
    tags=$(GIT_TERMINAL_PROMPT=0 run_bash_probe git ls-remote --tags "$git_url" 2>"$stderr_file")
    rc=$?
    reason=$(summarize_probe_error "$stderr_file")
    rm -f "$stderr_file"

    if [ "$rc" -ne 0 ] || [ -z "$tags" ]; then
        if [ "$rc" -eq 124 ]; then
            reason="$git_url did not answer within ${SYSUPDATE_BASH_REMOTE_TIMEOUT}s"
        fi
        BASH_VERSION_LOOKUP_ERROR="${reason:-git ls-remote $git_url failed (exit $rc)}"
        return 1
    fi

    BASH_LATEST_VERSION=$(printf '%s\n' "$tags" | \
        grep -oP 'refs/tags/bash-\K[0-9]+\.[0-9]+(?=\^\{\}|$)' | \
        sort -V | tail -n1)

    if [ -z "$BASH_LATEST_VERSION" ]; then
        BASH_VERSION_LOOKUP_ERROR="no bash-X.Y tags found at $git_url"
        return 1
    fi

    return 0
}

# Read the latest release series from the GNU release listing - a different
# host from Savannah, so it still answers while Savannah itself is down.
# Sets BASH_LATEST_VERSION / BASH_VERSION_LOOKUP_ERROR; no subshell.
fetch_bash_version_from_gnu_listing() {
    local listing_url version_pattern listing

    listing_url=$(get_config "version.release_listing_url")
    version_pattern=$(get_config "version.release_pattern")
    if [ -z "$listing_url" ] || [ -z "$version_pattern" ]; then
        return 1
    fi

    # --connect-timeout: a host that silently drops packets, as an unreachable
    # ftp.gnu.org does, otherwise burns the whole --max-time budget before the
    # run can move on. --tries=1 keeps wget from repeating that wait.
    if command -v curl >/dev/null 2>&1; then
        listing=$(curl -fsSL --connect-timeout 8 --max-time "$SYSUPDATE_BASH_REMOTE_TIMEOUT" "$listing_url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        listing=$(wget -qO- --tries=1 --timeout="$SYSUPDATE_BASH_REMOTE_TIMEOUT" --connect-timeout=8 "$listing_url" 2>/dev/null)
    else
        BASH_VERSION_LOOKUP_ERROR="neither curl nor wget is available to read $listing_url"
        return 1
    fi

    if [ -z "$listing" ]; then
        BASH_VERSION_LOOKUP_ERROR="$listing_url could not be reached"
        return 1
    fi

    BASH_LATEST_VERSION=$(printf '%s\n' "$listing" | \
        grep -oE "$version_pattern" | \
        sed -nE "s/$version_pattern/\1/p" | \
        sort -V | tail -n1)

    if [ -z "$BASH_LATEST_VERSION" ]; then
        BASH_VERSION_LOOKUP_ERROR="no bash releases matched at $listing_url"
        return 1
    fi

    return 0
}

# Resolve the latest bash release series (X.Y) from the first source that
# answers. Sets BASH_LATEST_VERSION, or BASH_VERSION_LOOKUP_ERROR with the last
# reason; must not run in a subshell. Returns 1 when no source answered.
#
# The sources are tried widest-reach last: the upstream git:// remote, the same
# repository over https (port 9418 is blocked on plenty of networks while 443 is
# not), then the GNU release listing on another host for when Savannah is down.
# All three report the same X.Y series, so which one answered does not change
# the verdict.
get_latest_bash_version() {
    local url

    BASH_LATEST_VERSION=""
    BASH_VERSION_LOOKUP_ERROR=""

    for url in "$(get_config "version.git_url")" "$(get_config "version.git_url_https")"; do
        [ -n "$url" ] || continue
        if fetch_bash_version_from_git_remote "$url"; then
            return 0
        fi
    done

    if fetch_bash_version_from_gnu_listing; then
        return 0
    fi

    return 1
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
    
    # Get latest version from the upstream repository (or its fallbacks). Not in
    # a subshell: the lookup reports back through globals.
    local latest_version=""
    if get_latest_bash_version; then
        latest_version="$BASH_LATEST_VERSION"
    fi

    # Nothing answered. That is a retryable network condition, not a verdict on
    # the installed bash, so report "unknown" with the reason and carry on with
    # the rest of the run rather than failing loudly.
    if [ -z "$latest_version" ]; then
        emit_summary_event "version_check" "target" "Bash Shell" "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        local unreachable_msg
        unreachable_msg=$(get_config "messages.version_sources_unreachable")
        print_warning "${unreachable_msg:-Could not determine the latest bash release}"
        [ -n "$BASH_VERSION_LOOKUP_ERROR" ] && print_status "Last attempt: $BASH_VERSION_LOOKUP_ERROR"
        print_status "Installed bash is v$current_version; the check will retry on the next run"
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
