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
#   sudo bash setup-hyprland-alternatives.sh --skip-build     # register only (upstream already in /opt/hyprland)
#   sudo bash setup-hyprland-alternatives.sh --remove         # tear the group down (leaves both installs)
#
# --with-deps builds/installs the latest release of each named dep into
# /opt/hyprland BEFORE building Hyprland, for when apt's copy is too old or absent.
# Default list: hyprutils, hyprgraphics (hyprwm/<dep>, CMake, RPATH-isolated) and
# wayland-protocols (freedesktop — apt has 1.47, Hyprland needs >=1.49; installed
# data-only: XML tree + a .pc, no meson/wayland-scanner build).
# Also apt-install these first if missing: glslang-dev libinput-dev libeis-dev.
#
# Idempotent: safe to re-run (rebuilds /opt/hyprland and re-registers alternatives).
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
WITH_DEPS=""                          # deps to build from source into $DEST (space/comma list)
# Not packaged (or too old) in apt for recent Hyprland on Ubuntu: the hypr* libs
# plus wayland-protocols (apt ships 1.47; recent Hyprland needs >= 1.49).
DEPS_DEFAULT="hyprutils hyprgraphics wayland-protocols"

# pkg-config + cmake search paths for anything we build into the isolated prefix,
# so the Hyprland configure (and later deps) find OUR fresh builds before apt's.
DEST_PKGCFG="$DEST/lib/pkgconfig:$DEST/lib/x86_64-linux-gnu/pkgconfig:$DEST/share/pkgconfig"

#-------------------------- arg parsing --------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --ref)          REF="${2:-}"; shift 2 ;;
        --jobs)         JOBS="${2:-}"; shift 2 ;;
        --skip-build)   SKIP_BUILD=true; shift ;;
        --remove)       DO_REMOVE=true; shift ;;
        --with-deps)    WITH_DEPS="$DEPS_DEFAULT"; shift ;;
        --with-deps=*)  WITH_DEPS="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done
WITH_DEPS="${WITH_DEPS//,/ }"        # accept comma- or space-separated lists

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo bash $0 [--ref <tag>] [--skip-build] [--remove]" >&2
    exit 1
fi

#-------------------------- build a hypr* dependency into $DEST --------------------------
# Recent Hyprland needs hypr* libraries (hyprutils, hyprgraphics, ...) newer than
# Ubuntu packages — or not packaged at all. Build the latest release of each into
# the isolated $DEST prefix (with RPATH), so Hyprland links OUR copies and they
# never collide with /usr/lib. Deps are built in the given order; earlier ones are
# visible (via PKG_CONFIG_PATH) to later ones.
build_hypr_dep() {
    local name="$1"
    local repo="https://github.com/hyprwm/$name.git"

    local ref
    ref="$(git ls-remote --tags --refs "$repo" 2>/dev/null \
             | awk -F/ '{print $NF}' \
             | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
             | sort -V | tail -1)"
    [ -n "$ref" ] || { echo "error: could not resolve a release tag for '$name' (typo? no such hyprwm repo?)" >&2; return 1; }

    echo "==> Building dependency $name $ref into $DEST"
    local d
    d="$(mktemp -d "/tmp/${name}-build-XXXXXX")"

    # Silence stdout from git clone but preserve stderr so users see the root cause of failures
    if ! git clone --recursive --depth 1 --branch "$ref" "$repo" "$d/src" >/dev/null; then
        echo "error: clone of $name $ref failed" >&2; rm -rf "$d"; return 1
    fi
    if ! PKG_CONFIG_PATH="$DEST_PKGCFG:${PKG_CONFIG_PATH:-}" \
         cmake --no-warn-unused-cli \
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
    local repo="https://gitlab.freedesktop.org/wayland/wayland-protocols.git"

    local ref
    ref="$(git ls-remote --tags --refs "$repo" 2>/dev/null \
             | awk -F/ '{print $NF}' \
             | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' \
             | sort -V | tail -1)"
    [ -n "$ref" ] || { echo "error: could not resolve a wayland-protocols release tag" >&2; return 1; }

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

