#!/bin/bash
#
# update_claude_desktop.sh - Claude Desktop (Linux) Update Manager
# SNIPPET_ID: claude-desktop
# SNIPPET_NAME: Claude Desktop (Linux .deb)
#
# Claude Desktop on Linux now ships two ways, and the installed package can
# come from either, so this snippet picks the channel that is actually in use:
#
#   apt      - Anthropic's own repository (downloads.claude.ai/claude-desktop/apt).
#              When an enabled apt source serves the package, apt is both the
#              version source and the install channel.
#   apt-pool - Anthropic's build installed without that repository registered
#              (the documented CLAUDE_DESKTOP_ADD_REPO="false" install, or a
#              pool .deb installed by hand). Still the official channel: the
#              version comes from the repository's pool index and the update
#              reinstalls from that same pool.
#   github   - the community packaging aaddrick/claude-desktop-debian, which
#              ships prebuilt .deb assets on its GitHub releases. Used only
#              when no apt source carries the package and the installed one is
#              not Anthropic's own build.
#
# On the apt channel the "latest" version does not come from the local apt
# index alone. That index is only as fresh as the last `apt-get update`, which
# --check-only and --snippet deliberately never run, so a stale candidate
# reported a superseded version as the latest. Past a freshness window the
# repository's own Packages index is read over HTTPS instead - no sudo, no
# apt-get update - and `apt-get update && apt-get install --only-upgrade` then
# reaches exactly that version, so the invariant below still holds.
#
# Mixing the two is what the channel must prevent: the community releases trail
# Anthropic's own repository, so checking an apt-installed package against
# GitHub reports the installed version as "newer than latest release" (or, the
# other way round, offers a .deb that apt would overwrite on the next upgrade).
#
# Within each channel the comparison stays like-for-like: the current version
# is the installed dpkg version, and the latest version is the dpkg version of
# the exact artifact we would install - the apt candidate, or the matching
# release asset whose URL we download. We never report an update that cannot be
# applied (see snippet-install-channel-vs-version-source note).
#
# References: https://github.com/aaddrick/claude-desktop-debian
#
# Version: 0.3.0-alpha
# Date: 2026-10-12
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.3.0-alpha (2026-10-12) - Resolve the apt-channel latest version from the
#                              repository's Packages index when the local apt
#                              index is stale, so read-only discovery stops
#                              reporting a superseded candidate as the latest
#                            - New apt-pool channel for Anthropic's build
#                              installed without the repository registered,
#                              which previously fell through to the community
#                              GitHub packaging and reported ahead_of_latest
#                            - Respect an apt hold rather than promising an
#                              upgrade that could not be applied
#   0.2.0-alpha (2026-10-06) - Detect the install channel; prefer Anthropic's
#                              official apt repository over the community
#                              GitHub packaging when apt serves the package
#   0.1.0-alpha (2026-07-07) - Initial alpha version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$SCRIPT_DIR/claude_desktop.yaml"

# dpkg package names to probe, in preference order. The first one that is
# installed determines both the current version and which release asset we
# select, so the update stays on the same packaging variant.
CLAUDE_DESKTOP_PACKAGES=("claude-desktop" "claude-desktop-unofficial")

# Populated by claude_desktop_version_check for the update handler.
CLAUDE_DESKTOP_PKG=""
CLAUDE_DESKTOP_VERSION=""
CLAUDE_DESKTOP_DEB_URL=""
# "apt", "apt-pool" or "github" - which channel the installed package came from.
CLAUDE_DESKTOP_CHANNEL=""
# Human-readable provenance of LATEST_VERSION, so a reported version always
# says which authority produced it.
CLAUDE_DESKTOP_LATEST_SOURCE=""

# The apt candidate version for a package, verbatim.
# Args: <pkg>; echoes the candidate, or nothing when apt has none.
#
# Unlike get_apt_latest_version this keeps any Debian revision suffix: the
# current version it is compared against is the dpkg version of the same
# package, so stripping "-1" off one side only would make an unchanged package
# look newer than its own candidate.
claude_desktop_apt_candidate() {
    local candidate
    candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || return 1
    printf '%s\n' "$candidate"
}

