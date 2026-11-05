#!/usr/bin/env bash
#
# setup-hyprland-alternatives.sh
#
# Register the apt Hyprland and an upstream (source-built) Hyprland as a single
# `Hyprland` update-alternatives group so you can switch between them:
#   - generic link:  /usr/local/bin/Hyprland   (precedes /usr/bin in PATH)
#   - master/slave:  Hyprland + hyprctl + hyprpm switch together (version-locked)
#   - upstream built into an ISOLATED prefix /opt/hyprland (bin + lib + share),
#     with an install RPATH so it resolves its OWN libraries and can never
#     collide with apt's /usr/lib hypr* libs (that collision is what broke the
#     previous /usr/local source build — see docs/hyprland-status.md).
#
# Unlike kitty (a self-contained app bundle), Hyprland is a compositor with a
# dependency chain (hyprutils/hyprlang/hyprcursor/aquamarine/...). Building a
# newer upstream than apt ships generally requires those deps at matching
# versions too. This script attempts the documented CMake build; if the deps
# are not satisfiable it aborts with an actionable message rather than producing
# a silently-broken binary. See docs/hyprland-dual-install-assessment.md.
#
# Run with sudo:
#   sudo bash setup-hyprland-alternatives.sh [--ref <tag>] [--jobs N]
#   sudo bash setup-hyprland-alternatives.sh --with-deps      # also build hypr* libs apt lacks (hyprutils, hyprgraphics)
#   sudo bash setup-hyprland-alternatives.sh --with-deps=hyprutils,hyprgraphics  # custom dep list
#   sudo bash setup-hyprland-alternatives.sh --with-deps=aquamarine@v0.14.0       # pin a dep to a tag
#   sudo bash setup-hyprland-alternatives.sh --cxx clang++    # override the compiler (default: auto, see NOTE)
#   sudo bash setup-hyprland-alternatives.sh --skip-build     # register only (upstream already in /opt/hyprland)
#   sudo bash setup-hyprland-alternatives.sh --remove         # tear the group down (leaves both installs)
#
# NOTE: the compiler is chosen automatically, starting from the SYSTEM g++ (GCC 15
# on resolute) — that one's libstdc++ ABI matches apt's C++ libs (GLIBCXX_3.4.34),
# so an OLDER g++ must never be used (its libstdc++ cannot resolve apt's symbols).
# A NEWER one is fine and is sometimes required: Hyprland v0.57.0+ calls
# std::string::subview, which GCC 15's libstdc++ does not have. So when the system
# g++ cannot compile AND run that call, the script steps up to the newest g++-N on
# PATH that can (g++-16 here) and says so; if none can, it warns and names the
# apt package instead of dying 46% into the build. Pass --cxx only to force a
# particular compiler (e.g. clang++); it is then used as given, with no step-up.
# For GCC 15's -Wtemplate-body false positive on Hyprland 0.56.2 the script passes
# -Wno-template-body automatically. See docs/hyprland-status.md, incidents 3 and 4.
#
# --with-deps builds/installs the latest release of each named dep into
# /opt/hyprland BEFORE building Hyprland, for when apt's copy is too old or absent.
# Default list: hyprutils, hyprgraphics, aquamarine, hyprland-protocols
# (hyprwm/<dep>, CMake, RPATH-isolated — hyprland-protocols is data-only but still
# a CMake project, so it needs no special case; apt has 0.7.0 and 0.57.0 needs
# >=0.8.0) and wayland-protocols (freedesktop — apt has 1.47, Hyprland needs
# >=1.49; installed data-only: XML tree + a .pc, no meson/wayland-scanner build).
# Also apt-install these first if missing: glslang-dev libinput-dev libeis-dev
# libcanberra-dev (new in 0.57.0). A failed configure now names the exact
# apt package or --with-deps list to use, so you do not have to guess.
#
# Idempotent AND atomic: safe to re-run. The existing /opt/hyprland is moved aside
# before a rebuild and restored automatically if the build fails, so a broken build
# can never leave you with no compositor. On success the old prefix is kept one
# generation at /opt/hyprland.previous.
set -euo pipefail

#-------------------------- configuration --------------------------
DEST="/opt/hyprland"                 # isolated upstream prefix
REPO="https://github.com/hyprwm/Hyprland.git"
LINK="/usr/local/bin/Hyprland"       # generic (master) link
APT_HYPR="/usr/bin/Hyprland"
APT_HYPRCTL="/usr/bin/hyprctl"
APT_HYPRPM="/usr/bin/hyprpm"
APT_PRIO=53                          # matches apt Hyprland 0.53.x
UP_PRIO=56                           # matches upstream 0.56.x → wins in auto mode (newer)

REF=""                               # git ref to build (default: latest release tag)
JOBS="$(nproc 2>/dev/null || echo 2)"
SKIP_BUILD=false
DO_REMOVE=false
CXX=""                                # C++ compiler ("" = auto; see compiler selection below)
CC=""                                 # C compiler (derived from CXX)
RANGES_SHIM=""                        # path to a force-included compat shim, if needed
WITH_DEPS=""                          # deps to build from source into $DEST (space/comma list)
# Not packaged (or too old) in apt for recent Hyprland on Ubuntu. Order matters:
# hyprutils first (everything needs it); wayland-protocols before aquamarine (which
# may use it); aquamarine must be newer than apt's — Hyprland 0.56.2 uses
# SBackendOptions::logConnection, added after apt's 0.9.3 (compile error otherwise).
DEPS_DEFAULT="hyprutils wayland-protocols aquamarine hyprgraphics hyprland-protocols"
# VERSION SKEW: each name here resolves to that dep's LATEST release tag, while
# Hyprland itself can be pinned with --ref. Building an older pinned Hyprland
# against today's deps can fail to compile, or link against sonames that later
# move — pin the deps too in that case, with "name@tag" entries:
#   --with-deps=hyprutils@v0.14.0,wayland-protocols,aquamarine@v0.14.0
# Unpinned names keep tracking latest, which is what you want for latest Hyprland.

# pkg-config + cmake search paths for anything we build into the isolated prefix,
# so the Hyprland configure (and later deps) find OUR fresh builds before apt's.
DEST_PKGCFG="$DEST/lib/pkgconfig:$DEST/lib/x86_64-linux-gnu/pkgconfig:$DEST/share/pkgconfig"
CONFIG_LOG_KEEP="/tmp/hyprland-configure-failed.log"  # survives the build dir cleanup
BUILD_LOG_KEEP="/tmp/hyprland-failed-build.log"          # ditto, for the compile
# NB: deliberately not hyprland-build-*.log — the build trees are
# /tmp/hyprland-build-XXXXXX, so that name would put the one diagnostic a
# failed run leaves behind inside the glob anyone would use to sweep them.

