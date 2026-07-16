#!/bin/bash
#
# upgrade_utils.sh - Common Utilities for Upgrade Snippets
#
# Provides reusable functions for version checking and application updates
# to avoid code duplication across upgrade snippet modules.
#
# Version: 1.2.0
# Date: 2025-11-29
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#
# Version History:
#   1.1.0 (2025-11-29) - Added apt package manager support
#                       - New function: get_apt_latest_version()
#                       - Added "apt" case in config_driven_version_check()
#   1.0.0 (2025-11-25) - Initial stable release
#

# Ensure core_lib.sh is loaded
if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi

#=============================================================================
# CONFIGURATION MANAGEMENT
#=============================================================================

# Read configuration values from YAML files using yq
# Usage: get_config "key.path" "config_file.yaml"
# Returns: configuration value
# Example: get_config "application.name" "$CONFIG_FILE"
get_config() {
    local key="$1"
    local config_file="${2:-$CONFIG_FILE}"
    local value
    
    if [ -z "$key" ]; then
        echo ""
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return 1
    fi

    value=$(yq -r ".$key" "$config_file" 2>/dev/null)
    if [ "$value" = "null" ]; then
        echo ""
        return 1
    fi

    echo "$value"
}

get_current_version_from_config() {
    local version_cmd
    version_cmd=$(get_config "version.command")
    local version_regex
    version_regex=$(get_config "version.regex")

    if [ -z "$version_cmd" ] || [ -z "$version_regex" ]; then
        echo ""
        return 1
    fi

    local version_output
    version_output=$(eval "$version_cmd" 2>/dev/null | head -1)
    local current_version
    current_version=$(extract_version "$version_output" "$version_regex")

    if [ -z "$current_version" ]; then
        echo ""
        return 1
    fi

    echo "$current_version"
}

# Config-driven application version check workflow
# Performs complete version check using configuration file
# Usage: config_driven_version_check
# Requires: CONFIG_FILE environment variable set
# Sets: CURRENT_VERSION, LATEST_VERSION, VERSION_STATUS, APP_DISPLAY_NAME
# Returns: 0 on success, 1 on failure
config_driven_version_check() {
    # Print operation header
    local checking_msg
    checking_msg=$(get_config "messages.checking_updates")
    print_operation_header "$checking_msg"
    
    # Check application installed
    local app_name
    app_name=$(get_config "application.name")
    local app_cmd
    app_cmd=$(get_config "application.command")
    local install_help
    install_help=$(get_config "messages.install_help")
    local app_command="${app_cmd:-$app_name}"

    APP_DISPLAY_NAME=$(get_config "application.display_name")
    if [ -z "$APP_DISPLAY_NAME" ]; then
        APP_DISPLAY_NAME="$app_name"
    fi

    if ! check_app_installed_or_help "$app_command" "$APP_DISPLAY_NAME" "$install_help"; then
        return 1
    fi
    
    # Get current version
    CURRENT_VERSION=$(get_current_version_from_config)
    
    if [ -z "$CURRENT_VERSION" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_version")
        if [ -z "$error_msg" ]; then
            error_msg=$(get_config "messages.failed_get_version")
        fi
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$error_msg"
        ask_continue
        return 1
    fi
    
    # Get latest version based on source
    local version_source
    version_source=$(get_config "version.source")
    
    case "$version_source" in
        "github")
            local github_owner
            github_owner=$(get_config "version.github_owner")
            local github_repo
            github_repo=$(get_config "version.github_repo")
            LATEST_VERSION=$(get_github_latest_version "$github_owner" "$github_repo")
            ;;
        "github_tags")
            local github_owner
            github_owner=$(get_config "version.github_owner")
            local github_repo
            github_repo=$(get_config "version.github_repo")
            LATEST_VERSION=$(get_github_latest_tag "$github_owner" "$github_repo")
            ;;
        "npm")
            local npm_package
            npm_package=$(get_config "application.npm_package")
            LATEST_VERSION=$(get_npm_latest_version "$npm_package" --verbose="${VERBOSE_MODE:-false}")
            ;;
        "apt")
            local package_name
            package_name=$(get_config "version.package_name")
            if [ -z "$package_name" ]; then
                package_name=$(get_config "application.name")
            fi
            LATEST_VERSION=$(get_apt_latest_version "$package_name" --verbose="${VERBOSE_MODE:-false}")
            ;;
        *)
            print_error "Unknown version source: $version_source"
            return 1
            ;;
    esac
    
    # Compare and report versions
    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?
    
    return 0
}

#=============================================================================
# GITHUB API FUNCTIONS
#=============================================================================