# The dpkg architecture, which names both the pool asset and the release asset.
claude_desktop_arch() {
    local arch
    arch=$(dpkg --print-architecture 2>/dev/null)
    printf '%s\n' "${arch:-amd64}"
}

# True when the installed package is Anthropic's own build rather than the
# community packaging. The dpkg Maintainer field is the discriminator, and it
# travels with the package, so it answers even when no apt source is registered
# and the version table says nothing about where the .deb came from.
claude_desktop_package_is_official() {
    local maintainer needle
    maintainer=$(dpkg-query -W -f='${Maintainer}' "$1" 2>/dev/null)
    [ -n "$maintainer" ] || return 1

    needle=$(get_config apt_repository.official_maintainer)
    [ -n "$needle" ] || needle="Anthropic"

    case "$maintainer" in
        *"$needle"*) return 0 ;;
        *) return 1 ;;
    esac
}

# The highest version Anthropic's repository publishes for this architecture,
# read from its own Packages index over HTTPS.
claude_desktop_published_version() {
    local base suite component
    base=$(get_config apt_repository.base_url)
    [ -n "$base" ] || return 1
    suite=$(get_config apt_repository.suite)
    component=$(get_config apt_repository.component)

    fetch_debian_repo_latest_version \
        "$base" "${suite:-stable}" "${component:-main}" "$(claude_desktop_arch)"
}

# Resolve the latest version on the apt channel and record where it came from.
# Sets LATEST_VERSION and CLAUDE_DESKTOP_LATEST_SOURCE (so it must not run in a
# subshell); returns 1 when no authority yields a version at all.
#
# The apt candidate is the better answer while the local index is fresh: it
# accounts for pinning and apt preferences, so it is the version an upgrade
# would actually install. But the index is only as fresh as the last
# `apt-get update`, and --check-only and --snippet deliberately never run one,
# so the candidate they read can name a long-superseded version. Past the
# freshness window the cached candidate is not evidence, and the repository's
# own index - public, no sudo, no apt-get update - is consulted instead.
claude_desktop_resolve_apt_latest() {
    local candidate
    candidate=$(claude_desktop_apt_candidate "$CLAUDE_DESKTOP_PKG") || candidate=""

    LATEST_VERSION="$candidate"
    CLAUDE_DESKTOP_LATEST_SOURCE="apt candidate"

    local host max_age
    host=$(get_config apt_repository.host)
    max_age=$(get_config apt_repository.index_max_age_seconds)
    [ -n "$host" ] || return 0

    apt_index_is_stale "$host" "${max_age:-3600}" || return 0

    # Held back: the repository's newest version could not be installed even if
    # we reported it, and this snippet never reports an update it cannot apply.
    if apt_package_is_held "$CLAUDE_DESKTOP_PKG"; then
        print_warning "$APP_DISPLAY_NAME is held by apt - reporting the held candidate"
        return 0
    fi

    local published
    published=$(claude_desktop_published_version) || published=""
    if [ -z "$published" ]; then
        [ -n "$LATEST_VERSION" ] || return 1
        print_warning "Local apt index is stale and $host is unreachable - '$LATEST_VERSION' may be out of date"
        CLAUDE_DESKTOP_LATEST_SOURCE="apt candidate (stale index, repository unreachable)"
        return 0
    fi

    # Only ever move the answer forward. A candidate ahead of what the index
    # publishes means another source serves this package too, and apt would
    # install that one.
    if [ -n "$candidate" ] && ! dpkg --compare-versions "$published" gt "$candidate"; then
        return 0
    fi

    LATEST_VERSION="$published"
    CLAUDE_DESKTOP_LATEST_SOURCE="repository index (local apt index is stale)"
    return 0
}