#-------------------------- arg parsing --------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --ref)          REF="${2:-}"; shift 2 ;;
        --jobs)         JOBS="${2:-}"; shift 2 ;;
        --skip-build)   SKIP_BUILD=true; shift ;;
        --remove)       DO_REMOVE=true; shift ;;
        --with-deps)    WITH_DEPS="$DEPS_DEFAULT"; shift ;;
        --with-deps=*)  WITH_DEPS="${1#*=}"; shift ;;
        --cxx)          CXX="${2:-}"; shift 2 ;;
        --cxx=*)        CXX="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done
WITH_DEPS="${WITH_DEPS//,/ }"        # accept comma- or space-separated lists

if [ "$(id -u)" -ne 0 ] && [ -z "${SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY:-}" ]; then
    echo "Run with sudo: sudo bash $0 [--ref <tag>] [--skip-build] [--remove]" >&2
    exit 1
fi

#-------------------------- compiler selection --------------------------
# Build with the SYSTEM default compiler (GCC 15 on Ubuntu resolute). This matters
# for ABI: apt's C++ libraries (re2, hyprutils, ...) are built with GCC 15 and
# require its libstdc++ (GLIBCXX_3.4.34). Building with an older g++ (e.g. g++-14)
# links an older libstdc++ that can't resolve those symbols, so every apt C++ lib
# fails to link ("undefined reference to ...@GLIBCXX_3.4.34"). Use --cxx only to
# pick another libstdc++-based compiler (e.g. clang++), never an older g++.
#
# The system compiler is the STARTING point, not the fixed choice. Hyprland v0.57.1
# failed to build here on 2026-11-05 because GCC 15's libstdc++ has no
# std::string::subview while g++-16 was installed and unused: the default was blind,
# so the one fact that decides the compiler — what its libstdc++ actually provides —
# was never asked. cxx_can_build_source now asks, and the default steps up (never
# down, per the ABI rule above) to the newest g++-N on PATH that passes.
#
# GCC 15's new -Wtemplate-body eagerly (and, for Hyprland 0.56.2, wrongly) rejects
# std::ranges::starts_with in a template body even though <algorithm> is included
# and the standard is C++26 — the name resolves fine at instantiation. So we pass
# -Wno-template-body when building Hyprland with GCC, deferring the check.
# derive_cc_for <c++-compiler> — the C compiler that belongs with it.
#
# Versioned suffixes are handled by pattern, not by a list: this used to name
# g++-13 and g++-14 explicitly, so g++-16 — the compiler Hyprland v0.57.0 needs,
# because its `std::string::subview` call wants a C++26 libstdc++ that GCC 15
# does not have — fell through to "cc" and quietly mixed toolchains. Only the
# name is derived; whether it exists is the caller's business.
derive_cc_for() {
    case "$1" in
        *clang++)  echo "clang" ;;
        *g++-*)    echo "gcc-${1##*g++-}" ;;
        *g++)      echo "gcc" ;;
        *)         echo "cc" ;;
    esac
}

# cxx_can_build_source <c++-compiler> — can this toolchain both COMPILE and RUN
# the C++26 library calls Hyprland's source makes? Two different things fail here
# and they need opposite fixes, so the probe covers both:
#   * compile: GCC 15's libstdc++ has no std::string::subview, which Hyprland
#     v0.57.0+ calls. The build used to discover this ~46% in, at
#     src/ipc/s1/S1.cpp, after cloning, submodules and every dependency.
#   * run: a binary built against a NEWER libstdc++ than the one the loader will
#     hand it dies at startup on GLIBCXX_3.4.NN. So the probe is executed, not
#     just compiled — compiling with g++-16 proves nothing if this machine's
#     libstdc++6 runtime is still GCC 15's.
# std::ranges::starts_with is deliberately NOT probed here: the compat shim below
# supplies it, so a compiler missing only that is still a usable compiler.
cxx_can_build_source() {
    local probe_src probe_bin rc=0
    probe_src="$(mktemp /tmp/hypr-cxx-probe-XXXXXX.cpp)"
    probe_bin="${probe_src%.cpp}.bin"
    cat > "$probe_src" <<'CPP'
#include <string>
int main() { std::string s = "hyprland"; return s.subview(0, 4) == "hypr" ? 0 : 1; }
CPP
    "$1" -std=c++26 -o "$probe_bin" "$probe_src" >/dev/null 2>&1 \
        && "$probe_bin" >/dev/null 2>&1 || rc=1
    rm -f "$probe_src" "$probe_bin"
    return "$rc"
}

# cxx_major <c++-compiler> — its major version, or "" if it will not say.
cxx_major() {
    local v=""
    v="$("$1" -dumpfullversion -dumpversion 2>/dev/null | head -1)" || v=""
    echo "${v%%.*}"
}

# newer_gxx_majors <floor-major> — the major version of every g++-N on PATH with
# N greater than <floor-major>, newest first. The floor is the ABI rule from the
# comment above, enforced instead of only documented: apt's C++ libraries want
# the system libstdc++, so an OLDER g++ is never a candidate — only a newer one.
# An empty or non-numeric floor yields no candidates, so an unreadable compiler
# version can never silently open the door to g++-13.
# No `sort -rn | uniq`: this runs while PATH is being reasoned about, and a
# caller that narrows PATH to the compilers it wants considered would lose
# coreutils with it. Pure bash keeps the answer independent of PATH's contents.
newer_gxx_majors() {
    local floor="$1" dir f major m seen
    case "$floor" in ''|*[!0-9]*) return 0 ;; esac
    local -a dirs=() majors=()
    IFS=: read -r -a dirs <<< "$PATH"
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/g++-*; do
            [ -x "$f" ] || continue
            major="${f##*/g++-}"
            case "$major" in ''|*[!0-9]*) continue ;; esac
            [ "$major" -gt "$floor" ] || continue
            seen=false
            for m in ${majors[@]+"${majors[@]}"}; do
                if [ "$m" = "$major" ]; then seen=true; break; fi
            done
            [ "$seen" = true ] || majors+=("$major")
        done
    done
    # Descending, so the newest usable compiler is tried first.
    local i j tmp n=${#majors[@]}
    for ((i = 0; i < n; i++)); do
        for ((j = i + 1; j < n; j++)); do
            if [ "${majors[j]}" -gt "${majors[i]}" ]; then
                tmp="${majors[i]}"; majors[i]="${majors[j]}"; majors[j]="$tmp"
            fi
        done
    done
    for m in ${majors[@]+"${majors[@]}"}; do echo "$m"; done
}

