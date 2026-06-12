# System Update - Modular Package Management System

Refactored version of the system_update.sh script following cohesion and coupling principles.

## Architecture

The monolithic 2600-line script has been split into focused, single-responsibility modules:

```
system_update/
├── system_update.sh          # Main orchestrator (coordinator only)
├── lib/
│   ├── core_lib.sh           # Core utilities & output formatting
│   ├── apt_manager.sh        # APT package manager operations
│   ├── pacman_manager.sh     # Pacman package manager operations
│   ├── dpkg_manager.sh       # DPKG maintenance operations
│   ├── snap_manager.sh       # Snap package operations
│   ├── cargo_manager.sh      # Rust/Cargo package operations
│   ├── pip_manager.sh        # Python pip package operations
│   ├── npm_manager.sh        # Node.js npm package operations
│   └── app_managers.sh       # Application updates (Kitty, Calibre, Copilot)
└── README.md                 # This file
```

## Benefits of Modular Design

### High Cohesion
- Each module has a **single, well-defined responsibility**
- `core_lib.sh` - only formatting and common utilities
- `apt_manager.sh` - only APT operations
- `app_managers.sh` - only application-specific updates

### Loose Coupling
- Modules are **independent** and can be tested separately
- Main script just **coordinates** module execution
- Easy to add/remove/replace package managers
- Library modules can be sourced individually if needed

### Maintainability
- ~200-400 lines per file instead of 2600 lines
- Easier to locate and fix bugs
- Clear separation of concerns
- Better code organization

### Reusability
- Individual modules can be used in other scripts
- Functions can be called independently
- Easy to extract specific functionality

## Usage

The main script maintains **100% backward compatibility** with the original:

```bash
# Basic usage (interactive mode)
./system_update.sh

# Quiet mode (no prompts)
./system_update.sh -q

# Full system upgrade
./system_update.sh -f

# List installed packages
./system_update.sh -l

# Cleanup only
./system_update.sh -c

# Show version
./system_update.sh -v

# Help
./system_update.sh -h
```

## Module Details

### core_lib.sh
- Color definitions
- Output formatting functions (`print_*`)
- Common utilities (`ask_continue`, `detect_package_manager`, `compare_versions`)

### apt_manager.sh
- `update_package_list()` - Update APT cache
- `check_unattended_upgrades()` - Configure automatic updates
- `check_updates_available()` - Check for available updates
- `upgrade_packages()` - Upgrade packages with kept-back handling (uses `apt upgrade`)
- `full_upgrade()` - Dist-upgrade operation
- `cleanup()` - Autoremove and autoclean
- `check_broken_packages()` - Fix broken packages

### pacman_manager.sh
- `update_pacman_database()` - Update package database
- `upgrade_pacman_packages()` - Upgrade packages
- `clean_pacman_cache()` - Clean package cache
- `remove_pacman_orphans()` - Remove orphaned packages
- `list_pacman_packages()` - List packages
- `check_pacman_config()` - Configuration checks

### dpkg_manager.sh
- `maintain_dpkg_packages()` - DPKG maintenance and status

### snap_manager.sh
- `update_snap_packages()` - Update Snap packages

### cargo_manager.sh
- `update_rustup_toolchain()` - Update rustup
- `update_rust_toolchains()` - Update Rust toolchains
- `update_cargo_packages()` - Update Cargo packages
- `update_rust_packages()` - Main entry point

### pip_manager.sh
- `update_pip_packages()` - Update Python packages

### npm_manager.sh
- `update_npm_packages()` - Update Node.js global packages

### app_managers.sh
- `check_kitty_update()` - Update Kitty terminal
- `check_calibre_update()` - Update Calibre
- `update_github_copilot_cli()` - Update GitHub Copilot CLI

## Design Principles Applied

### Single Responsibility Principle (SRP)
Each module handles one package manager or category of functionality.

### Open/Closed Principle
Easy to extend with new package managers without modifying existing code.

### Dependency Inversion
Main script depends on abstractions (sourced modules), not concrete implementations.

### High Cohesion
Functions within each module are strongly related and work together.

### Loose Coupling
Modules are independent; changes in one don't require changes in others.

## Testing

Individual modules can be tested by sourcing them:

```bash
# Test APT module functions
source lib/core_lib.sh
source lib/apt_manager.sh
QUIET_MODE=true
check_updates_available
```

## Repository Layout

This repository now ships the modular system update tooling directly in `scripts/`. It is a **complete refactoring** that:

1. Maintains all original functionality
2. Preserves all command-line options
3. Keeps the same user interface
4. Uses the same output formatting

To use it from the repository root, run:

```bash
cd scripts
./system_update.sh
```

## Version

- **Version**: 0.4.1 (Modular)
- **Original Version**: 0.3.0 (Monolithic)
- **Author**: mpb
- **Repository**: https://github.com/mpbarbosa/sysupdate
- **License**: MIT
