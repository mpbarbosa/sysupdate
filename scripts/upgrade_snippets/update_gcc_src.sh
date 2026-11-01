#!/bin/bash
#
# update_gcc_src.sh - GCC from upstream source (private prefix) Update Manager
# SNIPPET_ID: gcc-src
# SNIPPET_NAME: GCC (upstream source, private prefix)
#
# Tracks the GNU Compiler Collection as upstream releases it, and installs it
# into a private versioned prefix (<root>/gcc-<version>, root configurable via
# SYSUPDATE_GCC_SRC_PREFIX_ROOT). This runs *alongside* the apt-based `gcc`
# snippet and does not replace it: that one answers "what will apt install",
# this one answers "what has upstream released, against my own source build".
# The two can legitimately disagree by several releases.
#
# See gcc_src.yaml for the full rationale, in particular:
#   - why this is a separate snippet instead of a second version source on
#     gcc.yaml (the version source has to match the install channel, or the
#     snippet announces an update it cannot apply - the matchmaker defect);
#   - why the install never goes to /usr (dpkg owns /usr/bin/gcc and the shared
#     libgcc_s / libstdc++ every C++ binary on the host links against);
#   - what a build costs (3-stage bootstrap: an hour-plus of CPU, ~10 GB of
#     build tree), and why it is confirmed, space-checked and never started in
#     --check-only;
#   - the libstdc++ runtime consequence of actually using the result, which this
#     snippet only prints (it never writes /etc/ld.so.conf.d).
#
# Reference: https://gcc.gnu.org/install/
#
# Version: 0.1.0-alpha
# Date: 2026-10-31
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2026-10-31) - Initial alpha version, upstream source build
#
# Dependencies (checked before a build, never at check time):
#   - git, make, gcc, g++, tar, bzip2, flex, bison
#   - wget or curl (for contrib/download_prerequisites)
#   GMP/MPFR/MPC/ISL are fetched by contrib/download_prerequisites rather than
#   required from the system.

GCC_SRC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$GCC_SRC_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# shellcheck disable=SC2034
CONFIG_FILE="$GCC_SRC_SCRIPT_DIR/gcc_src.yaml"

#=============================================================================
# PREFIX DISCOVERY
#=============================================================================

# The directory that holds the versioned prefixes.
#
# Overridable so the toolchain can live under "${XDG_DATA_HOME:-~/.local/share}"
# instead of /opt, which also removes the need for sudo at install time.
gcc_src_prefix_root() {
    local configured
    configured=$(get_config "prefix.root")
    printf '%s\n' "${SYSUPDATE_GCC_SRC_PREFIX_ROOT:-${configured:-/opt}}"
}

# The driver-name suffix for a release, e.g. "-upstream-16" for 16.2.0.
#
# Deliberately not the distro's own "-<major>" shape: apt already owns gcc-16,
# so a bare major suffix would collide the moment the prefix's bin/ reaches
# PATH, which is the one thing the prefix exists to prevent.
# Usage: gcc_src_program_suffix 16.2.0
gcc_src_program_suffix() {
    local version="$1"
    local suffix_prefix
    suffix_prefix=$(get_config "prefix.program_suffix_prefix")
    printf '%s%s\n' "${suffix_prefix:--upstream-}" "${version%%.*}"
}

# The three-part release a compiler driver reports for itself, e.g. "16.2.0".
#
# -dumpfullversion prints exactly the upstream release with no distro build
# string around it, which is what makes it directly comparable with a release
# tag. The value comes from an external binary, so it is returned only when it
# really is a dotted-numeric version - that also rejects the gcc-ar / gcc-nm
# wrappers that share the driver's name prefix.
# Usage: gcc_src_driver_release /opt/gcc-16.2.0/bin/gcc-upstream-16
gcc_src_driver_release() {
    local driver="$1"
    local version

    [ -x "$driver" ] || return 1

    version=$("$driver" -dumpfullversion 2>/dev/null) || return 1
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1

    printf '%s\n' "$version"
}