# Echoes "<version> <download-url>" for the highest version Anthropic's pool
# publishes for an architecture. Args: <arch>; returns 1 when unresolvable.
claude_desktop_pool_asset() {
    local arch="$1"
    local base suite component index
    base=$(get_config apt_repository.base_url)
    [ -n "$base" ] || return 1
    suite=$(get_config apt_repository.suite)
    component=$(get_config apt_repository.component)

    index=$(fetch_debian_repo_index \
        "$base" "${suite:-stable}" "${component:-main}" "$arch") || return 1

    local best_ver="" best_path="" ver path
    while read -r ver path; do
        [[ "$ver" =~ ^[0-9][A-Za-z0-9.+:~-]*$ ]] || continue

        # Filename is external input that becomes a download URL. Keep it a
        # relative path inside the pool so a rewritten index cannot aim the
        # download at another host or walk out of the repository.
        case "$path" in
            pool/*) ;;
            *) continue ;;
        esac
        case "$path" in
            *..*) continue ;;
        esac
        case "${path##*/}" in
            "${CLAUDE_DESKTOP_PKG}"_*.deb) ;;
            *) continue ;;
        esac

        if [ -z "$best_ver" ] || dpkg --compare-versions "$ver" gt "$best_ver"; then
            best_ver="$ver"
            best_path="$path"
        fi
    done < <(printf '%s\n' "$index" | awk '
        BEGIN { RS = "" }
        {
            ver = ""; fn = ""
            n = split($0, lines, "\n")
            for (i = 1; i <= n; i++) {
                if (lines[i] ~ /^Version:[[:space:]]/) {
                    sub(/^Version:[[:space:]]*/, "", lines[i]); ver = lines[i]
                } else if (lines[i] ~ /^Filename:[[:space:]]/) {
                    sub(/^Filename:[[:space:]]*/, "", lines[i]); fn = lines[i]
                }
            }
            if (ver != "" && fn != "") print ver " " fn
        }')

    [ -n "$best_ver" ] && [ -n "$best_path" ] || return 1
    printf '%s %s\n' "$best_ver" "${base%/}/${best_path}"
}

# Detect the installed Claude Desktop package and its dpkg version.
# Sets the globals CLAUDE_DESKTOP_PKG and CLAUDE_DESKTOP_VERSION directly (must
# not run in a subshell, or those assignments would be lost); returns 1 if none
# of the candidate packages are installed.
detect_installed_claude_desktop() {
    local pkg version
    for pkg in "${CLAUDE_DESKTOP_PACKAGES[@]}"; do
        version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
        if [ -n "$version" ]; then
            CLAUDE_DESKTOP_PKG="$pkg"
            CLAUDE_DESKTOP_VERSION="$version"
            return 0
        fi
    done
    return 1
}

# Find the newest release asset matching "<pkg>_<version>_<arch>.deb".
# Args: <release-json> <pkg> <arch>
# Echoes: "<version> <download-url>" for the highest version, or nothing.
select_claude_desktop_asset() {
    local json="$1" pkg="$2" arch="$3"
    printf '%s\n' "$json" \
        | grep -oE '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | while IFS= read -r url; do
            local base="${url##*/}"
            if [[ "$base" =~ ^${pkg}_([0-9][^_]*)_${arch}\.deb$ ]]; then
                printf '%s %s\n' "${BASH_REMATCH[1]}" "$url"
            fi
        done \
        | sort -V \
        | tail -1
}