# Select the highest clean semantic version from a stream of git tag refs (or
# bare tag names) on stdin.
#
# Repos with a mixed-prefix tag namespace expose tags like
# "matchmaker-cli-v0.0.32", "matchmaker-lib-v0.0.28", and "v0.0.5" side by side.
# A naive `sed 's/^v//' | sort -V` lets a prefixed, non-semver string
# ("matchmaker-partial-v0.0.30") win the sort and leak out as a bogus "latest".
# To avoid that we extract only the trailing vX.Y[.Z...] from each tag and drop
# anything that doesn't reduce to a bare semver, so a non-semver tag can never
# win.
select_highest_semver_tag() {
    awk -F/ '{print $NF}' | \
        sed 's/\^{}$//' | \
        grep -oiE 'v?[0-9]+(\.[0-9]+)+$' | \
        sed 's/^[vV]//' | \
        sort -Vu | \
        tail -1
}

get_github_latest_remote_tag_fallback() {
    local owner="$1"
    local repo="$2"

    if [ -z "$owner" ] || [ -z "$repo" ] || ! command -v git &>/dev/null; then
        echo ""
        return 1
    fi

    git ls-remote --tags "https://github.com/$owner/$repo.git" 2>/dev/null | \
        select_highest_semver_tag
}

# Fetch latest version tag from GitHub releases
# Usage: get_github_latest_version "owner" "repo"
# Returns: version string (e.g., "3.4" or "0.0.361")
get_github_latest_version() {
    local owner="$1"
    local repo="$2"
    
    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo ""
        return 1
    fi
    
    local version
    version=$(curl -s "https://api.github.com/repos/$owner/$repo/releases/latest" | \
              grep '"tag_name"' | \
              sed -E 's/.*"([^"]+)".*/\1/' | \
              sed 's/^v//')

    if [ -z "$version" ]; then
        version=$(get_github_latest_remote_tag_fallback "$owner" "$repo")
    fi
    
    echo "$version"
}

# Fetch latest version from GitHub tags (when releases are not used)
# Usage: get_github_latest_tag "owner" "repo"
# Returns: version string from the first tag (e.g., "2.32.11")
get_github_latest_tag() {
    local owner="$1"
    local repo="$2"
    
    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo ""
        return 1
    fi
    
    local version
    version=$(curl -s "https://api.github.com/repos/$owner/$repo/tags" | \
              grep '"name"' | \
              head -1 | \
              sed -E 's/.*"([^"]+)".*/\1/' | \
              sed 's/^v//')

    if [ -z "$version" ]; then
        version=$(get_github_latest_remote_tag_fallback "$owner" "$repo")
    fi
    
    echo "$version"
}

# Fetch latest version from npm registry
# Usage: get_npm_latest_version "package-name"
# Returns: version string (e.g., "0.0.361")
get_npm_latest_version() {
    local package="$1"
    local verbose="${2:-false}"
    
    if [ -z "$package" ]; then
        echo ""
        return 1
    fi

    if [ "$verbose" = "true" ]; then
        print_status "Fetching npm latest version for package: $package"
    fi
    
    local version
    version=$(npm view "$package" version 2>/dev/null)
    if [ -z "$version" ]; then
        print_error "Failed to get latest version from npm"
        ask_continue
        return 1
    fi
    
    if [ "$verbose" = "true" ]; then
        print_status "Latest version for $package: $version"
    fi
    
    echo "$version"
}

# Fetch latest version from apt repository
# Usage: get_apt_latest_version "package-name"
# Returns: version string (e.g., "141.0.7390.76-1")
get_apt_latest_version() {
    local package="$1"
    local verbose="${2:-false}"
    
    if [ -z "$package" ]; then
        echo ""
        return 1
    fi

    if [ "$verbose" = "true" ]; then
        print_status "Fetching apt latest version for package: $package"
    fi
    
    local version
    version=$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}' | sed 's/-[^-]*$//')
    if [ -z "$version" ]; then
        print_error "Failed to get latest version from apt"
        return 1
    fi
    
    if [ "$verbose" = "true" ]; then
        print_status "Latest version for $package: $version"
    fi

    echo "$version"
}

#=============================================================================
# NPM HEALTH (detect + repair a corrupted global npm install)
#=============================================================================
#
# A partial npm self-update can leave the global npm with an internally
# inconsistent dependency tree (e.g. sibling packages requiring different
# `minipass` majors). `npm --version` still works, but anything that loads
# `cacache` crashes with "Class extends value ... is not a constructor or
# null". This corruption breaks every npm-based snippet, so detection and
# repair live here in the shared layer rather than in any one snippet.

