#!/usr/bin/env bash
#
# setup-kitty-alternatives.sh
#
# Register the apt kitty and the upstream (installer) kitty as a single
# `kitty` update-alternatives group so you can switch between them:
#   - generic link:  /usr/local/bin/kitty   (precedes /usr/bin in PATH)
#   - master/slave:  kitty + kitten switch together (they are version-coupled)
#   - upstream copied to /opt/kitty.app      (clean system-wide location)
#
# Run with sudo:
#   sudo bash setup-kitty-alternatives.sh [path-to-upstream-kitty.app]
#
# Idempotent: safe to re-run (refreshes /opt and re-registers the alternatives).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo bash $0 [path-to-upstream-kitty.app]" >&2
    exit 1
fi

# Upstream (installer) kitty.app. Default: the invoking user's ~/.local/kitty.app;
# override by passing a path as $1.
SRC="${1:-}"
if [ -z "$SRC" ]; then
    invoking_user="${SUDO_USER:-$USER}"
    invoking_home="$(getent passwd "$invoking_user" | cut -d: -f6)"
    SRC="$invoking_home/.local/kitty.app"
fi

DEST="/opt/kitty.app"
APT_KITTY="/usr/bin/kitty"
APT_KITTEN="/usr/bin/kitten"
APT_PRIO=45     # matches apt kitty 0.45.x
UP_PRIO=48      # matches upstream kitty 0.48.x → wins in auto mode (newer)

echo "Upstream source: $SRC"
if [ ! -x "$SRC/bin/kitty" ]; then
    echo "error: '$SRC/bin/kitty' not found or not executable" >&2
    echo "       pass the correct path: sudo bash $0 /path/to/kitty.app" >&2
    exit 1
fi

echo "==> Copying upstream kitty to $DEST"
rm -rf "$DEST"
cp -a "$SRC" "$DEST"
if ! "$DEST/bin/kitty" --version >/dev/null 2>&1; then
    echo "error: '$DEST/bin/kitty' failed to run after copy" >&2
    exit 1
fi
echo "    $DEST/bin/kitty -> $("$DEST/bin/kitty" --version)"

echo "==> Registering the 'kitty' alternatives group (generic link: /usr/local/bin/kitty)"
if [ -x "$APT_KITTY" ]; then
    update-alternatives --install /usr/local/bin/kitty kitty "$APT_KITTY" "$APT_PRIO" \
        --slave /usr/local/bin/kitten kitten "$APT_KITTEN"
    echo "    apt      $APT_KITTY  (priority $APT_PRIO)"
else
    echo "    (apt kitty not present at $APT_KITTY — skipping)"
fi
update-alternatives --install /usr/local/bin/kitty kitty "$DEST/bin/kitty" "$UP_PRIO" \
    --slave /usr/local/bin/kitten kitten "$DEST/bin/kitten"
echo "    upstream $DEST/bin/kitty  (priority $UP_PRIO)"

echo "==> Result"
update-alternatives --display kitty

cat <<'NEXT'

Done.
  • /usr/local/bin precedes /usr/bin in PATH, so `kitty` now resolves to the
    active alternative (highest priority = upstream, in auto mode).
  • Switch interactively:  sudo update-alternatives --config kitty
  • Pin one explicitly:    sudo update-alternatives --set kitty /opt/kitty.app/bin/kitty
  • GUI launchers: point the .desktop `Exec=` at /usr/local/bin/kitty so they
    follow the active alternative.
  • The old ~/.local/bin/{kitty,kitten} symlinks are now shadowed; remove them
    to avoid confusion:  rm -f ~/.local/bin/kitty ~/.local/bin/kitten
  • If you ever `apt remove kitty`, also drop its alternative:
        sudo update-alternatives --remove kitty /usr/bin/kitty
NEXT