HYPRLAND_EXTRA_CXXFLAGS=""
if [ "$SKIP_BUILD" = false ] && [ -z "${SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY:-}" ]; then
    CXX_EXPLICIT=true
    if [ -z "$CXX" ]; then CXX="g++"; CXX_EXPLICIT=false; fi
    command -v "$CXX" >/dev/null 2>&1 || { echo "error: C++ compiler '$CXX' not found" >&2; exit 1; }

    # When no --cxx was given and the default toolchain's libstdc++ cannot build
    # what the source calls, step UP to the newest g++-N on PATH that can, rather
    # than failing 46% into the build. An explicit --cxx is honoured as given.
    if [ "$CXX_EXPLICIT" = false ] && ! cxx_can_build_source "$CXX"; then
        picked=""
        for major in $(newer_gxx_majors "$(cxx_major "$CXX")"); do
            if cxx_can_build_source "g++-$major"; then picked="g++-$major"; break; fi
        done
        if [ -n "$picked" ]; then
            echo "==> $CXX's libstdc++ has no std::string::subview — stepping up to $picked"
            CXX="$picked"
        else
            # Not fatal: refs before v0.57.0 do not call subview, and this same
            # compiler built them. Say exactly what will break and where.
            echo "warning: $CXX's libstdc++ has no std::string::subview, and no newer g++-N" >&2
            echo "         on PATH can build and run it either. Hyprland v0.57.0 and later" >&2
            echo "         call it, so ${REF:-the latest release} will fail at src/ipc/s1/S1.cpp." >&2
            echo "         Fix: sudo apt-get install -y g++-16  (or pass --cxx <compiler>)." >&2
        fi
    fi

    # Derive the matching C compiler.
    CC="$(derive_cc_for "$CXX")"
    command -v "$CC" >/dev/null 2>&1 || CC="cc"
    # Suppress the GCC-15 -Wtemplate-body diagnostic for Hyprland (GCC only; GCC
    # silently ignores the unknown -Wno-* on versions that lack the warning).
    case "$CXX" in
        *g++*) HYPRLAND_EXTRA_CXXFLAGS="-Wno-template-body" ;;
    esac

    # Ubuntu resolute's libstdc++ (GCC 15.2) does NOT implement
    # std::ranges::starts_with (P1659) — verified: __cpp_lib_ranges_starts_ends_with
    # is undefined and it's absent from <algorithm>. Hyprland 0.56.2 uses it on a
    # lazy transform_view (so the .starts_with() member won't do). When the toolchain
    # lacks the algorithm, provide it via a force-included compat shim rather than
    # patching Hyprland's source. The shim is itself guarded on the feature macro, so
    # it's a no-op once the stdlib gains the algorithm.
    if ! printf '#include <algorithm>\n#include <string_view>\nbool p(){std::string_view s;return std::ranges::starts_with(s,s);}\n' \
         | "$CXX" -std=c++26 -x c++ -fsyntax-only - >/dev/null 2>&1; then
        RANGES_SHIM="$(mktemp /tmp/hypr-ranges-compat-XXXXXX.hpp)"
        cat > "$RANGES_SHIM" <<'HPP'
#pragma once
#include <version>
// Guard on C++20+ too: this header is force-included into EVERY compile, including
// CMake's compiler-identification test which builds with the default standard
// (gnu++17). In pre-C++20 the ranges concepts don't exist, so keep the shim empty
// there (otherwise the trivial test fails and CMake declares the compiler broken).
#if !defined(__cpp_lib_ranges_starts_ends_with) && __cplusplus >= 202002L
#include <ranges>
namespace std::ranges {
inline constexpr struct __compat_starts_with_fn {
    template <input_range R1, input_range R2>
    constexpr bool operator()(R1&& r1, R2&& r2) const {
        auto it1 = ranges::begin(r1); auto e1 = ranges::end(r1);
        auto it2 = ranges::begin(r2); auto e2 = ranges::end(r2);
        for (; it2 != e2; ++it1, ++it2)
            if (it1 == e1 || !(*it1 == *it2)) return false;
        return true;
    }
} starts_with{};
}
#endif
HPP
        HYPRLAND_EXTRA_CXXFLAGS="${HYPRLAND_EXTRA_CXXFLAGS:+$HYPRLAND_EXTRA_CXXFLAGS }-include $RANGES_SHIM"
        echo "==> stdlib lacks std::ranges::starts_with — injecting a compat shim"
    fi

    echo "==> Building with CXX=$CXX CC=$CC${HYPRLAND_EXTRA_CXXFLAGS:+ (Hyprland CXXFLAGS: $HYPRLAND_EXTRA_CXXFLAGS)}"
fi

#-------------------------- build a hypr* dependency into $DEST --------------------------
# Recent Hyprland needs hypr* libraries (hyprutils, hyprgraphics, ...) newer than
# Ubuntu packages — or not packaged at all. Build the latest release of each into
# the isolated $DEST prefix (with RPATH), so Hyprland links OUR copies and they
# never collide with /usr/lib. Deps are built in the given order; earlier ones are
# visible (via PKG_CONFIG_PATH) to later ones.
build_hypr_dep() {
    local name="$1"
    local pinned="${2:-}"
    local repo="https://github.com/hyprwm/$name.git"

    local ref
    if [ -n "$pinned" ]; then
        # Explicit pin (name@ref). Verify the tag exists so the failure is a clear
        # "no such tag" rather than an opaque clone error 200 lines later.
        if ! git ls-remote --exit-code --tags --refs "$repo" "refs/tags/$pinned" >/dev/null 2>&1; then
            echo "error: '$name' has no tag '$pinned' (see $repo tags)" >&2; return 1
        fi
        ref="$pinned"
    else
        ref="$(git ls-remote --tags --refs "$repo" 2>/dev/null \
                 | awk -F/ '{print $NF}' \
                 | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
                 | sort -V | tail -1)"
        [ -n "$ref" ] || { echo "error: could not resolve a release tag for '$name' (typo? no such hyprwm repo?)" >&2; return 1; }
    fi

    echo "==> Building dependency $name $ref into $DEST"
    local d
    d="$(mktemp -d "/tmp/${name}-build-XXXXXX")"

    # Silence stdout from git clone but preserve stderr so users see the root cause of failures
    if ! git clone --recursive --depth 1 --branch "$ref" "$repo" "$d/src" >/dev/null; then
        echo "error: clone of $name $ref failed" >&2; rm -rf "$d"; return 1
    fi
    if ! PKG_CONFIG_PATH="$DEST_PKGCFG:${PKG_CONFIG_PATH:-}" \
         cmake --no-warn-unused-cli \
            -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
            -DCMAKE_BUILD_TYPE:STRING=Release \
            -DCMAKE_INSTALL_PREFIX:PATH="$DEST" \
            -DCMAKE_INSTALL_RPATH="$DEST/lib;$DEST/lib/x86_64-linux-gnu" \
            -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
            -DCMAKE_PREFIX_PATH="$DEST" \
            -B "$d/build" -S "$d/src"; then
        echo "error: cmake configure for '$name' failed — it likely has its own unmet -dev deps (see output above)" >&2
        rm -rf "$d"; return 1
    fi
    if ! cmake --build "$d/build" -j"$JOBS"; then
        echo "error: build of '$name' failed (see output above)" >&2; rm -rf "$d"; return 1
    fi
    if ! cmake --install "$d/build"; then
        echo "error: install of '$name' into $DEST failed" >&2; rm -rf "$d"; return 1
    fi
    rm -rf "$d"
    echo "    installed $name $ref -> $DEST"
}

