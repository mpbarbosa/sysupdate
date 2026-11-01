#!/bin/bash
#
# upgrade_utils.sh - Common Utilities for Upgrade Snippets
#
# Provides reusable functions for version checking and application updates
# to avoid code duplication across upgrade snippet modules.
#
# Version: 1.4.0
# Date: 2026-10-31
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#
# Version History:
#   1.4.0 (2026-10-31) - Read-only apt discovery for archive-served packages:
#                        get_apt_latest_version now resolves past a stale local
#                        index, so gcc / python3 / firefox / fwupd / chrome stop
#                        reporting a superseded candidate as up to date
#                      - New functions: apt_resolve_latest_version(),
#                        apt_package_candidate_origins(), apt_package_origin_pool(),
#                        apt_package_winning_priority(), apt_known_index_origins(),
#                        apt_host_family(),
#                        apt_package_index_is_stale(), apt_published_latest_version(),
#                        apt_repo_version_table(), apt_repo_published_version(),
#                        apt_index_to_version_table(), apt_index_cache_dir(),
#                        fetch_debian_repo_index_stream(), apt_candidate_version(),
#                        apt_version_gt(), apt_report_latest_resolution()
#   1.3.0 (2026-10-12) - Read-only apt version discovery that does not depend
#                        on the freshness of the local apt index
#                      - New functions: select_highest_dpkg_version(),
#                        apt_index_age_seconds(), apt_index_is_stale(),
#                        apt_package_is_held(), fetch_debian_repo_index(),
#                        fetch_debian_repo_latest_version()
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

