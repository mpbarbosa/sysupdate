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
#   sudo bash setup-hyprland-alternatives.sh --skip-build   # register only (upstream already in /opt/hyprland)
#   sudo bash setup-hyprland-alternatives.sh --remove       # tear the group down (leaves both installs)
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

#-------------------------- arg parsing --------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --ref)          REF="${2:-}"; shift 2 ;;
        --jobs)         JOBS="${2:-}"; shift 2 ;;
        --skip-build)   SKIP_BUILD=true; shift ;;
        --remove)       DO_REMOVE=true; shift ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo bash $0 [--ref <tag>] [--skip-build] [--remove]" >&2
    exit 1
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
    cmake --no-warn-unused-cli \
        -DCMAKE_BUILD_TYPE:STRING=Release \
        -DCMAKE_INSTALL_PREFIX:PATH="$DEST" \
        -DCMAKE_INSTALL_RPATH="$DEST/lib;$DEST/lib/x86_64-linux-gnu" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -B "$build_root/build" -S "$build_root/src"
    cfg_rc=$?
    if [ $cfg_rc -ne 0 ]; then
        set -e
        cat >&2 <<EOF
error: CMake configuration failed — the Hyprland dependency chain is not satisfiable.
       Building upstream $REF needs matching versions of the hypr* stack, e.g.:
         hyprutils, hyprlang, hyprcursor, hyprgraphics, hyprwayland-scanner,
         aquamarine, hyprland-protocols  (plus wayland/xkbcommon/pixman/cairo/pango/drm)
       Install the newer -dev packages (if your distro has them) or build that
       stack into $DEST first, then re-run with --skip-build.
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
    rm -rf "$DEST"
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