# Fetch the latest-release JSON, tolerating an exhausted anonymous GitHub REST
# rate limit (60 req/hr per IP) which is easy to hit mid-scan. Tries the
# anonymous API first, then the authenticated `gh` CLI if it is installed.
# Echoes JSON containing browser_download_url entries; returns 1 if none found.
fetch_claude_desktop_release_json() {
    local owner="$1" repo="$2" json
    json=$(curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${owner}/${repo}/releases/latest" 2>/dev/null)
    if printf '%s' "$json" | grep -q '"browser_download_url"'; then
        printf '%s' "$json"
        return 0
    fi

    if command -v gh >/dev/null 2>&1; then
        json=$(gh api "repos/${owner}/${repo}/releases/latest" 2>/dev/null)
        if printf '%s' "$json" | grep -q '"browser_download_url"'; then
            printf '%s' "$json"
            return 0
        fi
    fi

    return 1
}

# True if a URL is fetchable (follows redirects, fails on HTTP >= 400). Uses a
# single-byte range request so it does not download the whole .deb.
claude_desktop_url_reachable() {
    curl -fsL -r 0-0 -o /dev/null "$1" 2>/dev/null
}

# Fallback when the REST API is unavailable: resolve the latest version from the
# git tag over the git protocol (not rate-limited like the REST API) and build
# the stable per-release download URL. The tag looks like "3.0.1+claude1.18286.0"
# where 3.0.1 is the packaging revision and 1.18286.0 the Claude app version.
# Sets LATEST_VERSION and CLAUDE_DESKTOP_DEB_URL only if the constructed asset
# URL actually resolves, so we never advertise an update we cannot install.
# Args: <owner> <repo> <pkg> <arch>; returns 1 if it cannot resolve.
resolve_claude_desktop_from_tag() {
    local owner="$1" repo="$2" pkg="$3" arch="$4"
    local tag pkgrev appver filename url

    tag=$(get_github_latest_remote_tag_fallback "$owner" "$repo")
    [ -n "$tag" ] || return 1
    case "$tag" in
        *+claude*) ;;
        *) return 1 ;;
    esac

    pkgrev="${tag%%+*}"
    appver="${tag#*+claude}"
    [ -n "$appver" ] || return 1

    if [ "$pkg" = "claude-desktop-unofficial" ]; then
        filename="${pkg}_${appver}-${pkgrev}_${arch}.deb"
        LATEST_VERSION="${appver}-${pkgrev}"
    else
        filename="${pkg}_${appver}_${arch}.deb"
        LATEST_VERSION="${appver}"
    fi

    url="https://github.com/${owner}/${repo}/releases/latest/download/${filename}"
    if claude_desktop_url_reachable "$url"; then
        CLAUDE_DESKTOP_DEB_URL="$url"
        return 0
    fi

    LATEST_VERSION=""
    return 1
}