# Pure matcher: does the given npm output show the dependency-tree corruption
# signature? Kept side-effect free so it is unit-testable from a fixture.
# Usage: npm_output_indicates_corruption "<captured npm stderr/stdout>"
# Returns: 0 if the signature is present, 1 otherwise
npm_output_indicates_corruption() {
    local text="$1"
    printf '%s' "$text" | grep -qiE 'Class extends value .* is not a constructor or null'
}

# Resolve the global node_modules directory that owns a given npm binary,
# deriving it from the binary path so it works even when npm itself is broken.
# Usage: npm_global_modules_dir "<npm_bin>"
# Returns: path to <prefix>/lib/node_modules, or empty on failure
npm_global_modules_dir() {
    local npm_bin="$1"
    local resolved

    if command -v "$npm_bin" >/dev/null 2>&1; then
        resolved=$(command -v "$npm_bin")
    else
        resolved="$npm_bin"
    fi
    resolved=$(readlink -f "$resolved" 2>/dev/null || echo "$resolved")

    # Symlink target is usually <prefix>/lib/node_modules/npm/bin/npm-cli.js
    case "$resolved" in
        */npm/bin/npm-cli.js)
            printf '%s\n' "${resolved%/npm/bin/npm-cli.js}"
            return 0
            ;;
    esac

    # Fallback: <bindir>/../lib/node_modules
    local cand
    cand="$(dirname "$resolved")/../lib/node_modules"
    if [ -d "$cand" ]; then
        (cd "$cand" && pwd)
        return 0
    fi

    # Last resort: ask npm (root -g does not load cacache, so it survives)
    "$npm_bin" root -g 2>/dev/null
}

# Functional health probe: runs a cacache-loading offline npm command and
# classifies the result.
# Usage: probe_npm_health "<npm_bin>"
# Returns: 0 healthy, 2 known corruption signature, 1 other/inconclusive failure
probe_npm_health() {
    local npm_bin="$1"
    local out
    out=$("$npm_bin" cache verify 2>&1)
    local code=$?

    if [ $code -eq 0 ]; then
        return 0
    fi
    if npm_output_indicates_corruption "$out"; then
        return 2
    fi
    return 1
}

# Repair a corrupted global npm by reinstalling npm@latest from the registry
# tarball directly (npm's documented manual bootstrap) — no working npm
# required, so it can heal an npm that cannot run `install` itself.
# Usage: repair_npm_install "<npm_bin>" "<use_sudo:true|false>"
# Returns: 0 on success, 1 on failure
repair_npm_install() {
    local npm_bin="$1"
    local use_sudo="${2:-false}"

    local gnm
    gnm=$(npm_global_modules_dir "$npm_bin")
    if [ -z "$gnm" ]; then
        print_error "Could not determine npm global modules directory"
        return 1
    fi

    local meta
    meta=$(curl -fsSL "https://registry.npmjs.org/npm/latest" 2>/dev/null)
    local tarball_url
    tarball_url=$(printf '%s' "$meta" | grep -oE '"tarball":"[^"]+"' | head -1 | sed -E 's/.*"tarball":"([^"]+)".*/\1/')
    if [ -z "$tarball_url" ]; then
        print_error "Could not resolve npm@latest tarball URL from the registry"
        return 1
    fi

    local tmp
    tmp=$(mktemp -d "/tmp/npm-heal-XXXXXX") || return 1

    if ! curl -fsSL "$tarball_url" -o "$tmp/npm.tgz"; then
        print_error "Failed to download npm tarball"
        rm -rf "$tmp"
        return 1
    fi
    if ! tar -xzf "$tmp/npm.tgz" -C "$tmp" || [ ! -d "$tmp/package" ]; then
        print_error "Failed to extract npm tarball"
        rm -rf "$tmp"
        return 1
    fi

    local -a sudo_pfx=()
    [ "$use_sudo" = "true" ] && sudo_pfx=(run_with_sudo)

    # Replace <gnm>/npm with the fresh, internally-consistent package, keeping
    # the old copy aside until the move succeeds so a failure can roll back.
    "${sudo_pfx[@]}" rm -rf "$gnm/npm.heal-old" 2>/dev/null
    if [ -d "$gnm/npm" ] && ! "${sudo_pfx[@]}" mv "$gnm/npm" "$gnm/npm.heal-old"; then
        print_error "Failed to move aside the broken npm install"
        rm -rf "$tmp"
        return 1
    fi
    if ! "${sudo_pfx[@]}" mv "$tmp/package" "$gnm/npm"; then
        print_error "Failed to install the fresh npm; rolling back"
        [ -d "$gnm/npm.heal-old" ] && "${sudo_pfx[@]}" mv "$gnm/npm.heal-old" "$gnm/npm"
        rm -rf "$tmp"
        return 1
    fi

    "${sudo_pfx[@]}" rm -rf "$gnm/npm.heal-old" 2>/dev/null
    rm -rf "$tmp"
    return 0
}