# Resolve the one-line remediation text for a blocking summary status.
#
# Blocking statuses (`invalid_installation`, `insufficient_efi_space`, ...) tell
# the dashboard that sysupdate cannot proceed until a human fixes something on
# the host. The `remediation` field on the `summary.updates` event carries *what*
# to fix. The text lives in the snippet's YAML under `remediation.<key>` so the
# terminal help and the dashboard card stay a single source of truth.
#
# Placeholders substituted: {path} (from $2), {repo} (application.git_repo),
# {branch} (update.branch). Missing keys resolve to an empty string, which
# callers may still pass through — consumers treat empty as "no remediation".
#
# Usage: get_remediation "not_git_repo" "$install_dir"
get_remediation() {
    local key="$1"
    local install_dir="$2"

    local text
    text=$(get_config "remediation.$key")
    if [ -z "$text" ]; then
        echo ""
        return 0
    fi

    local repo
    repo=$(get_config "application.git_repo")
    local branch
    branch=$(get_config "update.branch")

    text="${text//\{path\}/$install_dir}"
    text="${text//\{repo\}/$repo}"
    text="${text//\{branch\}/$branch}"

    echo "$text"
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

    # When VERSION_CMD_STDERR_FILE is set (by config_driven_version_check), capture
    # the version command's stderr there so an actionable failure cause — e.g. a
    # broken binary's "libX.so: cannot open shared object file" — can be surfaced
    # instead of silently swallowed. Command substitution runs in a subshell, so a
    # file (not a variable) is used to carry the error back to the caller.
    local version_output
    if [ -n "${VERSION_CMD_STDERR_FILE:-}" ]; then
        version_output=$(eval "$version_cmd" 2>"$VERSION_CMD_STDERR_FILE" | head -1)
    else
        version_output=$(eval "$version_cmd" 2>/dev/null | head -1)
    fi
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
    
    # Get current version, capturing the version command's stderr so we can show
    # WHY it failed (e.g. a broken binary) rather than a bare "failed" message.
    local version_cmd_stderr
    VERSION_CMD_STDERR_FILE=$(mktemp 2>/dev/null || echo "")
    CURRENT_VERSION=$(get_current_version_from_config)
    if [ -n "$VERSION_CMD_STDERR_FILE" ]; then
        version_cmd_stderr=$(head -3 "$VERSION_CMD_STDERR_FILE" 2>/dev/null)
        rm -f "$VERSION_CMD_STDERR_FILE"
    fi
    VERSION_CMD_STDERR_FILE=""

    if [ -z "$CURRENT_VERSION" ]; then
        local error_msg
        error_msg=$(get_config "messages.failed_version")
        if [ -z "$error_msg" ]; then
            error_msg=$(get_config "messages.failed_get_version")
        fi
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
        print_error "$error_msg"
        # Surface the underlying cause (missing shared library, crash, etc.) so the
        # failure is actionable instead of a mysterious "unknown → unknown".
        if [ -n "${version_cmd_stderr:-}" ]; then
            while IFS= read -r _line; do
                [ -n "$_line" ] && print_error "  ↳ $_line"
            done <<< "$version_cmd_stderr"
        fi
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
#
# The version comes from apt_resolve_latest_version rather than straight from
# the candidate, so a read-only scan with a stale local index reports what the
# repository actually publishes instead of a long-superseded candidate. See
# "TRUSTWORTHY APT 'LATEST' VERSION" below for what that does and does not do.
# The trailing Debian revision is stripped here, as it always was, because the
# current version every caller compares against is stripped the same way.
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
    version=$(apt_resolve_latest_version "$package" | sed 's/-[^-]*$//')
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

# Locations apt actually reads. Overridable so the suites can point at a
# fixture tree instead of the real /etc.
APT_SOURCES_LIST_FILE="${APT_SOURCES_LIST_FILE:-/etc/apt/sources.list}"
APT_SOURCES_LIST_DIR="${APT_SOURCES_LIST_DIR:-/etc/apt/sources.list.d}"

# True when some enabled apt source points at the given URL substring.
# Usage: apt_repository_is_configured "dl.google.com/linux/chrome"
#
# A snippet must not decide this by testing for the one file it happens to
# write. The same repository legitimately lives in several shapes: the
# one-line `foo.list`, or the deb822 `foo.sources` that upstream postinsts now
# ship and that Ubuntu's deb822 migration rewrites old .list files into —
# leaving the original behind as `foo.list.disabled`. Probing for `foo.list`
# alone sees "not configured" on a perfectly configured machine and writes a
# second, duplicate entry for the same repository.
#
# Only live sources count. The globs below skip the `.disabled` and `.save`
# leftovers apt does not read, commented-out .list lines do not match, and a
# deb822 stanza turned off with `Enabled: no` is ignored.
apt_repository_is_configured() {
    local url_substring="$1"
    local pattern file

    [ -n "$url_substring" ] || return 1
    # Read the substring literally: URLs are full of dots.
    pattern=$(printf '%s' "$url_substring" | sed 's#[][\\.*^$(){}?+|]#\\&#g')

    for file in "$APT_SOURCES_LIST_FILE" "$APT_SOURCES_LIST_DIR"/*.list; do
        [ -f "$file" ] || continue
        if grep -Eq "^[[:space:]]*deb(-src)?[[:space:]].*${pattern}" "$file"; then
            return 0
        fi
    done

    for file in "$APT_SOURCES_LIST_DIR"/*.sources; do
        [ -f "$file" ] || continue
        grep -Eq "^[[:space:]]*URIs:.*${pattern}" "$file" || continue
        grep -Eqi "^[[:space:]]*Enabled:[[:space:]]*(no|false)" "$file" && continue
        return 0
    done

    return 1
}

# True when an enabled apt source actually serves the package - i.e. apt itself
# could install or upgrade it, so apt is a legitimate version source for it.
#
# `apt-cache policy` answers for any package dpkg knows about, and for one
# installed from a hand-downloaded .deb the Candidate is simply its own
# installed version. A snippet reading the Candidate alone would therefore call
# such a package permanently "up to date". Only an origin line in the version
# table ("500 https://repo ... Packages") proves a repository carries it; the
# "100 /var/lib/dpkg/status" pin is the installed copy, not a source.
apt_package_is_repo_served() {
    local package="$1"

    [ -n "$package" ] || return 1
    command -v apt-cache >/dev/null 2>&1 || return 1

    apt-cache policy "$package" 2>/dev/null \
        | grep -qE '^[[:space:]]+[0-9]+[[:space:]]+[a-z][a-z0-9+.-]*:'
}

# Where apt caches the repository indexes it has fetched. Overridable so the
# suites can point the freshness check at a fixture tree.
APT_LISTS_DIR="${APT_LISTS_DIR:-/var/lib/apt/lists}"

# The highest dpkg version among those read on stdin, one per line.
#
# `sort -V` is close to dpkg's ordering but not the same: it has no notion of
# an epoch and sorts the "~" pre-release marker the wrong way, so "1.0~rc1"
# comes out above "1.0". dpkg is the only authority, and every caller here is
# already on an apt system; sort -V stays only for the sourced-standalone case.
#
# The input is an external repository index, so lines that are not plausible
# dpkg versions are dropped rather than compared (see DEFENSIVE_CODING_GUIDE).
select_highest_dpkg_version() {
    local line best="" have_dpkg=false
    command -v dpkg >/dev/null 2>&1 && have_dpkg=true

    while IFS= read -r line; do
        line="${line//[[:space:]]/}"
        [[ "$line" =~ ^[0-9][A-Za-z0-9.+:~-]*$ ]] || continue
        if [ -z "$best" ]; then
            best="$line"
        elif [ "$have_dpkg" = true ]; then
            dpkg --compare-versions "$line" gt "$best" && best="$line"
        elif [ "$(printf '%s\n%s\n' "$best" "$line" | sort -V | tail -1)" = "$line" ]; then
            best="$line"
        fi
    done

    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

# Age in seconds of the most recently fetched apt index for a repository host.
# Args: <host> - a hostname as it appears in the cached index filenames
# Echoes the age; returns 1 when no index for that host has ever been fetched.
apt_index_age_seconds() {
    local host="$1"
    [ -n "$host" ] || return 1
    [ -d "$APT_LISTS_DIR" ] || return 1

    # apt names each cached index after its URL with "_" for the separators, so
    # the host survives verbatim: downloads.claude.ai_..._binary-amd64_Packages
    local newest
    newest=$(find "$APT_LISTS_DIR" -maxdepth 1 -type f -name "*${host}*_Packages*" \
        -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
    [ -n "$newest" ] || return 1

    local now
    now=$(date +%s 2>/dev/null) || return 1
    printf '%s\n' "$(( now - ${newest%.*} ))"
}

# True when the local apt index for a host is missing or older than max-age.
# Args: <host> [max-age-seconds, default 3600]
#
# A never-fetched index counts as stale: that is the state in which the apt
# candidate is least trustworthy, not the state in which to trust it.
apt_index_is_stale() {
    local host="$1" max_age="${2:-3600}"
    [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=3600

    local age
    age=$(apt_index_age_seconds "$host") || return 0
    [ "$age" -gt "$max_age" ]
}

# True when apt is holding the package back, so no upgrade could happen even if
# the repository published a newer version. Read-only; needs no sudo.
apt_package_is_held() {
    local package="$1"
    [ -n "$package" ] || return 1
    command -v apt-mark >/dev/null 2>&1 || return 1
    apt-mark showhold 2>/dev/null | grep -qxF "$package"
}

# A Debian repository's own Packages index for an architecture, over HTTPS.
# Args: <base-url> <suite> <component> <arch>
#   e.g. https://downloads.claude.ai/claude-desktop/apt/stable stable main amd64
# Echoes the index body; returns 1 when it cannot be read.
#
# This is what makes read-only discovery honest on an apt channel. The local
# apt index is only as fresh as the last `apt-get update`, which --check-only
# and --snippet deliberately never run, so the candidate they read can name a
# long-superseded version as the latest. The repository index needs no sudo and
# no apt-get update, so a read-only scan can consult the authority directly.
fetch_debian_repo_index() {
    local base="$1" suite="$2" component="$3" arch="$4"
    [ -n "$base" ] && [ -n "$suite" ] && [ -n "$component" ] && [ -n "$arch" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    local timeout="${SYSUPDATE_CURL_TIMEOUT:-20}"
    local index_url="${base%/}/dists/${suite}/${component}/binary-${arch}/Packages"
    local body
    body=$(curl -fsSL --max-time "$timeout" "$index_url" 2>/dev/null)

    # Some repositories publish only the compressed index.
    if [ -z "$body" ] && command -v gzip >/dev/null 2>&1; then
        body=$(curl -fsSL --max-time "$timeout" "${index_url}.gz" 2>/dev/null \
            | gzip -cd 2>/dev/null)
    fi

    [ -n "$body" ] || return 1
    printf '%s\n' "$body"
}

# The highest version a Debian repository publishes for an architecture.
# Args: as fetch_debian_repo_index; echoes the version, returns 1 on failure.
fetch_debian_repo_latest_version() {
    local index
    index=$(fetch_debian_repo_index "$@") || return 1
    printf '%s\n' "$index" \
        | awk '/^Version:[[:space:]]/ { print $2 }' \
        | select_highest_dpkg_version
}

#=============================================================================
# TRUSTWORTHY APT "LATEST" VERSION FOR READ-ONLY DISCOVERY
#=============================================================================
#
# `apt-cache policy` answers out of the local index, which is only as fresh as
# the last `apt-get update`. `--check-only` and `--snippet <id>` deliberately
# never run one, so in exactly the two modes the dashboard consumes the
# candidate can name a long-superseded version and the snippet reports
# `up_to_date`. apt_resolve_latest_version() closes that gap: while the index
# is fresh it returns the candidate unchanged, and once the index is stale it
# asks the repository that would serve the package.
#
# Why the repository's own Packages index, and not the alternatives:
#
#   * Launchpad (Ubuntu) / ftp-master madison (Debian) replies are tiny, but
#     they answer a different question - what the distribution published, not
#     what this machine's configured mirror serves at this machine's pin
#     priorities. A lagging mirror or a pin would turn their answer into the
#     promise of an upgrade apt would refuse, which is the same defect as
#     reporting past a hold. Two distro-specific APIs would also have to be
#     kept working, each with its own outage and rate-limit behaviour.
#   * A scoped `apt-get -o Dir::State::lists=<tmpdir> update` needs no sudo
#     with a private lists directory, but it downloads the same index bytes
#     plus Release and signature material, and scoping it to one origin means
#     synthesising a sources file; get that wrong and it quietly refetches
#     every enabled source instead of one.
#   * The Packages index is the authority apt itself would read, over the same
#     URI from the machine's own sources, needs no sudo and no apt-get update.
#
# What keeps it cheap is not fetching fewer bytes per index but fetching fewer
# indexes: the origins come from the package's own version table, so only the
# suites that actually serve *this* package are consulted (one for `gcc`, not
# `resolute` + `-updates` + `-security`), only those at apt's winning pin
# priority, and each index is reduced to a "<package> <version>" table cached
# for the run - so `gcc`, `python3` and `fwupd` share a single fetch.
#
# Set SYSUPDATE_APT_PUBLISHED_LOOKUP=false to switch the lookup off entirely
# and go back to reading the candidate alone.

# Run-scoped cache directory for fetched repository index tables.
# Echoes the path, creating it on first use; returns 1 when it cannot.
apt_index_cache_dir() {
    local dir="${SYSUPDATE_APT_INDEX_CACHE_DIR:-${TMPDIR:-/tmp}/sysupdate-apt-index-${SYSUPDATE_RUN_ID:-$$}}"
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s\n' "$dir"
}

# The apt origins that could actually install a package, as
# "<base-url>|<suite>|<component>" lines. Returns 1 when there are none.
#
# Only the origins at the winning pin priority are reported, because those are
# the only ones apt would choose between. Firefox is the worked example: with
# Mozilla's repository pinned to 1000 and Ubuntu's snap-transition package
# sitting at -1, "the highest version any origin publishes" would pick
# Ubuntu's `1:1snap1-0ubuntu9.1` - an epoch outranks everything - and promise
# an upgrade apt has been configured never to make.
#
# The dpkg status pin (priority 100, no URI) is the installed copy rather than
# a source and never matches. Flat repositories print no suite/component pair,
# so they yield nothing here and the caller keeps the candidate.
apt_package_candidate_origins() {
    local package="$1"
    [ -n "$package" ] || return 1
    command -v apt-cache >/dev/null 2>&1 || return 1

    local origins
    origins=$(apt-cache policy "$package" 2>/dev/null | awk '
        $2 ~ /:\/\// && $NF == "Packages" && NF >= 5 {
            priority = $1 + 0
            # 0 and below are never installed, so they are not candidates.
            if (priority < 1) next
            split($3, parts, "/")
            if (parts[1] == "" || parts[2] == "") next
            key = $2 "|" parts[1] "|" parts[2]
            if (!(key in seen) || priority > seen[key]) seen[key] = priority
            if (priority > winning) winning = priority
        }
        END {
            for (key in seen) if (seen[key] == winning) print key
        }
    ')

    [ -n "$origins" ] || return 1
    printf '%s\n' "$origins"
}

# The winning pin priority among the origins that serve a package.
# Args: <package>; returns 1 when no origin does.
apt_package_winning_priority() {
    local package="$1"
    [ -n "$package" ] || return 1
    command -v apt-cache >/dev/null 2>&1 || return 1

    local winning
    winning=$(apt-cache policy "$package" 2>/dev/null | awk '
        $2 ~ /:\/\// && $NF == "Packages" && NF >= 5 {
            priority = $1 + 0
            if (priority < 1) next
            if (priority > winning) winning = priority
        }
        END { if (winning > 0) print winning }
    ')

    [ -n "$winning" ] || return 1
    printf '%s\n' "$winning"
}

# Every index apt knows about, as "<priority>|<base-url>|<suite>|<component>".
#
# Read from `apt-cache policy` with no package, which lists the configured
# priority of each index. Those priorities come from the Release files and the
# preferences, not from the package lists, so they stay true while the versions
# in the index go stale.
apt_known_index_origins() {
    command -v apt-cache >/dev/null 2>&1 || return 1

    local origins
    origins=$(apt-cache policy 2>/dev/null | awk '
        $2 ~ /:\/\// && $NF == "Packages" && NF >= 5 {
            priority = $1 + 0
            if (priority < 1) next
            split($3, parts, "/")
            if (parts[1] == "" || parts[2] == "") next
            print priority "|" $2 "|" parts[1] "|" parts[2]
        }
    ' | sort -u)

    [ -n "$origins" ] || return 1
    printf '%s\n' "$origins"
}

# The last two labels of a host - "archive.ubuntu.com" and
# "security.ubuntu.com" both reduce to "ubuntu.com". Accepts a base URL.
apt_host_family() {
    local host="${1#*://}"
    host="${host%%/*}"
    host="${host%%:*}"
    printf '%s\n' "$host" | awk -F. '{ if (NF >= 2) print $(NF - 1) "." $NF; else print $0 }'
}

# The origins a read-only scan should ask about a package, as
# "<base-url>|<suite>|<component>" lines. Returns 1 when there are none.
#
# The package's own version table names only the pockets that already held a
# version when the local index was last fetched. For an archive package that is
# usually the frozen release pocket alone, while its updates land in
# <suite>-updates and <suite>-security - exactly the pockets a months-old index
# cannot point at. So the pool is the package's own winning-priority origins
# plus every index apt knows at that same priority in the same archive family:
# same component, same release before the pocket suffix, and a host sharing its
# last two labels, which is what makes security.ubuntu.com a sibling of
# archive.ubuntu.com.
#
# apt itself would consider *every* index at the winning priority. The family
# restriction is a cost bound rather than a correctness rule: it keeps a run
# from fetching the index of every unrelated third-party repository that merely
# shares priority 500. A package served only by an index the local lists have
# never seen at all stays out of reach.
apt_package_origin_pool() {
    local package="$1"
    [ -n "$package" ] || return 1

    local own
    own=$(apt_package_candidate_origins "$package") || return 1

    local priority
    priority=$(apt_package_winning_priority "$package") || {
        printf '%s\n' "$own"
        return 0
    }

    local -a families=() releases=() components=()
    local base suite component
    while IFS='|' read -r base suite component; do
        [ -n "$base" ] || continue
        families+=("$(apt_host_family "$base")")
        releases+=("${suite%%-*}")
        components+=("$component")
    done <<< "$own"

    local pool="$own"
    local known_priority family release index
    while IFS='|' read -r known_priority base suite component; do
        [ "$known_priority" = "$priority" ] || continue
        family=$(apt_host_family "$base")
        release="${suite%%-*}"
        for ((index = 0; index < ${#families[@]}; index++)); do
            [ "$family" = "${families[$index]}" ] || continue
            [ "$release" = "${releases[$index]}" ] || continue
            [ "$component" = "${components[$index]}" ] || continue
            pool+=$'\n'"$base|$suite|$component"
            break
        done
    done < <(apt_known_index_origins)

    printf '%s\n' "$pool" | sort -u
}

# True when the local index of any origin that could install the package is
# missing or older than max-age - i.e. when the candidate is not evidence.
# Args: <package> [max-age-seconds]
apt_package_index_is_stale() {
    local package="$1" max_age="$2"
    local base suite component host

    while IFS='|' read -r base suite component; do
        [ -n "$base" ] || continue
        host="${base#*://}"
        host="${host%%/*}"
        [ -n "$host" ] || continue
        if apt_index_is_stale "$host" "$max_age"; then
            return 0
        fi
    done < <(apt_package_origin_pool "$package")

    return 1
}

# Reduce a Debian Packages index on stdin to "<package> <version>" lines.
#
# The main archive's index is tens of megabytes uncompressed, so it is never
# held in a variable or written to disk whole: it streams through here and only
# the table is kept.
apt_index_to_version_table() {
    awk '
        /^Package:[[:space:]]/ { package_name = $2; next }
        /^Version:[[:space:]]/ { if (package_name != "") print package_name, $2; next }
        /^$/ { package_name = "" }
    '
}

# Stream one origin's Packages index for an architecture to stdout.
# Args: <base-url> <suite> <component> <arch>; returns 1 when unreadable.
#
# Separate from fetch_debian_repo_index so the body never has to fit in a
# variable, and so the suites can stub the network at one seam.
fetch_debian_repo_index_stream() {
    local base="$1" suite="$2" component="$3" arch="$4"
    [ -n "$base" ] && [ -n "$suite" ] && [ -n "$component" ] && [ -n "$arch" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    local timeout="${SYSUPDATE_CURL_TIMEOUT:-20}"
    local url="${base%/}/dists/${suite}/${component}/binary-${arch}/Packages"
    local payload
    payload=$(mktemp 2>/dev/null) || return 1

    # The archive publishes the compressed index; some third-party repositories
    # publish only the plain one.
    if command -v gzip >/dev/null 2>&1 \
        && curl -fsSL --max-time "$timeout" -o "$payload" "${url}.gz" 2>/dev/null \
        && [ -s "$payload" ]; then
        gzip -cd < "$payload" 2>/dev/null
        rm -f "$payload"
        return 0
    fi

    if curl -fsSL --max-time "$timeout" -o "$payload" "$url" 2>/dev/null \
        && [ -s "$payload" ]; then
        cat "$payload"
        rm -f "$payload"
        return 0
    fi

    rm -f "$payload"
    return 1
}

# Path to the cached "<package> <version>" table for one origin, fetching it on
# first use. Args: <base-url> <suite> <component> <arch>; returns 1 on failure.
#
# An unreachable origin is remembered as a miss for the rest of the run, so one
# network timeout is paid once rather than by every snippet behind it.
apt_repo_version_table() {
    local base="$1" suite="$2" component="$3" arch="$4"
    local dir key table
    dir=$(apt_index_cache_dir) || return 1

    key=$(printf '%s|%s|%s|%s' "$base" "$suite" "$component" "$arch" \
        | md5sum 2>/dev/null | awk '{ print $1 }')
    [ -n "$key" ] || key="${base//[^A-Za-z0-9]/_}_${suite}_${component}_${arch}"
    table="$dir/$key.table"

    [ -f "$table.miss" ] && return 1
    if [ -s "$table" ]; then
        printf '%s\n' "$table"
        return 0
    fi

    fetch_debian_repo_index_stream "$base" "$suite" "$component" "$arch" \
        | apt_index_to_version_table > "$table.part" 2>/dev/null

    if [ -s "$table.part" ] && mv -f "$table.part" "$table" 2>/dev/null; then
        printf '%s\n' "$table"
        return 0
    fi

    rm -f "$table.part"
    : > "$table.miss" 2>/dev/null
    return 1
}

# The highest version one origin publishes for a package.
# Args: <package> <base-url> <suite> <component> <arch>
apt_repo_published_version() {
    local package="$1" base="$2" suite="$3" component="$4" arch="$5"
    [ -n "$package" ] || return 1

    local table
    table=$(apt_repo_version_table "$base" "$suite" "$component" "$arch") || return 1

    awk -v want="$package" '$1 == want { print $2 }' "$table" \
        | select_highest_dpkg_version
}

# The highest version the package's origin pool publishes, read from those
# origins' own Packages indexes. Args: <package>; returns 1 when none answers.
apt_published_latest_version() {
    local package="$1"
    [ -n "$package" ] || return 1

    local arch base suite component
    arch=$(dpkg --print-architecture 2>/dev/null)
    [ -n "$arch" ] || arch="amd64"

    {
        while IFS='|' read -r base suite component; do
            [ -n "$base" ] && [ -n "$suite" ] && [ -n "$component" ] || continue
            apt_repo_published_version "$package" "$base" "$suite" "$component" "$arch"
        done < <(apt_package_origin_pool "$package")
    } | select_highest_dpkg_version
}

# True when version <a> is strictly newer than version <b>, by dpkg's ordering.
# Usage: apt_version_gt "4:10.1.0" "4:9.5.0"
apt_version_gt() {
    [ -n "$1" ] || return 1
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --compare-versions "$1" gt "$2"
        return
    fi

    [ "$1" != "$2" ] || return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# The apt candidate for a package, verbatim ("(none)" reported as absent).
apt_candidate_version() {
    local candidate
    candidate=$(apt-cache policy "$1" 2>/dev/null \
        | awk '/^[[:space:]]*Candidate:/ { print $2; exit }')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || return 1
    printf '%s\n' "$candidate"
}

# Record where a resolved apt "latest" version came from, as a log.entry event
# on the JSON stream. Silent for the plain candidate - that is the default - and
# silent when --json-events is off. Args: <package>
apt_report_latest_resolution() {
    [ "${APT_LATEST_VERSION_SOURCE:-apt candidate}" = "apt candidate" ] && return 0
    emit_event "log.entry" "action" "apt_latest_resolution" "target" "$1" \
        "status" "resolved" "category" "version_check" \
        "details" "$APT_LATEST_VERSION_SOURCE"
}

# The version a read-only scan should report as "latest" for an apt package.
# Args: <package> [max-age-seconds, default SYSUPDATE_APT_INDEX_MAX_AGE or 3600]
# Echoes a full dpkg version (epoch and Debian revision intact) and returns 0,
# or returns 1 when no authority can name one.
#
# Sets APT_LATEST_VERSION_SOURCE to the provenance of the answer, so a caller
# that does not need a subshell can say which authority produced the version;
# the same provenance is emitted as a log.entry event whenever it is not the
# plain candidate. Nothing is printed to stdout but the version itself, because
# every caller captures this in a command substitution.
#
# The answer only ever moves forward past the candidate, and never past a hold:
# a held package cannot be upgraded at all, so reporting the repository's newer
# version for it would promise an upgrade apt would refuse.
apt_resolve_latest_version() {
    local package="$1"
    local max_age="${2:-${SYSUPDATE_APT_INDEX_MAX_AGE:-3600}}"
    [ -n "$package" ] || return 1
    command -v apt-cache >/dev/null 2>&1 || return 1

    local candidate
    candidate=$(apt_candidate_version "$package") || candidate=""
    APT_LATEST_VERSION_SOURCE="apt candidate"

    # The candidate is the better answer while the index is fresh: it accounts
    # for pinning and preferences, so it is the version an upgrade would
    # actually install.
    if [ "${SYSUPDATE_APT_PUBLISHED_LOOKUP:-true}" != "true" ] \
        || ! apt_package_is_repo_served "$package" \
        || ! apt_package_index_is_stale "$package" "$max_age"; then
        [ -n "$candidate" ] || return 1
        printf '%s\n' "$candidate"
        return 0
    fi

    if apt_package_is_held "$package"; then
        APT_LATEST_VERSION_SOURCE="apt candidate (held by apt)"
        apt_report_latest_resolution "$package"
        [ -n "$candidate" ] || return 1
        printf '%s\n' "$candidate"
        return 0
    fi

    local published
    published=$(apt_published_latest_version "$package") || published=""

    if [ -z "$published" ]; then
        [ -n "$candidate" ] || return 1
        APT_LATEST_VERSION_SOURCE="apt candidate (stale index, repository unreachable)"
        apt_report_latest_resolution "$package"
        printf '%s\n' "$candidate"
        return 0
    fi

    # Forward only. A candidate at or above what the winning origins publish
    # means the local index already holds the better answer - another source
    # serves the package too, and apt would install that one.
    if [ -n "$candidate" ] && ! apt_version_gt "$published" "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi

    APT_LATEST_VERSION_SOURCE="repository index (local apt index is stale)"
    apt_report_latest_resolution "$package"
    printf '%s\n' "$published"
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

# Report the dpkg current-state word for a package ("installed", "unpacked",
# "half-configured", "config-files", ...), or nothing when dpkg does not know
# the package / dpkg is unavailable.
# Uses dpkg-query, which reads the status file without taking the dpkg lock, so
# it works for an unprivileged user.
# Usage: dpkg_package_state "code-insiders"
dpkg_package_state() {
    local package_name="$1"

    command -v dpkg-query &> /dev/null || return 1

    # ${Status} expands to three words: <want> <error-flag> <current-state>.
    dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | awk '{print $3}'
}

# True when dpkg knows the package but it is not fully configured — the files
# are unpacked on disk, yet the postinst never ran, so PATH symlinks and
# desktop entries the postinst creates are missing.
# Usage: dpkg_package_needs_configure "code-insiders"
dpkg_package_needs_configure() {
    local state
    state=$(dpkg_package_state "$1")

    case "$state" in
        ""|installed|config-files|not-installed) return 1 ;;
        *) return 0 ;;
    esac
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

#=============================================================================
# PIP ENVIRONMENT (PEP 668 externally-managed interpreters)
#=============================================================================
#
# Debian/Ubuntu ship an EXTERNALLY-MANAGED marker in the stdlib directory, so
# every `pip install` — including `--user`, which only ever writes to
# ~/.local — refuses to run until `--break-system-packages` is passed. Without
# that flag the pip snippet fails 100% of its packages instantly and has no
# error text left to explain why, so the probes and the output classifier live
# here where they are side-effect free and unit-testable.

# Does the interpreter backing pip carry a PEP 668 EXTERNALLY-MANAGED marker?
# Probes python3's own stdlib path rather than globbing /usr/lib, so it stays
# correct for pyenv/conda interpreters and for a future Python minor bump.
# A wrong answer degrades gracefully in both directions: a missed marker just
# means the install fails with its real reason reported, and a false positive
# only adds a flag that is a no-op on an unmanaged interpreter.
# Usage: pip_environment_is_externally_managed
# Returns: 0 when the marker is present, 1 otherwise
pip_environment_is_externally_managed() {
    local stdlib
    stdlib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))' 2>/dev/null) || return 1
    [ -n "$stdlib" ] && [ -f "$stdlib/EXTERNALLY-MANAGED" ]
}

# Does this pip understand --break-system-packages? The flag arrived in pip
# 23.0.1; passing it to an older pip is a hard "no such option" error, so the
# capability is probed rather than assumed from a parsed version string.
# Usage: pip_supports_break_system_packages "<pip_bin>"
# Returns: 0 when supported, 1 otherwise
pip_supports_break_system_packages() {
    local pip_bin="${1:-pip3}"
    "$pip_bin" install --help 2>/dev/null | grep -q -- '--break-system-packages'
}

# Pure matcher: did this pip output fail the PEP 668 guard? Kept separate from
# the probe above so a failure can be attributed after the fact, even when the
# marker probe guessed wrong.
# Usage: pip_output_is_externally_managed "<captured pip output>"
# Returns: 0 if the signature is present, 1 otherwise
pip_output_is_externally_managed() {
    printf '%s' "$1" | grep -qiE 'externally[- ]managed[- ]environment|This environment is externally managed'
}

# Pure classifier: reduce captured pip output to one human-readable cause.
# The snippet prints this next to the package name instead of guessing, so a
# PEP 668 refusal is never reported as a missing compiler.
# Usage: pip_failure_reason "<captured pip output>"
# Returns: always 0; prints a single line
pip_failure_reason() {
    local output="$1"

    if pip_output_is_externally_managed "$output"; then
        printf '%s\n' 'externally-managed environment (PEP 668)'
        return 0
    fi

    if printf '%s' "$output" | grep -qiE 'Failed building wheel|Microsoft Visual C\+\+|Python\.h: No such file|error: command .* failed with exit|gcc: (error|not found)'; then
        printf '%s\n' 'build failed — needs compiler/headers'
        return 0
    fi

    if printf '%s' "$output" | grep -qiE 'Temporary failure in name resolution|Read timed out|Connection (refused|reset)|Network is unreachable|Max retries exceeded'; then
        printf '%s\n' 'network error reaching the package index'
        return 0
    fi

    if printf '%s' "$output" | grep -qiE 'ResolutionImpossible|conflicting dependencies|dependency conflicts'; then
        printf '%s\n' 'dependency conflict'
        return 0
    fi

    if printf '%s' "$output" | grep -qiE 'No matching distribution found|Could not find a version'; then
        printf '%s\n' 'no matching distribution for this Python'
        return 0
    fi

    if printf '%s' "$output" | grep -qiE 'Permission denied|\[Errno 13\]|Read-only file system'; then
        printf '%s\n' 'permission denied writing the target directory'
        return 0
    fi

    # Nothing recognised: echo pip's own last meaningful line rather than
    # inventing a cause. Better an unfamiliar message than a wrong diagnosis.
    local last
    last=$(printf '%s\n' "$output" | grep -vE '^[[:space:]]*$' | tail -n 1 | cut -c1-160)
    if [ -n "$last" ]; then
        printf '%s\n' "$last"
    else
        printf '%s\n' 'pip exited non-zero with no output'
    fi
}