# Install freedesktop wayland-protocols into $DEST as DATA ONLY (no meson build).
#
# apt ships 1.47; recent Hyprland needs >= 1.49. Building wayland-protocols with
# meson runs `wayland-scanner --strict` to generate per-protocol enum headers
# that ARE install targets in 1.49 — and that step fails DTD validation on newer
# staging XMLs against the (older) system wayland-scanner. So a full `meson
# install` fails, and `meson install --no-rebuild` fails too (the headers it
# wants to install were never built).
#
# But Hyprland never needs those generated C headers: it consumes wayland-protocols
# purely as data — the protocol .xml files, located at build time via
# `pkg-config --variable=pkgdatadir wayland-protocols`. So we install exactly that:
# the XML tree (stable/staging/unstable, structure preserved) + a hand-written .pc
# carrying the version and pkgdatadir. No meson, no wayland-scanner, no compile.
build_wayland_protocols() {
    local pinned="${1:-}"
    local repo="https://gitlab.freedesktop.org/wayland/wayland-protocols.git"

    local ref
    if [ -n "$pinned" ]; then
        if ! git ls-remote --exit-code --tags --refs "$repo" "refs/tags/$pinned" >/dev/null 2>&1; then
            echo "error: wayland-protocols has no tag '$pinned'" >&2; return 1
        fi
        ref="$pinned"
    else
        ref="$(git ls-remote --tags --refs "$repo" 2>/dev/null \
                 | awk -F/ '{print $NF}' \
                 | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
                 | sort -V | tail -1)"
        [ -n "$ref" ] || { echo "error: could not resolve a wayland-protocols release tag" >&2; return 1; }
    fi

    echo "==> Installing wayland-protocols $ref into $DEST (data-only)"
    local d
    d="$(mktemp -d "/tmp/wayland-protocols-XXXXXX")"

    if ! git clone --depth 1 --branch "$ref" "$repo" "$d/src" >/dev/null; then
        echo "error: clone of wayland-protocols $ref failed" >&2; rm -rf "$d"; return 1
    fi

    # Install the protocol XML tree, preserving the stable/staging/unstable layout
    # that pkgdatadir consumers expect (e.g. staging/color-management/*.xml).
    local pkgdatadir="$DEST/share/wayland-protocols"
    install -d "$pkgdatadir"
    local copied=0 sub
    for sub in stable staging unstable; do
        if [ -d "$d/src/$sub" ]; then
            cp -a "$d/src/$sub" "$pkgdatadir/"
            copied=1
        fi
    done
    [ -f "$d/src/wayland-protocols.dtd" ] && cp -a "$d/src/wayland-protocols.dtd" "$pkgdatadir/"
    if [ "$copied" -ne 1 ]; then
        echo "error: no protocol dirs (stable/staging/unstable) found in wayland-protocols $ref" >&2
        rm -rf "$d"; return 1
    fi

    # Synthesize the pkg-config file Hyprland reads: it needs Version (for the
    # >=1.49 check) and the pkgdatadir variable (to locate the XMLs). Installed to
    # share/pkgconfig (arch-independent), which is on DEST_PKGCFG.
    local ver="${ref#v}"
    install -d "$DEST/share/pkgconfig"
    cat > "$DEST/share/pkgconfig/wayland-protocols.pc" <<PC
prefix=$DEST
datarootdir=\${prefix}/share
pkgdatadir=\${datarootdir}/wayland-protocols

Name: Wayland Protocols
Description: Wayland protocol files
Version: $ver
PC

    rm -rf "$d"
    echo "    installed wayland-protocols $ref (data-only) -> $pkgdatadir"
}

# Dispatch a dependency spec to the right builder (hyprwm/cmake vs the special
# non-hyprwm cases). A spec is "name" (latest release tag) or "name@ref" (pinned).
build_one_dep() {
    local spec="$1" name ref
    name="${spec%%@*}"
    ref=""
    [ "$spec" != "$name" ] && ref="${spec#*@}"
    case "$name" in
        wayland-protocols) build_wayland_protocols "$ref" ;;
        *)                 build_hypr_dep "$name" "$ref" ;;
    esac
}

#-------------------------- explaining a failed configure --------------------------
# A failed CMake configure has two unrelated causes that need opposite fixes: a
# hypr* library too old or absent (build it from source into $DEST, minutes) and
# a plain -dev package that was never installed (one apt-get, seconds). The CMake
# output says which; read it instead of printing both and leaving the reader to
# guess. v0.57.0 added a `libcanberra` module to Hyprland's pkg_check_modules
# call, and the old generic message pointed at a source build of the whole hypr*
# stack for a missing libcanberra-dev.
#
# pkg-config module names are not apt package names, and on a machine that lacks
# the package nothing can map one to the other: `dpkg -S` only knows installed
# files and apt-file is not installed by default. Hence the explicit table, over
# the modules Hyprland and the hypr* deps ask for; anything missing from it falls
# back to an apt-file hint rather than a wrong guess.
SOURCE_BUILDABLE="hyprutils hyprlang hyprcursor hyprgraphics hyprwayland-scanner aquamarine hyprland-protocols wayland-protocols"