# Ensure the given npm is healthy before an npm-based snippet uses it; if the
# known corruption is detected, offer (prompt-gated) to repair it.
# Usage: ensure_npm_healthy [<npm_bin>] [--sudo]
#   <npm_bin>  npm to check (default: "npm" on PATH)
#   --sudo     use sudo for the repair writes (system /usr/local installs)
# Honors CHECK_ONLY_MODE (never repairs), QUIET_MODE (no prompt -> declines),
# and SYSUPDATE_NPM_AUTOHEAL=true (repairs without prompting).
# Returns: 0 if healthy or repaired, 1 if broken and not repaired
ensure_npm_healthy() {
    local npm_bin="npm"
    local use_sudo="false"

    while [ $# -gt 0 ]; do
        case "$1" in
            --sudo) use_sudo="true" ;;
            *)      npm_bin="$1" ;;
        esac
        shift
    done

    # Nothing to check if this npm is not present
    if ! command -v "$npm_bin" >/dev/null 2>&1 && [ ! -x "$npm_bin" ]; then
        return 0
    fi

    probe_npm_health "$npm_bin"
    local health=$?

    if [ "$health" -eq 0 ]; then
        return 0
    fi
    # Inconclusive / unrelated failure: do not claim corruption, let the
    # caller's own npm invocation surface whatever the real error is.
    if [ "$health" -ne 2 ]; then
        return 0
    fi

    print_warning "Detected a corrupted npm install ($npm_bin)"
    print_status  "Symptom: 'Class extends value ... is not a constructor or null' (mismatched dependency tree, e.g. minipass)"

    if [ "${CHECK_ONLY_MODE:-false}" = "true" ]; then
        print_status "Check-only mode - not repairing npm"
        return 1
    fi

    if [ "${SYSUPDATE_NPM_AUTOHEAL:-false}" != "true" ]; then
        if ! prompt_yes_no "Reinstall a clean npm@latest to repair it?"; then
            print_status "Skipping npm repair"
            return 1
        fi
    fi

    print_status "Repairing npm via clean tarball reinstall..."
    if ! repair_npm_install "$npm_bin" "$use_sudo"; then
        print_error "Failed to repair npm"
        return 1
    fi

    if probe_npm_health "$npm_bin"; then
        print_success "npm repaired successfully"
        return 0
    fi

    print_error "npm still unhealthy after repair"
    return 1
}

#=============================================================================
# USER INTERACTION FUNCTIONS
#=============================================================================

# Generic update confirmation prompt
# Usage: prompt_update_confirmation "application_name"
# Returns: 0 for yes (proceed with update), 1 for no (skip update)
# Example: prompt_update_confirmation "tmux"
prompt_update_confirmation() {
    local app_name="$1"
    prompt_yes_no "Update $app_name?"
}

#=============================================================================
# PACKAGE MANAGER FUNCTIONS
#=============================================================================

# Update application via package manager
# Usage: update_via_package_manager "package-name" ["verify-command"]
# Returns: 0 on success, 1 if no package manager found
update_via_package_manager() {
    local app_name="$1"
    local verify_command="${2:-}"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - skipping package manager update for $app_name"
        return 0
    fi

    local update_exit_code
    if command -v apt-get &> /dev/null; then
        print_status "Using apt package manager..."
        run_with_sudo apt-get update && run_with_sudo apt-get install --only-upgrade "$app_name" -y
        update_exit_code=$?
    elif command -v brew &> /dev/null; then
        print_status "Using Homebrew package manager..."
        brew upgrade "$app_name"
        update_exit_code=$?
    elif command -v dnf &> /dev/null; then
        print_status "Using dnf package manager..."
        run_with_sudo dnf upgrade "$app_name" -y
        update_exit_code=$?
    elif command -v yum &> /dev/null; then
        print_status "Using yum package manager..."
        run_with_sudo yum update "$app_name" -y
        update_exit_code=$?
    elif command -v pacman &> /dev/null; then
        print_status "Using pacman package manager..."
        run_with_sudo pacman -S --needed "$app_name" --noconfirm
        update_exit_code=$?
    else
        print_warning "No supported package manager found"
        return 1
    fi

    if [ $update_exit_code -ne 0 ]; then
        return $update_exit_code
    fi

    if [ -n "$verify_command" ] && ! command -v "$verify_command" &> /dev/null; then
        print_error "Update completed, but '$verify_command' is not available on PATH"
        return 1
    fi

    return 0
}