# The highest-versioned upstream prefix install found under the prefix root.
#
# Echoes "<version> <driver-path>" and returns 0, or returns 1 when there is no
# usable install. Several versioned prefixes can coexist (that is the point of
# versioning them), so the comparison is made against the newest one.
#
# The version is read from the driver rather than parsed out of the directory
# name: the directory name is just a label this snippet wrote, while the driver
# is the thing that will actually compile.
gcc_src_installed_prefix() {
    local root
    root=$(gcc_src_prefix_root)
    local best_version="" best_driver="" driver version

    [ -d "$root" ] || return 1

    for driver in "$root"/gcc-*/bin/gcc*; do
        [ -x "$driver" ] || continue
        # The binutils wrappers installed next to the driver carry the same
        # name prefix; they do not understand -dumpfullversion.
        case "${driver##*/}" in
            *gcc-ar*|*gcc-nm*|*gcc-ranlib*) continue ;;
        esac

        version=$(gcc_src_driver_release "$driver") || continue

        if [ -z "$best_version" ]; then
            best_version="$version"
            best_driver="$driver"
            continue
        fi

        # compare_versions returns 2 when the first argument is the older one.
        compare_versions "$best_version" "$version"
        local cmp_result=$?
        if [ "$cmp_result" -eq 2 ]; then
            best_version="$version"
            best_driver="$driver"
        fi
    done

    [ -n "$best_version" ] || return 1

    printf '%s %s\n' "$best_version" "$best_driver"
}

#=============================================================================
# UPSTREAM RELEASE DISCOVERY
#=============================================================================

# The highest release upstream has tagged, e.g. "16.2.0".
#
# `git ls-remote --tags` on the project's own repository, restricted to the
# releases/gcc-* namespace and reduced by select_highest_semver_tag. No token
# and no API quota: the GitHub REST path against the gcc-mirror/gcc mirror is
# subject to the anonymous rate limit that has already produced "unknown"
# version reports elsewhere in this repo.
#
# The namespace filter is load-bearing. The same tag namespace holds
# basepoints/gcc-16 and prereleases/gcc-2.95.3-test1 (which
# select_highest_semver_tag drops for having no dot / a trailing suffix) but
# also libgcj-2.95.1 and libf2c-0.5.22, which are bare semver and would be
# eligible on their own merits. releases/gcc-* is the only namespace that means
# "a GCC release".
gcc_src_latest_release() {
    local repo namespace version
    repo=$(get_config "application.git_repo")
    namespace=$(get_config "version.tag_namespace")

    if [ -z "$repo" ] || ! command -v git &> /dev/null; then
        return 1
    fi

    version=$(git ls-remote --tags "$repo" 2>/dev/null \
        | grep -F "${namespace:-refs/tags/releases/gcc-}" \
        | select_highest_semver_tag)

    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1

    printf '%s\n' "$version"
}

#=============================================================================
# BUILD PRE-FLIGHT
#=============================================================================

# Print a blocking status's remediation text, if the YAML carries one.
#
# get_remediation returns an empty string for a key it cannot resolve, and
# consumers are expected to treat empty as "no remediation" - printing it
# unguarded puts a bare "ℹ️" line in the log.
# Usage: gcc_src_print_remediation insufficient_space
gcc_src_print_remediation() {
    local text
    text=$(get_remediation "$1")
    [ -n "$text" ] && print_status "$text"
    return 0
}

# Free space in MB on the filesystem that holds a path, or its nearest existing
# ancestor - the prefix root and the build root may not exist yet.
# Echoes an integer, or returns 1 when df output cannot be trusted.
# Usage: gcc_src_free_mb /opt/gcc-16.2.0
gcc_src_free_mb() {
    local path="$1"
    local value

    while [ -n "$path" ] && [ "$path" != "/" ] && [ ! -d "$path" ]; do
        path=$(dirname "$path")
    done

    value=$(df -P -BM "$path" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'M')

    # Guard against unexpected df output (missing mount, wrapped device names).
    case "$value" in
        ''|*[!0-9]*) return 1 ;;
    esac

    printf '%s\n' "$value"
}