# Dispatch a dependency name to the right builder (hyprwm/cmake vs the special
# non-hyprwm cases).
build_one_dep() {
    case "$1" in
        wayland-protocols) build_wayland_protocols ;;
        *)                 build_hypr_dep "$1" ;;
    esac
}

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

    # Fresh isolated prefix, then build any requested hypr* deps into it FIRST so
    # the Hyprland configure below finds them (via PKG_CONFIG_PATH) instead of apt's.
    echo "==> Preparing isolated prefix $DEST"
    rm -rf "$DEST"
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

    build_root="$(mktemp -d /tmp/hyprland-build-XXXXXX)"
    trap 'rm -rf "$build_root"' EXIT

    echo "    cloning $REF ..."
    if ! git clone --recursive --depth 1 --branch "$REF" "$REPO" "$build_root/src" 2>&1 | tail -3; then
        echo "error: git clone of $REF failed" >&2
        exit 1
    fi

    echo "    configuring (CMake, prefix=$DEST, RPATH=$DEST/lib) ..."
    # errexit off around the build so we can give an actionable dependency message.
    set +e
    PKG_CONFIG_PATH="$DEST_PKGCFG:${PKG_CONFIG_PATH:-}" \
    cmake --no-warn-unused-cli \
        -DCMAKE_BUILD_TYPE:STRING=Release \
        -DCMAKE_INSTALL_PREFIX:PATH="$DEST" \
        -DCMAKE_INSTALL_RPATH="$DEST/lib;$DEST/lib/x86_64-linux-gnu" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_PREFIX_PATH="$DEST" \
        -B "$build_root/build" -S "$build_root/src"
    cfg_rc=$?
    if [ $cfg_rc -ne 0 ]; then
        set -e
        cat >&2 <<EOF
error: CMake configuration failed — the Hyprland dependency chain is not satisfiable.
       Building upstream $REF needs matching versions of the hypr* stack, e.g.:
         hyprutils, hyprlang, hyprcursor, hyprgraphics, hyprwayland-scanner,
         aquamarine, hyprland-protocols  (plus wayland/xkbcommon/pixman/cairo/pango/drm)
       If a hypr* library is too old or missing in apt (a "requires >= X" or
       "not found" pkg-config error above), build it from source into $DEST:
         sudo bash $0 --with-deps                       # builds: $DEPS_DEFAULT
         sudo bash $0 --with-deps=hyprutils,hyprgraphics # or a custom list
       If instead a plain -dev package is missing, apt-install it and re-run.
       Upstream build docs: https://wiki.hyprland.org/Getting-Started/Installation/#manual-manual-build
EOF
        exit 1
    fi

    echo "    compiling (-j$JOBS) ..."
    cmake --build "$build_root/build" --config Release --target Hyprland -j"$JOBS"
    build_rc=$?
    if [ $build_rc -ne 0 ]; then
        set -e
        echo "error: compilation failed (see output above)" >&2
        exit 1
    fi

    echo "    installing into $DEST ..."
    # NB: do NOT rm -rf "$DEST" here — it now holds the hypr* deps we built above.
    cmake --install "$build_root/build"
    inst_rc=$?
    set -e
    [ $inst_rc -eq 0 ] || { echo "error: install into $DEST failed" >&2; exit 1; }
fi

#-------------------------- validate the upstream build --------------------------
UP_HYPR="$DEST/bin/Hyprland"
if [ ! -x "$UP_HYPR" ]; then
    echo "error: '$UP_HYPR' not found or not executable" >&2
    echo "       build it first (drop --skip-build) or install upstream into $DEST" >&2
    exit 1
fi
# Confirm it resolves its own libraries (no /usr/lib hypr* fallback that could break on apt upgrade).
if ldd "$UP_HYPR" 2>/dev/null | grep -q 'not found'; then
    echo "warning: '$UP_HYPR' has unresolved libraries:" >&2
    ldd "$UP_HYPR" | grep 'not found' >&2
    echo "         the upstream build is not self-contained; fix its RPATH/deps before relying on it." >&2
fi
up_ver="$("$UP_HYPR" --version 2>/dev/null | head -1 || true)"
echo "    upstream: $UP_HYPR -> ${up_ver:-<version unreadable>}"

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