# Detect available package managers
# Usage: detect_available_package_managers
# Returns: space-separated list of available package managers
detect_available_package_managers() {
    local managers=""
    
    command -v apt &> /dev/null && managers="$managers apt"
    command -v brew &> /dev/null && managers="$managers brew"
    command -v dnf &> /dev/null && managers="$managers dnf"
    command -v yum &> /dev/null && managers="$managers yum"
    command -v pacman &> /dev/null && managers="$managers pacman"
    
    echo "$managers" | xargs
}

#=============================================================================
# VERSION CHECKING FUNCTIONS
#=============================================================================

# Check if application is installed
# Usage: check_app_installed "command-name" "app-name"
# Returns: 0 if installed, 1 if not
check_app_installed() {
    local command_name="$1"
    local app_name="${2:-$command_name}"
    
    if ! command -v "$command_name" &> /dev/null; then
        emit_summary_event "version_check" "target" "$app_name" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
        print_warning "$app_name not installed"
        return 1
    fi
    
    return 0
}

# Check if application is installed and show installation help if not
# Usage: check_app_installed_or_help "command-name" "app-name" "install-message"
# Returns: 0 if installed, 1 if not (and shows help + asks to continue)
check_app_installed_or_help() {
    local command_name="$1"
    local app_name="${2:-$command_name}"
    local install_message="$3"
    
    if ! check_app_installed "$command_name" "$app_name"; then
        if [ -n "$install_message" ]; then
            print_status "$install_message"
        fi
        ask_continue
        return 1
    fi
    
    return 0
}

# Extract version from command output
# Usage: extract_version "command output" "regex-pattern"
# Returns: extracted version string
extract_version() {
    local output="$1"
    local pattern="${2:-([0-9]+\.[0-9]+[a-z]?)}"
    
    printf '%s\n' "$output" | sed -nE "s/.*$pattern.*/\1/p" | head -1
}

# Compare and report version status
# Usage: compare_and_report_versions "current" "latest" "app-name"
# Returns: 0 if up-to-date, 1 if current > latest, 2 if update available
compare_and_report_versions() {
    local current_version="$1"
    local latest_version="$2"
    local app_name="${3:-Application}"
    
    print_status "Current version: $current_version"
    print_status "Latest version: $latest_version"
    
    if [ -z "$latest_version" ]; then
        emit_summary_event "version_check" "target" "$app_name" "status" "unknown" "current_version" "$current_version" "latest_version" "unknown"
        print_error "Failed to fetch latest version"
        return 1
    fi
    
    compare_versions "$current_version" "$latest_version"
    local cmp_result=$?
    
    if [ $cmp_result -eq 2 ]; then
        print_warning "$app_name update available: $current_version → $latest_version"
        emit_summary_event "version_check" "target" "$app_name" "status" "update_available" "current_version" "$current_version" "latest_version" "$latest_version"
        return 2
    elif [ $cmp_result -eq 1 ]; then
        print_status "$app_name version is newer than latest release"
        emit_summary_event "version_check" "target" "$app_name" "status" "ahead_of_latest" "current_version" "$current_version" "latest_version" "$latest_version"
        return 1
    else
        print_success "$app_name is up to date"
        emit_summary_event "version_check" "target" "$app_name" "status" "up_to_date" "current_version" "$current_version" "latest_version" "$latest_version"
        return 0
    fi
}

# Handle update workflow after version comparison
# Usage: handle_update_prompt "app-name" version_status update_command_or_function
# Returns: 0 on success or skip, 1 on failure
# Note: Automatically calls ask_continue and returns from parent function if no update needed
handle_update_prompt() {
    local app_name="$1"
    local version_status="$2"
    local update_callback="$3"
    
    # If no update needed (version_status 0=equal, 1=current>latest)
    if [ "$version_status" -ne 2 ]; then
        ask_continue
        return 0
    fi

    if [ "$CHECK_ONLY_MODE" = true ]; then
        print_status "Check-only mode - skipping $app_name update action"
        ask_continue
        return 0
    fi
    
    # Update needed - prompt user
    if ! prompt_yes_no "Update $app_name?"; then
        print_status "Skipping $app_name update"
        ask_continue
        return 0
    fi
    
    # Execute update callback
    print_status "Updating $app_name..."
    
    if [ -n "$update_callback" ]; then
        if eval "$update_callback"; then
            return 0
        else
            return 1
        fi
    fi
    
    return 0
}

