# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`sysupdate` is a Bash script suite for updating Linux systems and applications across multiple
package managers and standalone tools. Everything lives under `scripts/`.

## Running and validating

```bash
# Run the main updater (interactive)
./scripts/system_update.sh

# Common flags
./scripts/system_update.sh -q              # quiet/non-interactive
./scripts/system_update.sh -s              # simple mode (skip cleanup)
./scripts/system_update.sh -f              # full mode (system_summary.sh + dist-upgrade)
./scripts/system_update.sh -c              # cleanup only
./scripts/system_update.sh -l              # list installed packages
./scripts/system_update.sh --list-detailed
./scripts/system_update.sh --list-snippets         # list available upgrade_snippets with their IDs
./scripts/system_update.sh --snippet <id> [-q]     # run a single upgrade snippet by SNIPPET_ID

# Syntax-check a script after editing
bash -n scripts/system_update.sh
shellcheck scripts/lib/*.sh scripts/upgrade_snippets/*.sh

# Source a library module in isolation to test individual functions
source scripts/lib/core_lib.sh
source scripts/lib/apt_manager.sh
QUIET_MODE=true
check_updates_available
```

There is no automated test suite; validation is `bash -n` / `shellcheck` plus manual sourcing of
modules as shown above.

Engineering guides for this repo (when to use each one is in the index below):

@docs/guides/README.md

## Architecture

### Orchestrator + library modules (`scripts/system_update.sh`, `scripts/lib/`)

`system_update.sh` is a thin orchestrator: it parses CLI args, sources the modules below, detects
the package manager, and calls into them. It contains **no business logic** of its own.

- `lib/core_lib.sh` — foundation, sourced by every other module. Provides color codes, output
  helpers (`print_status`, `print_success`, `print_warning`, `print_error`, `print_operation_header`,
  `print_section_header`), `ask_continue`, `detect_package_manager` (apt vs pacman), and
  `compare_versions`/`normalize_version_for_comparison`.
- `lib/apt_manager.sh` — APT workflow: `update_package_list`, `check_unattended_upgrades`,
  `check_updates_available`, `upgrade_packages`, `full_upgrade`, `cleanup`, `check_broken_packages`.
- `lib/pacman_manager.sh` — Arch/pacman equivalent: `update_pacman_database`,
  `upgrade_pacman_packages`, `clean_pacman_cache`, `remove_pacman_orphans`, `list_pacman_packages`,
  `check_pacman_config`.
- `lib/dpkg_manager.sh` — `maintain_dpkg_packages` (dpkg-level maintenance/status).
- `lib/app_managers.sh` — snippet-loading machinery (`source_upgrade_snippets`,
  `list_upgrade_snippets`) plus Node.js runtime install/update helpers.
- `lib/upgrade_utils.sh` — shared framework used by `upgrade_snippets/` (see below): YAML config
  reading, version-check workflow, prompts, and generic update handlers.

Modules follow a `if [ -z "$BLUE" ]; then source core_lib.sh; fi` guard so they can be sourced
standalone or via the orchestrator without double-sourcing.

Each package-manager module only depends on `core_lib.sh` — no cross-module dependencies. Adding a
new package manager means adding a new `lib/<name>_manager.sh` and wiring it into
`system_update.sh`.

> Note: `scripts/README.md`, `scripts/ARCHITECTURE.md`, `scripts/REFACTORING_SUMMARY.md`, and
> `scripts/PROJECT_SUMMARY.txt` describe an earlier layout where `cargo_manager.sh`,
> `pip_manager.sh`, `npm_manager.sh`, and `snap_manager.sh` lived in `lib/`. They have since moved
> to `scripts/upgrade_snippets/` as snippets (see below) — those docs are stale on this point.

### Upgrade snippets (`scripts/upgrade_snippets/`)

This is a config-driven plugin system for updating individual applications/tools. Each snippet is
a `.sh` file, optionally paired with a `.yaml` config of the same base name.

- `app_managers.sh::source_upgrade_snippets` sources every `*.sh` in `upgrade_snippets/` (or only
  the one matching `SNIPPET_ID_FILTER` when `--snippet <id>` is passed).
- `app_managers.sh::list_upgrade_snippets` scans the same directory and prints each script's
  `SNIPPET_ID` / `SNIPPET_NAME` header comments.
- Snippet scripts identify themselves via header comments:
  ```bash
  # SNIPPET_ID: firefox
  # SNIPPET_NAME: Firefox Browser
  ```
- Config-driven snippets (e.g. `update_firefox.sh` + `firefox.yaml`) set `CONFIG_FILE` to their
  YAML, then read values via `upgrade_utils.sh::get_config "key.path"` (uses `yq`). The standard
  flow is `config_driven_version_check` (reads `application.*`, `version.*`, supports
  `version.source` of `github`, `github_tags`, `npm`, `apt`) followed by `handle_update_prompt`,
  `handle_installer_script_update`, or `handle_deb_package_update` depending on `update.method`.
- Some snippets are plain manager modules without YAML (`cargo_manager.sh`, `pip_manager.sh`,
  `npm_manager.sh`, `snap_manager.sh`) — they define their own `update_*_packages` function and
  rely only on `core_lib.sh`.
- `upgrade_snippets/examples/` contains example YAML configs (e.g. for `nodejs_app.yaml`).
  `upgrade_snippets/QUICK_REFERENCE.md` and the various `README_*.md`/`REQUIREMENTS_*.md` files
  document specific snippet families (Node.js runtime vs Node.js app updates, GDB, fwupd, Google
  Chrome, oh-my-bash).

When adding a new snippet: create `update_<name>.sh` with `SNIPPET_ID`/`SNIPPET_NAME` headers,
source `lib/upgrade_utils.sh`, and (if config-driven) add a matching `<name>.yaml`. No changes to
`system_update.sh` are needed — snippets are auto-discovered.

### Other entry points

- `scripts/system_summary.sh` — runs `fastfetch` for a system info summary; invoked automatically
  by `system_update.sh -f`.