# True when a path's filesystem has at least the required MB free.
# Reports the shortfall by path and figure rather than a bare "no space".
# Usage: gcc_src_require_free_mb /opt 3000
gcc_src_require_free_mb() {
    local path="$1"
    local required="$2"
    local available

    if ! available=$(gcc_src_free_mb "$path"); then
        print_warning "Could not read free space for $path - proceeding without the check"
        return 0
    fi

    if [ "$available" -ge "$required" ]; then
        print_status "Free space on $path: ${available} MB (need ${required} MB)"
        return 0
    fi

    local message
    message=$(get_config "messages.insufficient_space")
    message="${message/\{path\}/$path}"
    message="${message/\{available\}/$available}"
    message="${message/\{required\}/$required}"
    print_error "$message"
    gcc_src_print_remediation "insufficient_space"
    return 1
}

# True when everything a build needs is on PATH.
#
# check_build_dependencies already names the missing commands; the downloader is
# an either/or that it cannot express, so it is checked separately.
gcc_src_check_build_prereqs() {
    local deps downloaders downloader found=false

    deps=$(get_config "build.deps")
    # shellcheck disable=SC2086
    if ! check_build_dependencies ${deps:-git make gcc g++ tar bzip2 flex bison}; then
        gcc_src_print_remediation "missing_build_deps"
        return 1
    fi

    downloaders=$(get_config "build.downloaders")
    for downloader in ${downloaders:-wget curl}; do
        if command -v "$downloader" &> /dev/null; then
            found=true
            break
        fi
    done

    if [ "$found" != true ]; then
        print_error "$(get_config "messages.missing_downloader")"
        return 1
    fi

    return 0
}

# Name the dependency or resource a failed build actually tripped over.
#
# A bare "build failed" after an hour of bootstrap is close to useless, and the
# cause is nearly always one of a small set of recognisable lines. The log is
# read from disk rather than held in a variable: a bootstrap log runs to
# megabytes. The greps are `|| true`-guarded so that a caller running under
# errexit still reaches the end of the classification.
# Usage: gcc_src_report_build_failure /path/to/build.log
gcc_src_report_build_failure() {
    local log="$1"

    [ -f "$log" ] || return 0

    if grep -qF 'Building GCC requires GMP' "$log" 2>/dev/null; then
        print_error "Build stopped on: GMP / MPFR / MPC - contrib/download_prerequisites did not leave them in the source tree"
    fi

    local pattern dependency
    # command -> the dependency its absence means
    for pattern in \
        'flex: command not found|flex' \
        'bison: command not found|bison' \
        'makeinfo: command not found|texinfo (makeinfo)' \
        'msgfmt: command not found|gettext (msgfmt)' \
        'No space left on device|free disk space on the build filesystem' \
        'cannot find -lz|zlib development headers' \
        'zlib.h: No such file|zlib development headers' \
        'comparison of stage2 and stage3|a miscompiling host compiler (stage2/stage3 comparison failed)'
    do
        dependency="${pattern#*|}"
        if grep -qF "${pattern%%|*}" "$log" 2>/dev/null; then
            print_error "Build stopped on: $dependency"
        fi
    done

    print_status "Full build log kept at: $log"
    return 0
}

#=============================================================================
# BUILD AND INSTALL
#=============================================================================