apt_dev_package_for() {
    case "$1" in
        libcanberra)         echo "libcanberra-dev" ;;
        xkbcommon)           echo "libxkbcommon-dev" ;;
        uuid)                echo "uuid-dev" ;;
        wayland-server|wayland-client|wayland-cursor|wayland-egl)
                             echo "libwayland-dev" ;;
        cairo)               echo "libcairo2-dev" ;;
        pango|pangocairo)    echo "libpango1.0-dev" ;;
        pixman-1)            echo "libpixman-1-dev" ;;
        xcursor)             echo "libxcursor-dev" ;;
        libdrm)              echo "libdrm-dev" ;;
        libinput)            echo "libinput-dev" ;;
        libeis-1.0)          echo "libeis-dev" ;;
        gbm)                 echo "libgbm-dev" ;;
        gio-2.0|glib-2.0)    echo "libglib2.0-dev" ;;
        re2)                 echo "libre2-dev" ;;
        muparser)            echo "libmuparser-dev" ;;
        lcms2)               echo "liblcms2-dev" ;;
        libseat)             echo "libseat-dev" ;;
        libdisplay-info)     echo "libdisplay-info-dev" ;;
        libjpeg|libwebp|libmagic|librsvg-2.0|libspng)
                             echo "lib${1#lib}-dev" ;;
        *)                   echo "" ;;
    esac
}

# explain_configure_failure <cmake-log> — name the modules that were not
# satisfied and give the one command that fixes each class of them.
explain_configure_failure() {
    local log="$1" name pkg
    # Not $0: this function is also reached with the script sourced (the
    # SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY seam), where $0 is "bash".
    local self="${BASH_SOURCE[0]}"
    local unsatisfied="" from_source="" from_apt="" unmapped=""

    # CMake prints a summary list for a REQUIRED pkg_check_modules failure:
    #
    #   The following required packages were not found:
    #
    #      - aquamarine>=0.15.0
    #
    # That list is the only reliable evidence of a REQUIRED module, so prefer it.
    # A bare "Package 'x' not found" line is NOT such evidence: Hyprland probes
    # optional modules the same way and handles them. Measured on a real v0.57.0
    # log, "--   Package 'udis86' not found" is followed by "falling back to
    # subproject" — an earlier version of this function told the reader to go
    # hunting for a udis86 apt package that the build never needed.
    #
    # Both parses below end in `|| true`: they run under the script's
    # `set -euo pipefail`, where a grep that matches nothing fails the pipeline
    # and errexit would kill this function before it printed anything. That is
    # not hypothetical — it is how a configure failure with no pkg-config module
    # in the log (a compile error, say) came out completely silent.
    unsatisfied="$(sed -n '/The following required packages were not found/,/Call Stack/p' "$log" 2>/dev/null \
                    | grep -oE "^[[:space:]]+- [A-Za-z0-9_.+-]+([<>=]+[0-9.]+)?[[:space:]]*$" \
                    | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[<>=].*$//' \
                    | sed '/^$/d' | sort -u || true)"

    # No summary list: an older CMake, or a failure reported only by pkg-config
    # itself. Fall back to its three wordings — absent, and two "too old" forms.
    if [ -z "$unsatisfied" ]; then
        unsatisfied="$( { grep -oE "Package '[^']+' not found" "$log"
                          grep -oE "Package dependency requirement '[^']+'" "$log"
                          grep -oE "Requested '[^']+'" "$log"
                        } 2>/dev/null \
                        | sed -E "s/^Package '//
                                  s/' not found$//
                                  s/^Package dependency requirement '//
                                  s/^Requested '//
                                  s/'$//" \
                        | awk '{print $1}' \
                        | sed -E 's/[<>=].*$//; /^$/d' \
                        | sort -u || true)"
    fi

    for name in $unsatisfied; do
        case " $SOURCE_BUILDABLE " in
            *" $name "*) from_source="$from_source $name"; continue ;;
        esac
        pkg="$(apt_dev_package_for "$name")"
        if [ -n "$pkg" ]; then
            from_apt="$from_apt $pkg"
        else
            unmapped="$unmapped $name"
        fi
    done
    from_apt="$(echo "$from_apt" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"

    echo "error: CMake configuration failed — the Hyprland dependency chain is not satisfiable." >&2
    if [ -n "$unsatisfied" ]; then
        echo "       Unsatisfied pkg-config modules for $REF: $(echo $unsatisfied)" >&2
    fi

    if [ -n "$from_apt" ]; then
        echo "       Missing -dev packages. Install them and re-run this script:" >&2
        echo "         sudo apt-get install -y ${from_apt% }" >&2
    fi
    if [ -n "$from_source" ]; then
        # Name the WHOLE dependency set, not only what failed this time. Every run
        # rebuilds the prefix from scratch (stage_prefix), so --with-deps=aquamarine
        # on its own would drop hyprutils, wayland-protocols and the rest, and the
        # next configure would fail on one of those instead. Measured: that is what
        # the first cut of this message advised for an unsatisfied
        # hyprland-protocols.
        local deps_arg="" dep
        for dep in $DEPS_DEFAULT $from_source; do
            case ",$deps_arg," in *",$dep,"*) continue ;; esac
            deps_arg="${deps_arg:+$deps_arg,}$dep"
        done
        echo "       hypr* libraries too old or absent in apt. Build them into $DEST:" >&2
        echo "         sudo bash $self --with-deps=$deps_arg" >&2
    fi
    if [ -n "$unmapped" ]; then
        echo "       No known apt package for:${unmapped}. Find what ships <module>.pc with:" >&2
        echo "         sudo apt-get install -y apt-file && sudo apt-file update" >&2
        for name in $unmapped; do
            echo "         apt-file search $name.pc" >&2
        done
    fi
    if [ -z "$unsatisfied" ]; then
        # Not a pkg-config failure — fall back to the generic dependency advice.
        cat >&2 <<EOF
       Nothing in the log names an unsatisfied pkg-config module, so this is not
       a missing-dependency failure. Building upstream $REF needs matching
       versions of the hypr* stack, e.g.:
         hyprutils, hyprlang, hyprcursor, hyprgraphics, hyprwayland-scanner,
         aquamarine, hyprland-protocols  (plus wayland/xkbcommon/pixman/cairo/pango/drm)
       and a C++26-capable toolchain; read the CMake error above.
         sudo bash $self --with-deps                       # builds: $DEPS_DEFAULT
EOF
    fi
    # $build_root (and this log with it) is removed by cleanup_build on exit, so
    # keep a copy the reader can still open after the run.
    if cp -f "$log" "$CONFIG_LOG_KEEP" 2>/dev/null; then
        echo "       Full configure log: $CONFIG_LOG_KEEP" >&2
    fi
    echo "       Upstream build docs: https://wiki.hyprland.org/Getting-Started/Installation/#manual-manual-build" >&2
}

