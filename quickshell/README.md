# sysupdate QuickShell Widget

A Wayland desktop widget built with **Quickshell** that shows the count of pending OS package
updates (apt/pacman) and a button to run `system_update.sh` interactively.

**Version:** `v0.1`

## Files

- `shell.qml`: Quickshell entry point — status display and "Run Updates" button.
- `scripts/sysupdate_status.sh`: local, no-network check of pending apt/pacman updates.

## Run

1. Ensure Quickshell is installed.
2. From this directory, run:

   ```bash
   quickshell -p shell.qml
   ```

The compositor is detected automatically at startup:

| Compositor | Window type | Positioning |
|---|---|---|
| Sway, Hyprland (wlroots) | `PanelWindow` via layershell | Anchored to top-right edge |
| GNOME, other | `FloatingWindow` fallback | Floating (position by window manager) |

Detection checks `SWAYSOCK` and `HYPRLAND_INSTANCE_SIGNATURE` environment variables.

## qmlls setup

Use your editor's QML language server (`qmlls`) with this repository opened at:

`<repository-root>/quickshell`

so it can index `shell.qml` and provide completions/diagnostics.

## See also

- [DESIGN.md](./DESIGN.md) — design doc and v0.1 scope.
- `~/Documents/GitHub/sysmon` — sibling widget this one follows for styling and architecture.