# Build one upstream release and install it into its own prefix.
#
# Layout: the source tree and the (out-of-tree) build tree both live in a
# temporary directory under TMPDIR, which is removed afterwards; only the
# install prefix survives. An in-prefix build would leave ~10 GB of object
# files inside the thing meant to be a clean toolchain.
#
# TMPDIR is honoured rather than hardcoding /tmp the way create_build_directory
# does: /tmp is a tmpfs on many systems, and a 10 GB bootstrap tree in RAM is
# not a build, it is an OOM.
# Usage: gcc_src_build_and_install 16.2.0
gcc_src_build_and_install() {
    local version="$1"
    local root prefix suffix repo languages
    root=$(gcc_src_prefix_root)
    prefix="$root/gcc-$version"
    suffix=$(gcc_src_program_suffix "$version")
    repo=$(get_config "application.git_repo")
    languages=$(get_config "build.languages")

    if [ -e "$prefix" ]; then
        print_error "Install prefix already exists: $prefix"
        print_status "Remove it (or point SYSUPDATE_GCC_SRC_PREFIX_ROOT elsewhere) and re-run"
        return 1
    fi

    gcc_src_check_build_prereqs || return 1

    local build_root
    build_root=$(mktemp -d -t gcc-src-build-XXXXXX) || {
        print_error "Could not create a build directory under ${TMPDIR:-/tmp}"
        return 1
    }

    gcc_src_require_free_mb "$build_root" "$(get_config "build.free_build_mb")" || {
        rm -rf "$build_root"
        return 1
    }
    gcc_src_require_free_mb "$root" "$(get_config "build.free_prefix_mb")" || {
        rm -rf "$build_root"
        return 1
    }

    # sudo is needed only when the prefix root is not ours to write.
    local install_sudo=""
    if [ ! -w "$root" ] && [ ! -w "$(dirname "$root")" ]; then
        install_sudo="sudo"
        if ! sudo_can_run; then
            print_error "Installing into $root needs sudo, which cannot be run without a terminal or askpass helper"
            rm -rf "$build_root"
            return 1
        fi
    fi

    local original_dir log
    original_dir=$(pwd)
    log="$build_root/build.log"

    local installing_msg
    installing_msg=$(get_config "messages.installing")
    print_status "${installing_msg/\{version\}/$version}"

    # A shallow clone of the one release tag: the full GCC history is several
    # gigabytes of its own and none of it is needed to build a release.
    print_status "Fetching source for GCC $version..."
    if ! git clone --depth 1 --branch "releases/gcc-$version" "$repo" "$build_root/gcc" >>"$log" 2>&1; then
        print_error "Failed to clone releases/gcc-$version from $repo"
        gcc_src_report_build_failure "$log"
        cd "$original_dir" > /dev/null 2>&1 || true
        return 1
    fi

    print_status "Downloading build prerequisites (GMP, MPFR, MPC, ISL)..."
    if ! (cd "$build_root/gcc" && ./contrib/download_prerequisites) >>"$log" 2>&1; then
        print_error "contrib/download_prerequisites failed - GMP/MPFR/MPC/ISL are not in the source tree"
        gcc_src_report_build_failure "$log"
        cd "$original_dir" > /dev/null 2>&1 || true
        return 1
    fi

    mkdir -p "$build_root/build"
    cd "$build_root/build" || { cd "$original_dir" > /dev/null 2>&1 || true; return 1; }

    print_status "Configuring with --prefix=$prefix --program-suffix=$suffix"
    if ! ../gcc/configure \
        --prefix="$prefix" \
        --program-suffix="$suffix" \
        --enable-languages="${languages:-c,c++}" \
        --disable-multilib \
        >>"$log" 2>&1; then
        print_error "configure failed for GCC $version"
        gcc_src_report_build_failure "$log"
        cd "$original_dir" > /dev/null 2>&1 || true
        return 1
    fi

    print_status "Bootstrapping (3 stages) - this is the hour-plus part..."
    if ! make -j"$(nproc 2>/dev/null || echo 2)" >>"$log" 2>&1; then
        print_error "Bootstrap failed for GCC $version"
        gcc_src_report_build_failure "$log"
        cd "$original_dir" > /dev/null 2>&1 || true
        return 1
    fi

    print_status "Installing into $prefix"
    if ! $install_sudo make install >>"$log" 2>&1; then
        print_error "make install into $prefix failed"
        gcc_src_report_build_failure "$log"
        cd "$original_dir" > /dev/null 2>&1 || true
        return 1
    fi

    cd "$original_dir" > /dev/null 2>&1 || true

    # Verify against the thing that will actually compile, not against make's
    # exit status: an install that lands in the wrong place or leaves a
    # non-functional driver exits 0 just the same.
    local installed_version
    if ! installed_version=$(gcc_src_driver_release "$prefix/bin/gcc$suffix"); then
        print_error "Installed, but $prefix/bin/gcc$suffix does not report a version - treating the install as failed"
        gcc_src_report_build_failure "$log"
        return 1
    fi

    if [ "$installed_version" != "$version" ]; then
        print_error "Installed driver reports $installed_version, expected $version"
        return 1
    fi

    # Only now is the build tree disposable.
    rm -rf "$build_root"

    print_status "Verified version: $installed_version"
    emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "up_to_date" "current_version" "$installed_version" "latest_version" "$version"
    print_success "$(get_config "messages.update_success")"
    gcc_src_report_runtime_note "$prefix" "$suffix"

    return 0
}