#-------------------------- atomic prefix handling --------------------------
# A rebuild must never leave the system with NO compositor. This script used to
# `rm -rf "$DEST"` before building, so a failed build — or a failed dependency
# build — destroyed a working install. On 2026-10-28 that is exactly what
# happened here: the running Hyprland was deleted from disk, the replacement
# never finished building, and the machine had nothing to log back into (see
# docs/hyprland-status.md).
#
# Instead: move the existing prefix aside (a rename on the same filesystem, so
# it is instant and a running compositor keeps its open inodes), build into a
# fresh $DEST, and on ANY failure put the old prefix back. On success keep one
# generation at $DEST.previous so a bad upgrade can be rolled back by hand.
#
# The rollback covers every exit path the shell can see, which is not every way a
# run can end: SIGKILL and SIGHUP leave no chance to undo the move. So a crashed
# run leaves a half-built $DEST next to an orphaned $DEST.rollback.<pid> holding
# the real install, and the NEXT run used to stage that wreckage aside as though
# it were the install worth protecting — orphaning the real one for good. That is
# what happened here on 2026-11-05 (incident 4 in docs/hyprland-status.md): a
# run died at ~10:46 with 0.57.0 parked in /opt/hyprland.rollback.1375914, and
# the next run restored the bin-less leftover and announced the compositor was
# "back in place". It was not: $DEST had no bin/Hyprland at all.
#
# Hence two rules below: a prefix counts as an install only if it can actually
# run (prefix_is_usable), and an orphan that can run outranks a $DEST that
# cannot (stage_prefix adopts it).
PREFIX_BACKUP=""           # set once the old prefix has been moved aside
PREFIX_COMMITTED=false     # set once the new build has been validated

# prefix_is_usable <dir> — does this directory hold a compositor you could run?
# bin/Hyprland is the one file whose absence means "this is the wreckage of a
# failed run", not "this is an install": the build installs it last, after every
# dependency, so a prefix with libs and no binary is a build that died partway.
prefix_is_usable() {
    [ -x "$1/bin/Hyprland" ]
}

# newest_usable_orphan — the most recent $DEST.rollback.* that holds a runnable
# build, ignoring this run's own backup. These exist only because a previous run
# was killed before it could undo its own staging.
newest_usable_orphan() {
    local d newest="" newest_t=0 t
    for d in "$DEST".rollback.*; do
        [ -d "$d" ] || continue
        [ "$d" = "$DEST.rollback.$$" ] && continue
        prefix_is_usable "$d" || continue
        t="$(stat -c %Y "$d" 2>/dev/null || echo 0)"
        [ "$t" -gt "$newest_t" ] || continue
        newest_t="$t"
        newest="$d"
    done
    if [ -n "$newest" ]; then echo "$newest"; fi
    return 0
}

# adopt_orphan_if_needed — if $DEST cannot run but a $DEST.rollback.* can, put the
# orphan back. Both entry paths have the same question to answer before they touch
# anything: is $DEST actually the install, or the remains of a run that was killed?
adopt_orphan_if_needed() {
    if [ ! -e "$DEST" ] || prefix_is_usable "$DEST"; then return 0; fi
    local orphan
    orphan="$(newest_usable_orphan)"
    if [ -z "$orphan" ]; then return 0; fi
    echo "    $DEST holds no runnable bin/Hyprland — wreckage of an earlier run"
    echo "    adopting the install a killed run left at $orphan"
    rm -rf "$DEST"
    mv "$orphan" "$DEST"
}

stage_prefix() {
    adopt_orphan_if_needed
    if [ -e "$DEST" ]; then
        PREFIX_BACKUP="$DEST.rollback.$$"
        rm -rf "$PREFIX_BACKUP"
        mv "$DEST" "$PREFIX_BACKUP"
        echo "    existing prefix moved aside -> $PREFIX_BACKUP (restored automatically if this run fails)"
    fi
    mkdir -p "$DEST"
}

# Runs from the EXIT trap: undo the move unless this run committed a good build.
rollback_prefix() {
    [ "$PREFIX_COMMITTED" = true ] && return 0
    [ -n "$PREFIX_BACKUP" ] && [ -d "$PREFIX_BACKUP" ] || return 0
    echo "==> This run did not produce a working build — restoring the previous $DEST" >&2
    rm -rf "$DEST"
    mv "$PREFIX_BACKUP" "$DEST"
    PREFIX_BACKUP=""
    # Report what is there, not what was put back. "Back in place" was printed on
    # 2026-11-05 over a prefix with no binary in it, which is how a lost install
    # went unnoticed: the one line that should have raised the alarm said all was
    # well. A restore of wreckage is still wreckage.
    if prefix_is_usable "$DEST"; then
        echo "    restored. The compositor you had before this run is back in place." >&2
        return 0
    fi
    echo "    restored $DEST, but it has NO runnable bin/Hyprland — what was there" >&2
    echo "    before this run was already incomplete, so nothing here can run." >&2
    local orphan
    orphan="$(newest_usable_orphan)"
    if [ -n "$orphan" ]; then
        echo "    A runnable build is parked at $orphan (an earlier run was killed" >&2
        echo "    before it could put it back). Re-running this script adopts it." >&2
    fi
}

# Everything the build must undo, on every exit path. rollback_prefix is
# idempotent — it clears PREFIX_BACKUP once it has restored — so running this
# more than once is harmless.
cleanup_build() {
    rollback_prefix
    [ -n "${build_root:-}" ] && rm -rf "$build_root"
    [ -n "${RANGES_SHIM:-}" ] && rm -f "$RANGES_SHIM"
    true
}

# Arm the rollback for every way this script can stop, signals included.
#
# Measured on bash 5.x rather than assumed, with only an EXIT trap armed:
#   * untrapped SIGTERM -> shell exits 143 and the EXIT trap DOES run, so the
#     TERM line below is redundant. It is kept for symmetry and because
#     web/run_app.sh arms EXIT INT TERM, making the intent explicit at the
#     cost of nothing.
#   * untrapped SIGINT delivered to the shell alone -> the shell does NOT exit
#     and the EXIT trap does NOT run. The INT line is what makes that path
#     clean up, by turning the signal into a plain `exit` so the EXIT trap runs.
#
# A real Ctrl-C signals the whole foreground process group, not the shell alone,
# which is a third case this has NOT measured — it may well already unwind
# correctly. So treat this as making the coverage explicit, not as a fix for a
# demonstrated outage.
arm_build_rollback() {
    trap cleanup_build EXIT
    trap 'exit 130' INT     # 128 + SIGINT
    trap 'exit 143' TERM    # 128 + SIGTERM
    trap 'exit 129' HUP     # 128 + SIGHUP — a closed terminal during a 20-minute
                            # build. Untrapped, bash can die here without running
                            # EXIT, which leaves exactly the orphaned-backup state
                            # found on 2026-11-05. SIGKILL still cannot be trapped,
                            # which is why stage_prefix also adopts an orphan.
}

