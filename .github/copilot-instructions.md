# Copilot Instructions

## Build, test, and lint commands

This repository is a Bash script suite. There is no automated test suite; validation is syntax checking, ShellCheck, and targeted manual runs.

```bash
# Main entry point (run from repo root)
./scripts/system_update.sh

# Common targeted runs
./scripts/system_update.sh -h
./scripts/system_update.sh --list-snippets
./scripts/system_update.sh --snippet <id> [-q]

# Full syntax check
bash -n scripts/system_update.sh scripts/lib/*.sh scripts/upgrade_snippets/*.sh

# Single-file syntax check
bash -n scripts/lib/core_lib.sh

# Full lint
shellcheck scripts/system_update.sh scripts/lib/*.sh scripts/upgrade_snippets/*.sh

# Single-file lint
shellcheck scripts/upgrade_snippets/update_firefox.sh

# Module-level manual validation
source scripts/lib/core_lib.sh
source scripts/lib/apt_manager.sh
QUIET_MODE=true
check_updates_available
```

The current ShellCheck baseline is not clean; expect existing findings around dynamic `source` usage and a handful of quoting/local-assignment warnings.

## High-level architecture

- Everything that matters lives under `scripts/`.
- `scripts/system_update.sh` is the thin orchestrator. It parses CLI flags, sources the library modules, detects `apt` vs `pacman`, runs the package-manager workflow, then loads upgrade snippets. Keep business logic out of this file.
- `scripts/lib/core_lib.sh` is the shared foundation. It defines color constants, all `print_*` helpers, `ask_continue`, package-manager detection, and version comparison utilities used across the repo.
- `scripts/lib/apt_manager.sh`, `pacman_manager.sh`, and `dpkg_manager.sh` hold package-manager-specific workflows. These modules depend on `core_lib.sh`, not on each other.
- `scripts/lib/app_managers.sh` is mainly snippet orchestration. It auto-sources every `scripts/upgrade_snippets/*.sh`, or only the matching one when `--snippet <id>` is used.
- `scripts/lib/upgrade_utils.sh` is the shared framework for config-driven snippets. YAML-backed snippets set `CONFIG_FILE`, read settings via `get_config`, call `config_driven_version_check`, then hand off to helpers such as `handle_update_prompt`, `handle_installer_script_update`, or `handle_deb_package_update`.
- `scripts/upgrade_snippets/` is the plugin layer. Some snippets are fully config-driven (`update_firefox.sh` + `firefox.yaml`); others are standalone manager-style snippets such as `pip_manager.sh`, `npm_manager.sh`, `cargo_manager.sh`, and `snap_manager.sh`.
- `scripts/system_summary.sh` is a separate entry point used by `./scripts/system_update.sh -f`.

## Key conventions

- Prefer `CLAUDE.md` over older docs when the docs disagree. Several files under `scripts/` still describe the pre-snippet layout where `cargo`, `pip`, `npm`, and `snap` lived in `lib/`; the current layout keeps those under `scripts/upgrade_snippets/`.
- Library modules are designed to be sourced standalone. Follow the existing guard pattern before sourcing `core_lib.sh`:

```bash
if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi
```

- Use the shared output helpers from `core_lib.sh` (`print_status`, `print_success`, `print_warning`, `print_error`, `print_operation_header`, `print_section_header`) instead of ad hoc `echo` formatting.
- Respect `QUIET_MODE`, `SIMPLE_MODE`, `FULL_MODE`, `VERBOSE_MODE`, and `SNIPPET_ID_FILTER`; snippet and manager behavior is expected to flow from those globals.
- Snippet discovery depends on header comments. New snippet scripts should declare:

```bash
# SNIPPET_ID: firefox
# SNIPPET_NAME: Firefox Browser
```

- Config-driven snippets should keep behavior in YAML where possible: set `CONFIG_FILE` to the matching `.yaml`, read values with `get_config`, and reuse `upgrade_utils.sh` helpers instead of duplicating version-check/update flow.
- Snippets typically execute themselves when sourced. `system_update.sh` does not call named snippet functions after loading them, so a new snippet must run its entrypoint at file end if it should participate in the update pass.