# Print the libstdc++ consequence of using the new toolchain.
#
# Both remedies are deliberate user choices with different blast radii, so the
# snippet states them and applies neither. Writing /etc/ld.so.conf.d would
# change the library search order for every process on the host.
# Usage: gcc_src_report_runtime_note /opt/gcc-16.2.0 -upstream-16
gcc_src_report_runtime_note() {
    local note
    note=$(get_config "messages.runtime_note")
    note="${note//\{prefix\}/$1}"
    note="${note//\{suffix\}/$2}"
    print_status "$note"
}

# The update action handed to handle_update_prompt.
#
# The generic "Update X?" prompt that got us here does not say what it costs, so
# the real confirmation - with the release, the prefix, the hour and the ~10 GB
# spelled out - happens here, immediately before anything is written.
perform_gcc_src_update() {
    local confirm root
    root=$(gcc_src_prefix_root)
    confirm=$(get_config "messages.confirm_build")
    confirm="${confirm//\{version\}/$LATEST_VERSION}"
    confirm="${confirm//\{prefix\}/$root/gcc-$LATEST_VERSION}"
    confirm="${confirm//\{build_root\}/${TMPDIR:-/tmp}}"
    print_status "$confirm"

    if ! prompt_yes_no "Start the GCC $LATEST_VERSION source build now?"; then
        print_status "Skipping GCC source build"
        return 0
    fi

    gcc_src_build_and_install "$LATEST_VERSION"
}

#=============================================================================
# SNIPPET ENTRY POINT
#=============================================================================

update_gcc_src() {
    APP_DISPLAY_NAME=$(get_config "application.display_name")
    [ -n "$APP_DISPLAY_NAME" ] || APP_DISPLAY_NAME="GCC (upstream source)"

    print_operation_header "$(get_config "messages.checking_updates")"

    local prefix_info driver=""
    CURRENT_VERSION=""
    if prefix_info=$(gcc_src_installed_prefix); then
        read -r CURRENT_VERSION driver <<< "$prefix_info"
    fi

    # Resolved before the not_installed branch on purpose: a dashboard entry
    # that says "nothing installed, upstream is at 16.2.0" is actionable, and
    # listing tags is read-only and cheap compared with what a build costs.
    LATEST_VERSION=$(gcc_src_latest_release) || LATEST_VERSION=""

    if [ -z "$CURRENT_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "not_installed" "current_version" "unknown" "latest_version" "${LATEST_VERSION:-unknown}"
        print_warning "$APP_DISPLAY_NAME not installed under $(gcc_src_prefix_root)"
        [ -n "$LATEST_VERSION" ] && print_status "Latest upstream release: $LATEST_VERSION"
        print_status "$(get_config "messages.install_help")"

        # The first build is an explicit opt-in, never a side effect of a
        # routine update run: the snippet is an updater, and an unprompted
        # hour-plus bootstrap is not an update.
        if [ "${SYSUPDATE_GCC_SRC_FIRST_BUILD:-false}" = true ] \
            && [ "$CHECK_ONLY_MODE" != true ] \
            && [ -n "$LATEST_VERSION" ]; then
            perform_gcc_src_update || { ask_continue; return 1; }
        fi

        ask_continue
        return 0
    fi

    print_status "Upstream prefix install: $driver"

    if [ -z "$LATEST_VERSION" ]; then
        emit_summary_event "version_check" "target" "$APP_DISPLAY_NAME" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
        print_error "$(get_config "messages.failed_latest")"
        ask_continue
        return 1
    fi

    compare_and_report_versions "$CURRENT_VERSION" "$LATEST_VERSION" "$APP_DISPLAY_NAME"
    VERSION_STATUS=$?

    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" "perform_gcc_src_update"; then
        ask_continue
        return 1
    fi
}

update_gcc_src