# Runs once the new build is validated: retire the backup to $DEST.previous.
commit_prefix() {
    PREFIX_COMMITTED=true
    [ -n "$PREFIX_BACKUP" ] && [ -d "$PREFIX_BACKUP" ] || return 0
    rm -rf "$DEST.previous"
    mv "$PREFIX_BACKUP" "$DEST.previous"
    PREFIX_BACKUP=""
    echo "    previous prefix kept at $DEST.previous (delete it once you are happy)"
}

#-------------------------- generic links: are they actually ours? --------------------------
# update-alternatives refuses to replace a path that is a real file it does not
# own, and says so in ONE line among hundreds of lines of output:
#
#     update-alternatives: warning: not replacing /usr/local/bin/hyprpm with a link
#
# Afterwards the group looks correct — `--display` lists the slave, and
# /etc/alternatives/hyprpm points at the new build — while PATH still finds the
# old binary. Measured on this machine on 2026-10-31: Hyprland and hyprctl were
# proper links to the freshly built 0.57.0 while /usr/local/bin/hyprpm was still
# a 2025-12-14 file left by an earlier /usr/local source install, so the
# compositor was ten months newer than its own plugin manager. Nothing in the
# script's output said so after the fact.
#
# So check the links instead of trusting the registration, and print the one
# command that fixes each one.
report_unmanaged_links() {
    local p target rc=0
    local self="${BASH_SOURCE[0]}"
    for p in "$@"; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        if [ -L "$p" ]; then
            target="$(readlink "$p")"
            case "$target" in
                /etc/alternatives/*) continue ;;
            esac
            echo "warning: $p is a symlink to $target, not to /etc/alternatives/" >&2
        else
            echo "warning: $p is a regular file, so update-alternatives could not take it over" >&2
        fi
        rc=1
        echo "         PATH will find it instead of the active alternative. To fix:" >&2
        echo "           sudo mv $p $p.stale && sudo bash $self --skip-build" >&2
    done
    return "$rc"
}

# Test seam, mirroring web/run_app.sh. `SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1
# source setup-hyprland-alternatives.sh` stops here with only the helpers above
# defined, so the prefix staging/rollback can be exercised directly
# (tests/integration/hyprland_setup_prefix.bats) instead of inferred from a real root
# build. Nothing below this line — no removal, no build, no update-alternatives
# — runs under the flag, and the script never sets it itself.
if [ -n "${SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY:-}" ]; then
    # `return` works when sourced (how the tests use this) and fails when the
    # file was executed, where `exit` is the right way out.
    # shellcheck disable=SC2317  # reached when `return` fails, i.e. not sourced
    return 0 2>/dev/null || exit 0
fi

#-------------------------- --remove --------------------------
if [ "$DO_REMOVE" = true ]; then
    echo "==> Removing the 'Hyprland' alternatives group (installs are left in place)"
    update-alternatives --remove-all Hyprland 2>/dev/null || true
    echo "    Done. Note: /opt/hyprland is left untouched; delete it manually if you no longer want the upstream build."
    exit 0
fi

#-------------------------- build upstream into /opt/hyprland --------------------------
if [ "$SKIP_BUILD" = false ]; then
    for t in git cmake g++ pkg-config make; do
        command -v "$t" >/dev/null 2>&1 || { echo "error: missing build tool: $t" >&2; exit 1; }
    done

    # Resolve the ref to build: explicit --ref, else the latest release tag.
    if [ -z "$REF" ]; then
        REF="$(git ls-remote --tags --refs "$REPO" 2>/dev/null \
                 | awk -F/ '{print $NF}' \
                 | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
                 | sort -V | tail -1)"
        [ -n "$REF" ] || { echo "error: could not resolve latest Hyprland tag; pass --ref <tag>" >&2; exit 1; }
    fi

    # Arm the rollback BEFORE anything destructive happens, so a failure in a
    # dependency build (not just in Hyprland itself) also restores the old prefix.
    arm_build_rollback

    # Fresh isolated prefix, then build any requested hypr* deps into it FIRST so
    # the Hyprland configure below finds them (via PKG_CONFIG_PATH) instead of apt's.
    echo "==> Preparing isolated prefix $DEST"
    stage_prefix
    if [ -n "$WITH_DEPS" ]; then
        echo "==> Building dependencies into $DEST: $WITH_DEPS"
        for dep in $WITH_DEPS; do
            build_one_dep "$dep" || {
                echo "error: dependency '$dep' could not be built; install its -dev deps and re-run" >&2
                exit 1
            }
        done
    fi

    echo "==> Building upstream Hyprland $REF into $DEST (isolated prefix)"

    # NB: no `trap ... EXIT` here — the rollback trap armed above already cleans
    # up $build_root and the shim. Re-arming it would silently drop the rollback.
    build_root="$(mktemp -d /tmp/hyprland-build-XXXXXX)"

    echo "    cloning $REF ..."
    if ! git clone --recursive --depth 1 --branch "$REF" "$REPO" "$build_root/src" 2>&1 | tail -3; then
        echo "error: git clone of $REF failed" >&2
        exit 1
    fi

    echo "    configuring (CMake, prefix=$DEST, RPATH=$DEST/lib) ..."
    # errexit off around the build so we can give an actionable dependency message.
    # The output is teed because explain_configure_failure reads it back to say
    # WHICH module was unsatisfied. 2>&1 folds cmake's stderr into that stream,
    # so the whole configure output still reaches the terminal and the log.
    set +e
    cfg_log="$build_root/cmake-configure.log"
    PKG_CONFIG_PATH="$DEST_PKGCFG:${PKG_CONFIG_PATH:-}" \
    cmake --no-warn-unused-cli \
        -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_CXX_FLAGS="$HYPRLAND_EXTRA_CXXFLAGS" \
        -DCMAKE_BUILD_TYPE:STRING=Release \
        -DCMAKE_INSTALL_PREFIX:PATH="$DEST" \
        -DCMAKE_INSTALL_RPATH="$DEST/lib;$DEST/lib/x86_64-linux-gnu" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_PREFIX_PATH="$DEST" \
        -B "$build_root/build" -S "$build_root/src" 2>&1 | tee "$cfg_log"
    cfg_rc=${PIPESTATUS[0]}
    if [ "$cfg_rc" -ne 0 ]; then
        set -e
        explain_configure_failure "$cfg_log"
        exit 1
    fi

    echo "    compiling (-j$JOBS) ..."
    # Build ALL default targets, not just the Hyprland compositor: `cmake --install`
    # installs hyprctl and hyprpm too (and the alternatives group registers them as
    # slaves), so they must be built or the install step fails ("cannot find hyprctl").
    # Teed and kept for the same reason as the configure log: "see output above"
    # is no help once the terminal that ran this is gone, and a compile failure
    # otherwise left nothing behind at all — cleanup_build removes $build_root on
    # the way out, so the only record was the scrollback.
    build_log="$build_root/cmake-build.log"
    cmake --build "$build_root/build" --config Release -j"$JOBS" 2>&1 | tee "$build_log"
    build_rc=${PIPESTATUS[0]}
    if [ "$build_rc" -ne 0 ]; then
        set -e
        echo "error: compilation of $REF failed" >&2
        grep -m3 -E '(^|[/ ])error:' "$build_log" 2>/dev/null | sed 's/^/       /' >&2 || true
        if cp -f "$build_log" "$BUILD_LOG_KEEP" 2>/dev/null; then
            echo "       Full build log: $BUILD_LOG_KEEP" >&2
        fi
        exit 1
    fi

    echo "    installing into $DEST ..."
    # NB: do NOT rm -rf "$DEST" here — it now holds the hypr* deps we built above.
    cmake --install "$build_root/build"
    inst_rc=$?
    set -e
    [ $inst_rc -eq 0 ] || { echo "error: install into $DEST failed" >&2; exit 1; }
fi

#-------------------------- registration-only recovery --------------------------
# --skip-build stages nothing, so it used to walk straight into the validation
# below and die with "not found or not executable" whenever $DEST was the wreckage
# of a killed run — even with the real install sitting in a $DEST.rollback.* right
# beside it, which is the state this machine was left in on 2026-11-05. Adopting
# here makes --skip-build the quick recovery it reads like: the install goes back
# and the alternatives links are re-registered, with no build and no manual `mv`.
if [ "$SKIP_BUILD" = true ]; then
    adopt_orphan_if_needed
fi

#-------------------------- validate the upstream build --------------------------
UP_HYPR="$DEST/bin/Hyprland"
if [ ! -x "$UP_HYPR" ]; then
    echo "error: '$UP_HYPR' not found or not executable" >&2
    echo "       build it first (drop --skip-build) or install upstream into $DEST" >&2
    exit 1
fi
# Confirm it resolves its own libraries (no /usr/lib hypr* fallback that could break on apt upgrade).
# A binary with unresolved libraries cannot start, so for a build WE just made this
# is a failed build, not a warning: fall through to the EXIT trap, which restores
# the previous prefix. With --skip-build the prefix is the user's own, so warn only.
if ldd "$UP_HYPR" 2>/dev/null | grep -q 'not found'; then
    echo "error: '$UP_HYPR' has unresolved libraries:" >&2
    ldd "$UP_HYPR" | grep 'not found' >&2
    if [ "$SKIP_BUILD" = false ]; then
        echo "       this build cannot start. Its dependencies in $DEST do not match the" >&2
        echo "       sonames it was linked against — usually dep/Hyprland version skew." >&2
        echo "       Pin the deps to versions contemporary with $REF, e.g.:" >&2
        echo "         sudo bash $0 --ref $REF --with-deps=hyprutils@v0.14.0,aquamarine@v0.14.0" >&2
        exit 1
    fi
    echo "       the upstream build is not self-contained; fix its RPATH/deps before relying on it." >&2
fi
up_ver="$("$UP_HYPR" --version 2>/dev/null | head -1 || true)"
if [ "$SKIP_BUILD" = false ] && [ -z "$up_ver" ]; then
    echo "error: '$UP_HYPR' was built but cannot report its version — treating as a failed build" >&2
    exit 1
fi
echo "    upstream: $UP_HYPR -> ${up_ver:-<version unreadable>}"

# The new prefix holds a binary that starts and resolves every library: keep it.
commit_prefix

# Resolve upstream slave paths (fall back to the master's bin dir).
UP_HYPRCTL="$DEST/bin/hyprctl"; [ -x "$UP_HYPRCTL" ] || UP_HYPRCTL=""
UP_HYPRPM="$DEST/bin/hyprpm";  [ -x "$UP_HYPRPM" ]  || UP_HYPRPM=""

#-------------------------- register the alternatives group --------------------------
echo "==> Registering the 'Hyprland' alternatives group (generic link: $LINK)"

# apt candidate
if [ -x "$APT_HYPR" ]; then
    apt_args=(--install "$LINK" Hyprland "$APT_HYPR" "$APT_PRIO")
    [ -x "$APT_HYPRCTL" ] && apt_args+=(--slave /usr/local/bin/hyprctl hyprctl "$APT_HYPRCTL")
    [ -x "$APT_HYPRPM" ]  && apt_args+=(--slave /usr/local/bin/hyprpm  hyprpm  "$APT_HYPRPM")
    update-alternatives "${apt_args[@]}"
    echo "    apt      $APT_HYPR  (priority $APT_PRIO)"
else
    echo "    (apt Hyprland not present at $APT_HYPR — skipping)"
fi

# upstream candidate
up_args=(--install "$LINK" Hyprland "$UP_HYPR" "$UP_PRIO")
[ -n "$UP_HYPRCTL" ] && up_args+=(--slave /usr/local/bin/hyprctl hyprctl "$UP_HYPRCTL")
[ -n "$UP_HYPRPM" ]  && up_args+=(--slave /usr/local/bin/hyprpm  hyprpm  "$UP_HYPRPM")
update-alternatives "${up_args[@]}"
echo "    upstream $UP_HYPR  (priority $UP_PRIO)"

echo "==> Result"
update-alternatives --display Hyprland

cat <<'DONE_MSG'

Done.
  • /usr/local/bin precedes /usr/bin in PATH, so `Hyprland` now resolves to the
    active alternative (highest priority = upstream, in auto mode).
  • Switch interactively:  sudo update-alternatives --config Hyprland
  • Pin one explicitly:    sudo update-alternatives --set Hyprland /opt/hyprland/bin/Hyprland
  • A running compositor does NOT swap under itself — the switch applies to your
    NEXT login. Ensure your wayland session launches `Hyprland` via PATH (so
    /usr/local/bin wins), or point the session's Exec at /usr/local/bin/Hyprland.
  • If you ever `apt remove hyprland`, also drop its alternative:
        sudo update-alternatives --remove Hyprland /usr/bin/Hyprland
  • Tear the whole group down (keeps both installs):
        sudo bash setup-hyprland-alternatives.sh --remove
DONE_MSG

# Last, so an unmanaged path is the final thing on screen instead of a warning
# buried in the registration output. Not fatal: the build and the group are fine,
# it is PATH that disagrees with them.
report_unmanaged_links "$LINK" /usr/local/bin/hyprctl /usr/local/bin/hyprpm || true