# Resolve current/latest versions and, on the github channel, the download URL.
# Sets CURRENT_VERSION, LATEST_VERSION, VERSION_STATUS, APP_DISPLAY_NAME,
# CLAUDE_DESKTOP_PKG, CLAUDE_DESKTOP_CHANNEL, CLAUDE_DESKTOP_DEB_URL.
# Returns 1 if it cannot proceed.
claude_desktop_version_check() {
    print_operation_header "$(get_config messages.checking_updates)"

    APP_DISPLAY_NAME=$(get_config application.display_name)
    [ -n "$APP_DISPLAY_NAME" ] || APP_DISPLAY_NAME="Claude Desktop"

    # Not installed -> not an error, just guidance.
    if ! detect_installed_claude_desktop; then
        print_warning "$APP_DISPLAY_NAME is not installed"
        local install_help
        install_help=$(get_config messages.install_help)
        [ -n "$install_help" ] && printf '%s\n' "$install_help"
        return 1
    fi
    CURRENT_VERSION="$CLAUDE_DESKTOP_VERSION"

    LATEST_VERSION=""
    CLAUDE_DESKTOP_DEB_URL=""
    CLAUDE_DESKTOP_LATEST_SOURCE=""
    CLAUDE_DESKTOP_CHANNEL="github"

    local arch
    arch=$(claude_desktop_arch)

    # Preferred channel: Anthropic's own apt repository, when an enabled source
    # serves this package. Both sides are then dpkg versions of the same
    # package from the same repository, and the upgrade is a plain apt one.
    if apt_package_is_repo_served "$CLAUDE_DESKTOP_PKG"; then
        CLAUDE_DESKTOP_CHANNEL="apt"
        print_status "Tracking $APP_DISPLAY_NAME through apt (package: $CLAUDE_DESKTOP_PKG)"
        if ! claude_desktop_resolve_apt_latest; then
            # compare_and_report_versions emits an "unknown" summary event.
            compare_and_report_versions "$CURRENT_VERSION" "" "$APP_DISPLAY_NAME"
            VERSION_STATUS=$?
            print_error "$(get_config messages.failed_latest) (package: $CLAUDE_DESKTOP_PKG)"
            return 1
        fi
        print_status "Latest version source: $CLAUDE_DESKTOP_LATEST_SOURCE"
        compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
        VERSION_STATUS=$?
        return 0
    fi

    # No apt source serves it, but it is Anthropic's own build: this is the
    # documented repo-less install (/etc/default/claude-desktop setting
    # CLAUDE_DESKTOP_ADD_REPO="false", or a .deb installed from the pool by
    # hand), so it stays on the official pool. Falling through to the community
    # releases here would be exactly the channel mismatch this snippet exists
    # to prevent: those trail the official repository by a whole major version,
    # so an official 2.x package reads as "newer than latest release" and the
    # scan reports noise instead of an answer.
    if claude_desktop_package_is_official "$CLAUDE_DESKTOP_PKG"; then
        CLAUDE_DESKTOP_CHANNEL="apt-pool"
        print_status "Tracking $APP_DISPLAY_NAME through Anthropic's package pool (package: $CLAUDE_DESKTOP_PKG, no apt source registered)"

        local pool_asset
        if pool_asset=$(claude_desktop_pool_asset "$arch"); then
            LATEST_VERSION="${pool_asset%% *}"
            CLAUDE_DESKTOP_DEB_URL="${pool_asset#* }"
            CLAUDE_DESKTOP_LATEST_SOURCE="repository pool index"
        fi

        if [ -z "$LATEST_VERSION" ] || [ -z "$CLAUDE_DESKTOP_DEB_URL" ]; then
            compare_and_report_versions "$CURRENT_VERSION" "" "$APP_DISPLAY_NAME"
            VERSION_STATUS=$?
            print_error "$(get_config messages.failed_latest) (package: $CLAUDE_DESKTOP_PKG, arch: $arch)"
            return 1
        fi

        print_status "Latest version source: $CLAUDE_DESKTOP_LATEST_SOURCE"
        compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
        VERSION_STATUS=$?
        return 0
    fi

    local owner repo
    owner=$(get_config repository.owner)
    repo=$(get_config repository.repo)

    # Preferred within the github channel: read the actual asset list from the
    # release JSON.
    local release_json asset
    if release_json=$(fetch_claude_desktop_release_json "$owner" "$repo"); then
        asset=$(select_claude_desktop_asset "$release_json" "$CLAUDE_DESKTOP_PKG" "$arch")
        if [ -n "$asset" ]; then
            LATEST_VERSION="${asset%% *}"
            CLAUDE_DESKTOP_DEB_URL="${asset#* }"
            CLAUDE_DESKTOP_LATEST_SOURCE="GitHub release asset"
        fi
    fi

    # Fallback: API unreachable/rate-limited -> derive from the git tag and the
    # stable release-download URL so a scan still reports a real version.
    if [ -z "$LATEST_VERSION" ] || [ -z "$CLAUDE_DESKTOP_DEB_URL" ]; then
        resolve_claude_desktop_from_tag "$owner" "$repo" "$CLAUDE_DESKTOP_PKG" "$arch"
    fi

    if [ -z "$LATEST_VERSION" ] || [ -z "$CLAUDE_DESKTOP_DEB_URL" ]; then
        # compare_and_report_versions emits an "unknown" summary event for us.
        compare_and_report_versions "$CURRENT_VERSION" "" "$APP_DISPLAY_NAME"
        VERSION_STATUS=$?
        print_error "$(get_config messages.failed_latest) (package: $CLAUDE_DESKTOP_PKG, arch: $arch)"
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?
    return 0
}

# Pre-flight shared by both channels: installing needs root either way. Bail
# before doing any work in a non-interactive context without cached sudo
# credentials, rather than downloading a package we cannot install.
# Args: <command the operator would have to authorise>
claude_desktop_require_sudo() {
    sudo_can_run && return 0

    emit_sudo_required_event "$1" "false"
    print_error "Sudo credentials required to install ${APP_DISPLAY_NAME}"
    print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
    return 1
}

# Confirm the installed package actually advanced to the version we resolved.
verify_claude_desktop_update() {
    if ! detect_installed_claude_desktop; then
        print_error "Failed to verify active $APP_DISPLAY_NAME version after update"
        return 1
    fi
    local verified_version="$CLAUDE_DESKTOP_VERSION"
    print_status "Verified version: $verified_version"

    local verify_cmp
    compare_versions "$verified_version" "$LATEST_VERSION"
    verify_cmp=$?
    if [ "$verify_cmp" -eq 2 ]; then
        print_error "$APP_DISPLAY_NAME update did not reach the expected version: $verified_version < $LATEST_VERSION"
        return 1
    fi

    return 0
}

