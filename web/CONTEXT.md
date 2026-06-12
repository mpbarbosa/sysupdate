# Context: sysupdate Web Dashboard

A planned browser-based "Cyber-Terminal HUD" front-end for sysupdate (React 18 + Vite 6 +
Tailwind CSS). Currently design-only — see [DESIGN.md](DESIGN.md).

## Glossary

### sysupdate Web Dashboard
The browser-based front-end described in `DESIGN.md`. A client of the core CLI engine
(`sysupdate`, see root `CONTEXT-MAP.md`); not a reimplementation of its update logic.

### Category
One of `system`, `node`, `python`, `rust`, `apps` (plus `all` for schedule tasks) — the grouping
used by `UpdateItem`, `LogEntry`, and `ScheduleTask` to classify what is being updated. Maps onto
the core CLI's update mechanisms:

- `system` → apt/pacman (OS package manager)
- `node` → `npm_manager.sh`
- `python` → `pip_manager.sh`
- `rust` → `cargo_manager.sh`
- `apps` → all other `upgrade_snippets/` (config-driven app snippets, `snap_manager.sh`)

This mapping is the intended correspondence; it is not yet wired up (the Dashboard currently uses
mock data).

### ScheduleTask
A maintenance cycle shown in `ScheduleView.tsx` ("Automated Cron Daemon"), with a `cron`
expression and a `command` (e.g. `sysupdate --snippet firefox`). Unlike the Live Output Console
(see "Open questions" in root `CONTEXT-MAP.md`), scheduling has a clear intended resolution:
enabling a `ScheduleTask` should manage a real entry in the user's `crontab` that invokes
`sysupdate`/`--snippet <id>`, not a simulated execution. `lastRun`/`nextRun` reflect the actual
crontab schedule.

### Severity
One of `info`, `minor`, `major` on `UpdateItem` — how urgent an available update is. Two-track
basis:

- `system` category (apt/pacman): `major` = a security update (apt's `security_updates` count in
  `check_updates_available`, `apt_manager.sh`); `info`/`minor` = a regular update. Apt is the only
  package manager with a security/non-security distinction; pacman updates default to `info`.
- `node`/`python`/`rust`/`apps`: derived from a semver diff between `currentVersion` and
  `latestVersion` — major version bump → `major`, minor bump → `minor`, patch/other → `info`.

### Status
The `UpdateItem` lifecycle: `up_to_date` (no update available) → `ready` (update available, not
started) → `updating` (in progress) → `failed` or back to `up_to_date` (on completion). A
straightforward UI state machine; no CLI-specific mapping beyond the lifecycle itself.

### SystemConfig.silentMode
Maps directly to the core CLI's existing `-q` (quiet/non-interactive) flag on `system_update.sh`.

### SystemConfig.autoUpdate
Not a separate mechanism — governed by whether any `ScheduleTask` is `enabled` (see
`ScheduleTask` above). A standalone `autoUpdate` toggle would be redundant with the schedule
list.

## Corrections to DESIGN.md

`DESIGN.md` is kept as-imported (source-of-truth design doc); known deviations from this
project's reality are tracked here instead of editing it in place.

### `SystemConfig.repositories`
`DESIGN.md` lists `{ brew, apt, npm, pip, cargo }`. `brew` is generic AI-Studio scaffolding with
no basis in this project (the core CLI has no Homebrew/macOS support), and `pacman` is missing
despite being one of the two package managers the core CLI supports
(`apt_manager.sh` / `pacman_manager.sh`). The corrected shape should be
`{ apt, pacman, npm, pip, cargo }`.