emit_captured_output() {
    local output="$1"
    local output_lines="${2:-0}"
    local rendered_output="$output"
    local line

    if [ -z "$output" ]; then
        return 0
    fi

    if [ "${VERBOSE_MODE:-false}" != "true" ] && [[ "$output_lines" =~ ^[0-9]+$ ]] && [ "$output_lines" -gt 0 ]; then
        rendered_output=$(printf '%s\n' "$output" | tail -n "$output_lines")
    fi

    while IFS= read -r line; do
        printf '%s\n' "$line"
        emit_terminal_event "output" "$line"
    done <<< "$rendered_output"
}

verify_configured_update_result() {
    local previous_version="${1:-$CURRENT_VERSION}"
    local expected_version="${2:-$LATEST_VERSION}"
    local success_msg="$3"
    local command_name
    command_name=$(get_config "application.command")
    if [ -z "$command_name" ]; then
        command_name=$(get_config "application.name")
    fi

    local current_after_update
    current_after_update=$(get_current_version_from_config)
    if [ -z "$current_after_update" ]; then
        print_error "Failed to verify active $APP_DISPLAY_NAME version after update"
        return 1
    fi

    print_status "Verified version: $current_after_update"

    local cmp_result=0
    if [ -n "$expected_version" ]; then
        compare_versions "$current_after_update" "$expected_version"
        cmp_result=$?
        if [ $cmp_result -eq 2 ]; then
            print_error "$APP_DISPLAY_NAME update did not reach the expected version: $current_after_update < $expected_version"
            return 1
        fi
    elif [ -n "$previous_version" ] && [ "$current_after_update" = "$previous_version" ]; then
        print_error "$APP_DISPLAY_NAME version did not change after update"
        return 1
    fi

    if [ $cmp_result -eq 1 ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "ahead_of_latest" "current_version" "$current_after_update" "latest_version" "${expected_version:-unknown}"
    else
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "up_to_date" "current_version" "$current_after_update" "latest_version" "${expected_version:-$current_after_update}"
    fi

    print_success "$success_msg"
    if [ -n "$command_name" ]; then
        show_installation_info "$command_name" "$APP_DISPLAY_NAME"
    fi

    return 0
}

perform_configured_installer_script_update() {
    local installer_url
    installer_url=$(get_config "update.installer_url")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    output_lines="${output_lines:-20}"
    local downloading_msg
    downloading_msg=$(get_config "messages.downloading_installer")
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local install_method
    install_method=$(get_config "update.method")

    if [ -z "$installer_url" ] || [ -z "$install_method" ]; then
        print_error "Installer update configuration is incomplete"
        return 1
    fi

    # Pre-flight: installers that need root can't proceed in a non-interactive
    # context (e.g. the web backend) without cached sudo credentials. Detect
    # that up front and bail before downloading, emitting sudo.required so the
    # UI can prompt for re-authentication instead of leaving a wasted download
    # and a hard error after the fact.
    if [ "$install_method" = "wget_sudo_installer" ] && ! sudo_can_run; then
        emit_sudo_required_event "sh <installer for ${APP_DISPLAY_NAME:-$installer_url}>" "false"
        print_error "Sudo credentials required to install ${APP_DISPLAY_NAME:-this update}"
        print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
        return 1
    fi

    local installer_script
    installer_script=$(mktemp "/tmp/sysupdate-installer-XXXXXX.sh") || return 1

    print_status "$downloading_msg"

    local download_output
    local download_exit_code
    case "$install_method" in
        "curl_installer"|"curl_bash_installer")
            download_output=$(curl -fsSL "$installer_url" -o "$installer_script" 2>&1)
            download_exit_code=$?
            ;;
        "wget_installer"|"wget_sudo_installer")
            download_output=$(wget -nv -O "$installer_script" "$installer_url" 2>&1)
            download_exit_code=$?
            ;;
        *)
            rm -f "$installer_script"
            print_error "Unknown install method: $install_method"
            return 1
            ;;
    esac

    emit_captured_output "$download_output" "$output_lines"
    if [ $download_exit_code -ne 0 ]; then
        rm -f "$installer_script"
        return 1
    fi

    local install_output
    local install_exit_code
    if [ "$install_method" = "wget_sudo_installer" ]; then
        install_output=$(run_with_sudo sh "$installer_script" 2>&1)
        install_exit_code=$?
    elif [ "$install_method" = "curl_bash_installer" ]; then
        # Some official installers (e.g. Oh My Posh) are bash scripts that use
        # bashisms and target a user-writable dir, so run them with bash and no
        # sudo rather than sh.
        install_output=$(bash "$installer_script" 2>&1)
        install_exit_code=$?
    else
        install_output=$(sh "$installer_script" 2>&1)
        install_exit_code=$?
    fi

    rm -f "$installer_script"
    emit_captured_output "$install_output" "$output_lines"
    if [ $install_exit_code -ne 0 ]; then
        return 1
    fi

    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