claude_desktop_success_message() {
    local success_msg
    success_msg=$(get_config messages.update_success)
    printf '%s\n' "${success_msg:-$APP_DISPLAY_NAME updated successfully}"
}

# apt channel: upgrade in place from the repository that already serves the
# package. No download or dpkg -i of our own - that would install the community
# build over the official one and swap the machine onto the other channel.
perform_claude_desktop_apt_update() {
    claude_desktop_require_sudo "apt-get install --only-upgrade ${CLAUDE_DESKTOP_PKG}" || return 1

    print_status "$(get_config messages.installing)"
    if ! update_via_package_manager "$CLAUDE_DESKTOP_PKG"; then
        print_error "Failed to upgrade $APP_DISPLAY_NAME via apt"
        return 1
    fi

    verify_claude_desktop_update || return 1

    print_success "$(claude_desktop_success_message)"
    return 0
}

# github channel: download the matching release asset and install it with dpkg.
perform_claude_desktop_deb_update() {
    local output_lines fix_deps
    output_lines=$(get_config update.output_lines)
    output_lines="${output_lines:-20}"
    fix_deps=$(get_config update.fix_dependencies)

    claude_desktop_require_sudo "dpkg -i <package for ${APP_DISPLAY_NAME}>" || return 1

    local temp_file
    temp_file=$(mktemp "/tmp/claude-desktop-XXXXXX.deb") || return 1

    print_status "$(get_config messages.downloading)"
    local download_output download_rc
    download_output=$(wget -nv -O "$temp_file" "$CLAUDE_DESKTOP_DEB_URL" 2>&1)
    download_rc=$?
    if [ "$download_rc" -ne 0 ]; then
        emit_captured_output "$download_output" "$output_lines"
        print_error "Failed to download $APP_DISPLAY_NAME package"
        rm -f "$temp_file"
        return 1
    fi
    emit_captured_output "$download_output" "$output_lines"

    print_status "$(get_config messages.installing)"
    local install_output install_exit_code
    install_output=$(run_with_sudo dpkg -i "$temp_file" 2>&1)
    install_exit_code=$?
    emit_captured_output "$install_output" "$output_lines"

    if [ -n "$fix_deps" ]; then
        if [ $install_exit_code -ne 0 ]; then
            print_warning "dpkg reported issues; attempting dependency repair"
        fi
        local -a fix_args=()
        read -r -a fix_args <<< "$fix_deps"
        local fix_output fix_rc
        fix_output=$(run_with_sudo "${fix_args[@]}" 2>&1)
        fix_rc=$?
        if [ "$fix_rc" -ne 0 ]; then
            emit_captured_output "$fix_output" "$output_lines"
            print_error "Failed to repair dependencies for $APP_DISPLAY_NAME"
            rm -f "$temp_file"
            return 1
        fi
        emit_captured_output "$fix_output" "$output_lines"
    elif [ $install_exit_code -ne 0 ]; then
        print_error "Failed to install $APP_DISPLAY_NAME package"
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"

    verify_claude_desktop_update || return 1

    print_success "$(claude_desktop_success_message)"
    return 0
}

# Route to the channel the installed package actually came from.
perform_claude_desktop_update() {
    case "$CLAUDE_DESKTOP_CHANNEL" in
        apt)
            perform_claude_desktop_apt_update
            ;;
        *)
            # apt-pool and github both install a downloaded .deb. Each stays on
            # its own channel because CLAUDE_DESKTOP_DEB_URL was resolved from
            # that channel's index - the official pool, or the community
            # release assets.
            perform_claude_desktop_deb_update
            ;;
    esac
}

update_claude_desktop() {
    if ! claude_desktop_version_check; then
        ask_continue
        return 0
    fi

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_claude_desktop_update"; then
        ask_continue
        return 1
    fi
}

update_claude_desktop
