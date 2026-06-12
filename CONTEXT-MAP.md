# Context Map

This repository spans multiple bounded contexts, each with its own glossary (`CONTEXT.md`) and
architectural decisions (`docs/adr/`).

## "sysupdate" naming

The name **sysupdate** is used at three levels — be precise about which one a document means:

- **sysupdate** (no qualifier) — the umbrella project, and specifically **the core CLI engine**
  (the Bash script suite in `scripts/`). This is the primary, currently-implemented artifact.
- **sysupdate Web Dashboard** — a browser-based "Cyber-Terminal HUD" front-end
  (React/Vite/TypeScript), implemented as a UX prototype against mock data. See
  [web/CONTEXT.md](web/CONTEXT.md).
- **sysupdate QuickShell Widget** — a Qt Quick/QML desktop-shell front-end (e.g. for
  Hyprland/Wayland bars or a GNOME floating window). See [quickshell/DESIGN.md](quickshell/DESIGN.md).

Both front-ends are clients of the core CLI engine — they invoke `sysupdate` rather than
reimplementing its update logic.

## Contexts

| Context | Location | Status |
|---|---|---|
| Core CLI engine | `scripts/` (see `CLAUDE.md`) | Implemented |
| Web Dashboard | `web/` | Experimental — UX prototype implemented with mock data (`web/DESIGN.md`) |
| QuickShell Widget | `quickshell/` | Experimental — design in progress (`quickshell/DESIGN.md`) |

## Experimental front-ends

The Web Dashboard and QuickShell Widget are **parallel experiments**, not a committed product
roadmap with a fixed use-case split. The goal is to evaluate both GUI paradigms against the core
CLI engine before (if ever) committing to one as "the" front-end. Either may be abandoned without
that being a reversal of an architectural decision.

## Relationships

- **Web Dashboard ↔ QuickShell Widget**: [`web/DESIGN.md`](web/DESIGN.md) is a reference for
  **information architecture and data shapes only** for the QuickShell Widget — the views
  (dashboard/logs/schedule/settings), sidebar categories, and data shapes (`UpdateItem`,
  `LogEntry`, `ScheduleTask`, `SystemConfig`). It is **not** a visual-styling reference for the
  QuickShell Widget (see "sysmon sibling project" below) and is **not** portable implementation
  code: the QuickShell Widget will be a native QML implementation, not a WebView embedding of the
  React app, so the two experiments remain genuinely distinct GUI paradigms.
- **Both front-ends → Core CLI engine**: clients only, via invoking `sysupdate` (see "sysupdate
  naming" above).
- **QuickShell Widget ↔ `sysmon` sibling project** (`~/Documents/GitHub/sysmon`): `sysmon` is a
  working Quickshell desktop widget by the same author, displayed on the same desktop. The
  sysupdate QuickShell Widget follows `sysmon`'s established conventions for **visual styling**
  (Catppuccin Mocha palette: `#1e1e2e` background, `#cdd6f4` text, `#89b4fa` accents) and
  **architecture** (compositor detection via `SWAYSOCK`/`HYPRLAND_INSTANCE_SIGNATURE` choosing
  `PanelWindow` vs `FloatingWindow`; a `Process` + JSON polling pattern against a bash backend
  script; launching an interactive terminal for scripts that need prompts), for visual cohesion
  between the two widgets and to reuse a proven pattern. `web/DESIGN.md`'s neon "Cyber-Terminal
  HUD" palette/aesthetic does **not** apply to the QuickShell Widget.

## Open questions / known gaps

- **Real output integration is unresolved.** `web/DESIGN.md` §4 explicitly designs the "Live
  Output Console" (`TerminalLine`) as a simulator "without relying on complex, external OS-level
  backends" — it only renders mock/staged lines. How either front-end (Web Dashboard or
  QuickShell Widget) would consume *real* `sysupdate` output (e.g. mapping `core_lib.sh`'s
  `print_status`/`print_success`/`print_warning`/`print_error` to `TerminalLine.type`, or
  invoking the CLI and streaming its stdout/stderr at all) is not designed yet. Both front-ends
  currently assume mock data; this should be resolved before either experiment moves past
  cosmetic/UX prototyping.
- **Notifications are a new CLI capability, not yet designed.** `SystemConfig.notifyOnSuccess`
  / `notifyOnFailure` imply desktop notifications (e.g. via `notify-send`) when a scheduled
  `ScheduleTask` completes. The core CLI has no notification mechanism today; this would need to
  be added (e.g. the cron-invoked command wraps `sysupdate`/`--snippet <id>` and calls
  `notify-send` based on exit status), independent of either front-end.
- **`LogEntry` persistence is a new CLI capability, not yet designed.** The CLI currently writes
  nothing persistent — each run only prints to stdout. For `LogsView`'s `LogEntry` records
  (`timestamp`, `category`, `target`, `action`, `status`, `details`, `duration`) to be real,
  `sysupdate` would need to append structured records (e.g. JSON-lines) after each run/snippet,
  which either front-end reads directly. "Journal" in `LogsView` is treated as a UI metaphor, not
  a literal `journalctl`/systemd dependency (the CLI has no systemd integration).
- **A quiet, batch "check-only" mode for `upgrade_snippets/` is a new CLI capability, not yet
  designed.** `config_driven_version_check` (`upgrade_utils.sh`) is interactive/printing — there's
  no way to ask "how many updates are pending for node/python/rust/apps?" without running the
  full interactive flow. This blocks per-category counts in the QuickShell Widget (see
  `quickshell/DESIGN.md` Non-Goals — v0.1 shows `system`/apt-pacman counts only, which need no new
  capability) and is the same underlying need as `LogEntry` persistence above: both want a quiet,
  structured, check-only pass over `upgrade_snippets/`.

## System-wide decisions

See `docs/adr/`.

Cross-cutting engineering guides that apply across the CLI engine and GUI
experiments live in `docs/guides/`.
