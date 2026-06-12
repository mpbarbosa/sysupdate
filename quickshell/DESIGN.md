# Design Doc: sysupdate QuickShell Widget

**Author:** Marcelo Pereira Barbosa
**Created:** 2026-06-11
**Last Updated:** 2026-06-11
**Status:** v0.1 implemented (pending visual review on a Wayland session)

---

## Overview

The sysupdate QuickShell Widget is a lightweight Wayland desktop widget built with
[Quickshell](https://quickshell.outfoxxed.me/) that displays the count of pending OS package
updates (apt/pacman) and provides a button to launch `system_update.sh` interactively in a
terminal. It is one of two parallel front-end experiments for `sysupdate` (see root
`CONTEXT-MAP.md`); the other is the Web Dashboard (`web/`).

---

## Background

This widget follows the architecture and visual conventions of the `sysmon` sibling project
(`~/Documents/GitHub/sysmon`), a working Quickshell widget by the same author that displays
CPU/memory/disk usage and a cache-cleanup button, and is displayed on the same desktop. Reusing
`sysmon`'s patterns gives:

- Compositor detection (`PanelWindow` on wlroots / `FloatingWindow` on GNOME, via
  `SWAYSOCK`/`HYPRLAND_INSTANCE_SIGNATURE`)
- A `Process` + JSON polling pattern against a bash backend script
- An interactive-terminal-launch pattern for scripts requiring prompts
- Visual cohesion: Catppuccin Mocha palette (`#1e1e2e` background, `#cdd6f4` text, `#89b4fa`
  accents)

`web/DESIGN.md` (the Web Dashboard's design doc) is referenced only for information architecture
and data shapes (e.g. the `Category` taxonomy) — not for visual styling or as portable code. See
root `CONTEXT-MAP.md` "Relationships".

---

## Goals (v0.1)

1. Display the count of pending OS package updates (apt or pacman, whichever
   `detect_package_manager` identifies), refreshed periodically (target: every 60s, like a
   typical bar widget) via `quickshell/scripts/sysupdate_status.sh`.
2. `sysupdate_status.sh` performs **local-only, no-network** checks (`apt list --upgradable` /
   `pacman -Qu`), so polling is cheap and safe at short intervals — no new core-CLI capability
   required.
3. Provide a "Run Updates" button that launches `system_update.sh` interactively in a terminal
   (`gnome-terminal -- bash`, mirroring `sysmon`'s "Clean Cache" button), since `system_update.sh`
   is interactive (prompts) like `cleanup_cache.sh`.
4. Compositor detection and visual styling follow `sysmon` exactly (see Background).

## Non-Goals (v0.1)

- **Per-category breakdown** (node/python/rust/apps from `upgrade_snippets/`). Blocked on a new
  core-CLI "quiet batch check-only" capability (see root `CONTEXT-MAP.md` open questions). v0.1
  shows the `system` category count only.
- **Logs / Schedule / Settings views** — out of scope for this widget; that's the Web Dashboard's
  territory.
- **Live in-widget output streaming** — the "Run Updates" terminal handles output, as with
  `sysmon`'s cleanup terminal.
- **Per-package list or changelogs.**
- **Notifications or cron/scheduling UI** — separate core-CLI capability gaps, not yet designed.
- **Multi-monitor support** — appears on one screen, like `sysmon`.
- **Configurable poll interval or thresholds** — fixed, like `sysmon`.

---

## Design

### Component overview

```
shell.qml  (Quickshell entry point)
│
├── Scope  (root — non-visual container, holds shared state)
│   ├── Process: compositorCheck   — detects compositor at startup (same as sysmon)
│   ├── Process: statusProcess     — runs sysupdate_status.sh, parses JSON
│   ├── Process: runUpdatesProcess — launches gnome-terminal with system_update.sh
│   ├── Timer                      — fires updateStatus() every 60 s
│   ├── Timer                      — delayed status refresh after "Run Updates" launch (15 s,
│   │                                 mirrors sysmon's cleanupEstimateRefreshTimer)
│   ├── component SysupdateContent — title + status line + "Run Updates" button
│   ├── Component: panelWindowComponent   — PanelWindow for wlroots
│   └── Component: floatingWindowComponent — FloatingWindow for GNOME
│
scripts/
└── sysupdate_status.sh — counts pending OS package updates, emits JSON
```

### Compositor detection

Identical to `sysmon`: `compositorCheck` runs
`printf '%s:%s' "${SWAYSOCK:-}" "${HYPRLAND_INSTANCE_SIGNATURE:-}"`; non-empty → `PanelWindow`
(anchored top-right), empty → `FloatingWindow`.

### Status pipeline

`sysupdate_status.sh` sources `scripts/lib/core_lib.sh` to reuse `detect_package_manager` (a
cheap `command -v` check), then counts pending updates with the corresponding local, no-network
command:

- apt: `apt list --upgradable 2>/dev/null | tail -n +2 | wc -l`
- pacman: `pacman -Qu | wc -l`

and emits one line of JSON:

```json
{"system": 4, "package_manager": "apt"}
```

`statusProcess` (a Quickshell `Process` with `StdioCollector`) parses this on a 60 s `Timer`,
following the same overlap-guard pattern as `sysmon`'s `metricsProcess`/`updateUsage()`.

### Status line and "Run Updates" button

- Status line: `"System updates: N pending"` when `system > 0`, or `"System: up to date"` when
  `system == 0`.
- Button: always enabled, labeled "Run Updates". `onClicked` launches
  `gnome-terminal -- bash <path to system_update.sh>` (same daemonizing pattern as `sysmon`'s
  cleanup button — `runUpdatesProcess.running` returns to `false` within milliseconds).
- After launch, the 15 s delayed `Timer` triggers `updateStatus()` again, so the displayed count
  reflects the result of the run.

### Window sizing

Smaller than `sysmon` (260×224) since there's less content: title (16 px) + status line (13 px) +
button (28 px) + outer margins (12 px each side) + column spacing (10 px × 2). Target
`implicitWidth: 260`, `implicitHeight: ~110`.

---

## Alternatives Considered

### Live full check including `upgrade_snippets/` for v0.1

Would give a complete per-`Category` count immediately. Rejected: many snippets do network calls
(GitHub releases/tags, npm registry), making a 60 s poll slow and risking rate limits — the same
"no network in the background poll" concern that shapes `sysmon`.

### Cached snapshot written by `system_update.sh` runs

A middle ground: `sysupdate_status.sh` reads a snapshot file last written by a full
`system_update.sh` run. Rejected for v0.1 because no such snapshot exists today —
`config_driven_version_check` is interactive/printing, not quiet/structured. Writing one is new
core-CLI work (tracked as a gap in root `CONTEXT-MAP.md`), so it's deferred to v0.2+ rather than
gating v0.1 on it.

### WebView-embedding the Web Dashboard instead of a native widget

Considered and rejected — see [ADR 0001](../docs/adr/0001-quickshell-widget-follows-sysmon-styling.md)
and root `CONTEXT-MAP.md` "Relationships": it would collapse the two front-end experiments into
one, defeating the point of evaluating both GUI paradigms.

## Decisions

- **Visual styling and architecture follow `sysmon`, not `web/DESIGN.md`'s Cyber-Terminal HUD.**
  See [docs/adr/0001-quickshell-widget-follows-sysmon-styling.md](../docs/adr/0001-quickshell-widget-follows-sysmon-styling.md).
- **Terminal emulator: hardcode `gnome-terminal`**, matching `sysmon` exactly. `$TERMINAL`-based
  portability is a shared future improvement for both widgets, not specific to this one.

## Open Questions

1. **Per-category breakdown** — deferred to v0.2+, pending the new core-CLI batch check-only
   capability (root `CONTEXT-MAP.md`).