run_configured_fix_dependencies() {
    local fix_deps_command="$1"
    local -a fix_deps_args=()

    if [ -z "$fix_deps_command" ]; then
        return 0
    fi

    read -r -a fix_deps_args <<< "$fix_deps_command"
    [ ${#fix_deps_args[@]} -gt 0 ] || return 0
    run_with_sudo "${fix_deps_args[@]}"
}

perform_configured_deb_package_update() {
    local redirect_url
    redirect_url=$(get_config "update.redirect_url")
    local temp_file
    temp_file=$(get_config "update.temp_file")
    local output_lines
    output_lines=$(get_config "update.output_lines")
    output_lines="${output_lines:-20}"
    local success_msg
    success_msg=$(get_config "messages.update_success")
    local fix_deps
    fix_deps=$(get_config "update.fix_dependencies")

    if [ -z "$redirect_url" ]; then
        print_error "Debian package update configuration is incomplete"
        return 1
    fi

    # Pre-flight: dpkg -i (and the apt-get -f dependency repair) need root. In a
    # non-interactive context (e.g. the web backend) with no cached sudo
    # credentials this cannot succeed, so bail before downloading the package
    # rather than wasting a large download and erroring after the fact. Emitting
    # sudo.required lets the UI prompt for re-authentication.
    if ! sudo_can_run; then
        emit_sudo_required_event "dpkg -i <package for ${APP_DISPLAY_NAME:-this update}>" "false"
        print_error "Sudo credentials required to install ${APP_DISPLAY_NAME:-this update}"
        print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
        return 1
    fi

    if [ -z "$temp_file" ]; then
        temp_file=$(mktemp "/tmp/sysupdate-package-XXXXXX.deb") || return 1
    fi

    local download_url
    download_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$redirect_url" 2>/dev/null)
    if [ -z "$download_url" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_download_url")
        print_error "$error_msg"
        rm -f "$temp_file"
        return 1
    fi

    local downloading_msg
    downloading_msg=$(get_config "messages.downloading")
    downloading_msg="${downloading_msg/\{url\}/$download_url}"
    local installing_msg
    installing_msg=$(get_config "messages.installing")

    print_status "$downloading_msg"
    local download_output
    download_output=$(wget -nv -O "$temp_file" "$download_url" 2>&1)
    local download_exit_code=$?
    emit_captured_output "$download_output" "$output_lines"
    if [ $download_exit_code -ne 0 ]; then
        rm -f "$temp_file"
        return 1
    fi

    print_status "$installing_msg"
    local install_output
    install_output=$(run_with_sudo dpkg -i "$temp_file" 2>&1)
    local install_exit_code=$?
    emit_captured_output "$install_output" "$output_lines"

    if [ -n "$fix_deps" ]; then
        if [ $install_exit_code -ne 0 ]; then
            print_warning "dpkg reported issues; attempting dependency repair"
        fi

        local fix_output
        fix_output=$(run_configured_fix_dependencies "$fix_deps" 2>&1)
        local fix_exit_code=$?
        emit_captured_output "$fix_output" "$output_lines"
        if [ $fix_exit_code -ne 0 ]; then
            rm -f "$temp_file"
            return 1
        fi
    elif [ $install_exit_code -ne 0 ]; then
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"
    verify_configured_update_result "$CURRENT_VERSION" "$LATEST_VERSION" "$success_msg"
}

# Download a URL to a file, showing wget's progress bar only on an interactive
# terminal. When the CLI is spawned by the web backend, its stdio is piped
# (non-TTY), where `wget --show-progress` degrades to per-chunk dot progress
# (one line every ~50KB) written to stderr. The backend forwards each such line
# as a terminal event, so a large download floods the Live Output Console and
# the JSON event stream with thousands of lines. In the non-TTY case use -nv
# (a single summary line) instead.
# Usage: download_with_progress <url> <output_path>
# Returns: wget's exit code
download_with_progress() {
    local url="$1"
    local output="$2"

    if [ -t 2 ]; then
        wget -q --show-progress "$url" -O "$output"
    else
        wget -nv "$url" -O "$output"
    fi
}

# Generic installer script update handler
# Handles common pattern of downloading and running an installer script
# Usage: handle_installer_script_update
# Requires: CONFIG_FILE with update.installer_url, update.output_lines, messages.*
# Returns: 0 on success, 1 on failure
handle_installer_script_update() {
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_configured_installer_script_update"; then
        ask_continue
        return 1
    fi
    
    return 0
}

# Handle .deb package download and installation
# Used by scripts that install via downloadable .deb packages
# Reads configuration from CONFIG_FILE YAML
handle_deb_package_update() {
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_configured_deb_package_update"; then
        ask_continue
        return 1
    fi
    
    return 0
}

#=============================================================================
# BUILD FROM SOURCE UTILITIES
#=============================================================================

# Check for build dependencies
# Usage: check_build_dependencies "dep1" "dep2" "dep3"
# Returns: 0 if all present, 1 if any missing (prints missing deps)
check_build_dependencies() {
    local missing_deps=()
    
    for dep in "$@"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing build dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Create temporary build directory
# Usage: BUILD_DIR=$(create_build_directory "app-name")
create_build_directory() {
    local app_name="$1"
    local safe_app_name
    safe_app_name=$(printf '%s' "$app_name" | tr -c '[:alnum:]._-' '-')

    mktemp -d "/tmp/${safe_app_name}-build-XXXXXX"
}

# Cleanup build directory
# Usage: cleanup_build_directory "/path/to/build/dir" "previous-dir"
cleanup_build_directory() {
    local build_dir="$1"
    local previous_dir="${2:-.}"
    
    cd "$previous_dir" > /dev/null 2>&1 || true
    [ -d "$build_dir" ] && rm -rf "$build_dir"
}

#=============================================================================
# INSTALLATION INFO DISPLAY
#=============================================================================

# Show detailed installation information in verbose mode
# Usage: show_installation_info "command-name" "App Name"
show_installation_info() {
    local command_name="$1"
    local app_name="${2:-$command_name}"
    
    # Only show if VERBOSE_MODE is enabled
    if [ "${VERBOSE_MODE:-false}" != "true" ]; then
        return 0
    fi
    
    print_status "Installation Information:"
    
    # Use whereis to show all installation paths (binary, source, man pages)
    local whereis_output
    whereis_output=$(whereis "$command_name" 2>/dev/null)
    
    if [ -n "$whereis_output" ]; then
        echo -e "${CYAN}   📍 Locations:${NC}"
        # Parse whereis output and display formatted
        local locations
        locations=$(echo "$whereis_output" | cut -d: -f2- | xargs -n1)
        
        while IFS= read -r location; do
            [ -n "$location" ] && echo -e "${CYAN}             ${NC}  $location"
        done <<< "$locations"
    else
        # Fallback to which if whereis returns nothing
        local binary_path
        binary_path=$(which "$command_name" 2>/dev/null)
        [ -n "$binary_path" ] && echo -e "${CYAN}   📍 Binary:${NC}  $binary_path"
    fi
    
    # Show version
    local version_output
    case "$command_name" in
        copilot)
            version_output=$("$command_name" --version 2>/dev/null | head -1)
            [ -n "$version_output" ] && echo -e "${CYAN}   📦 Version:${NC} $version_output"
            ;;
        tmux)
            version_output=$("$command_name" -V 2>/dev/null)
            [ -n "$version_output" ] && echo -e "${CYAN}   📦 Version:${NC} $version_output"
            ;;
        kitty)
            version_output=$("$command_name" --version 2>/dev/null)
            [ -n "$version_output" ] && echo -e "${CYAN}   📦 Version:${NC} $version_output"
            ;;
        *)
            version_output=$("$command_name" --version 2>/dev/null | head -1)
            [ -n "$version_output" ] && echo -e "${CYAN}   📦 Version:${NC} $version_output"
            ;;
    esac
    
    # Show config directory if exists
    local config_paths=()
    [ -d "$HOME/.config/$command_name" ] && config_paths+=("$HOME/.config/$command_name")
    [ -d "$HOME/.$command_name" ] && config_paths+=("$HOME/.$command_name")
    [ -f "$HOME/.${command_name}rc" ] && config_paths+=("$HOME/.${command_name}rc")
    [ -f "$HOME/.config/${command_name}.conf" ] && config_paths+=("$HOME/.config/${command_name}.conf")
    
    if [ ${#config_paths[@]} -gt 0 ]; then
        echo -e "${CYAN}   ⚙️  Config:${NC}"
        for cfg_path in "${config_paths[@]}"; do
            echo -e "${CYAN}            ${NC}  $cfg_path"
        done
    fi
    
    echo ""
}
