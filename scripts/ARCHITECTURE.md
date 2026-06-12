# System Update Architecture Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     system_update.sh                        │
│                   (Main Orchestrator)                       │
│                                                             │
│  • Argument parsing                                         │
│  • Flow control                                             │
│  • Module coordination                                      │
│  • NO business logic                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ sources
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       lib/ Modules                          │
└─────────────────────────────────────────────────────────────┘
              │
              ├─────────────────────────────────────────┐
              │                                         │
              ▼                                         ▼
┌──────────────────────────┐           ┌──────────────────────────┐
│    core_lib.sh           │           │  Package Managers        │
│  (Foundation Layer)      │           │                          │
├──────────────────────────┤           ├──────────────────────────┤
│ • Color definitions      │◄──────────┤ • apt_manager.sh         │
│ • print_* functions      │           │ • pacman_manager.sh      │
│ • ask_continue()         │           │ • dpkg_manager.sh        │
│ • detect_package_mgr()   │           │ • snap_manager.sh        │
│ • compare_versions()     │           │ • cargo_manager.sh       │
└──────────────────────────┘           │ • pip_manager.sh         │
                                       │ • npm_manager.sh         │
                                       │ • app_managers.sh        │
                                       └──────────────────────────┘
```

## Layered Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Layer 4: User Interface (CLI)                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  system_update.sh --quiet --full                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  Layer 3: Orchestration Layer                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  system_update.sh (main logic)                           │  │
│  │  • Parse arguments                                       │  │
│  │  • Detect package manager                                │  │
│  │  • Call appropriate manager modules                      │  │
│  │  • Handle flow control                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  Layer 2: Business Logic Layer (Package Managers)              │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │ apt_mgr.sh │ │pacman_mgr │ │ cargo_mgr  │ │  app_mgr   │  │
│  │            │ │    .sh     │ │    .sh     │ │    .sh     │  │
│  │ • update   │ │ • update   │ │ • update   │ │ • kitty    │  │
│  │ • upgrade  │ │ • upgrade  │ │ • toolchn  │ │ • calibre  │  │
│  │ • cleanup  │ │ • cleanup  │ │ • packages │ │ • copilot  │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
│                                                                │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │ snap_mgr   │ │  pip_mgr   │ │  npm_mgr   │ │ dpkg_mgr   │  │
│  │    .sh     │ │    .sh     │ │    .sh     │ │    .sh     │  │
│  │ • refresh  │ │ • update   │ │ • update   │ │ • maintain │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  Layer 1: Foundation Layer (Core Utilities)                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  core_lib.sh                                             │  │
│  │  • Color definitions (RED, GREEN, BLUE, etc.)            │  │
│  │  • Output formatters (print_status, print_error, etc.)   │  │
│  │  • User interaction (ask_continue)                       │  │
│  │  • System utilities (detect_package_manager)             │  │
│  │  • Version comparison (compare_versions)                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

## Module Dependencies

```
system_update.sh
├── requires → core_lib.sh
├── requires → apt_manager.sh
│   └── requires → core_lib.sh
├── requires → pacman_manager.sh
│   └── requires → core_lib.sh
├── requires → dpkg_manager.sh
│   └── requires → core_lib.sh
├── requires → snap_manager.sh
│   └── requires → core_lib.sh
├── requires → cargo_manager.sh
│   └── requires → core_lib.sh
├── requires → pip_manager.sh
│   └── requires → core_lib.sh
├── requires → npm_manager.sh
│   └── requires → core_lib.sh
└── requires → app_managers.sh
    └── requires → core_lib.sh
```

## Data Flow

```
User Input
    │
    ▼
┌──────────────────┐
│ Argument Parser  │ (system_update.sh)
└──────────────────┘
    │
    ├─ quiet mode? → Set QUIET_MODE=true
    ├─ full mode?  → Set FULL_MODE=true
    ├─ list mode?  → list_all_packages() → Exit
    └─ cleanup?    → cleanup() → Exit
    │
    ▼
┌──────────────────┐
│ Detect Package   │ (detect_package_manager)
│ Manager          │
└──────────────────┘
    │
    ├─ apt?    → Execute APT workflow
    └─ pacman? → Execute Pacman workflow
    │
    ▼
┌──────────────────┐
│ Execute Package  │
│ Manager Workflow │
└──────────────────┘
    │
    ├─ check_broken_packages()     ──┐
    ├─ check_unattended_upgrades() ──┤
    ├─ update_package_list()       ──┤
    ├─ upgrade_packages()          ──┤ Package Manager
    ├─ maintain_dpkg_packages()    ──┤ Specific
    └─ cleanup()                   ──┘
    │
    ▼
┌──────────────────┐
│ Update Universal │
│ Package Managers │
└──────────────────┘
    │
    ├─ update_snap_packages()
    ├─ update_rust_packages()
    ├─ update_pip_packages()
    └─ update_npm_packages()
    │
    ▼
┌──────────────────┐
│ Update           │
│ Applications     │
└──────────────────┘
    │
    ├─ check_kitty_update()
    ├─ update_github_copilot_cli()
    └─ check_calibre_update()
    │
    ▼
┌──────────────────┐
│ Final Cleanup    │ (if not simple mode)
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ Show Summary     │
└──────────────────┘
    │
    ▼
Exit
```

## Cohesion Analysis

### High Cohesion (Good ✅)

Each module contains **strongly related functions**:

```
apt_manager.sh
├── update_package_list()        ◄─── All APT-specific
├── upgrade_packages()            ◄─── operations grouped
│   (uses apt upgrade)            ◄─── (modern apt command)
├── full_upgrade()                ◄─── 
├── cleanup()                     ◄─── 
└── check_broken_packages()       ◄───  

core_lib.sh
├── print_status()                ◄─── All formatting
├── print_error()                 ◄─── and utility
├── print_success()               ◄─── functions
└── ask_continue()                ◄─── together
```

### Low Coupling (Good ✅)

Modules are **independent** and **loosely coupled**:

```
apt_manager.sh ←─┐
                 ├─── Only depend on core_lib.sh
snap_manager.sh ←┤    (No cross-dependencies)
                 │
npm_manager.sh ←─┘

Adding/removing one module ≠ Affects others ✅
```

## Comparison with Monolithic Design

### Monolithic (Before) ❌

```
┌─────────────────────────────────────┐
│     system_update.sh (2606 lines)   │
│                                     │
│ Colors + Functions + APT + Pacman + │
│ Snap + Cargo + pip + npm + Apps +   │
│ Main Logic ALL TOGETHER             │
│                                     │
│ Low Cohesion + High Coupling        │
└─────────────────────────────────────┘
```

### Modular (After) ✅

```
┌──────────────┐
│ Orchestrator │ (390 lines)
└──────┬───────┘
       │
       ├─ core_lib.sh (130 lines)
       ├─ apt_manager.sh (560 lines)
       ├─ pacman_manager.sh (108 lines)
       ├─ snap_manager.sh (52 lines)
       ├─ cargo_manager.sh (88 lines)
       ├─ pip_manager.sh (55 lines)
       ├─ npm_manager.sh (54 lines)
       └─ app_managers.sh (165 lines)

High Cohesion + Low Coupling ✅
```

## Benefits Summary

| Aspect | Benefit |
|--------|---------|
| **Maintainability** | Small, focused files (42-560 lines) |
| **Testability** | Can test modules independently |
| **Reusability** | Functions can be sourced in other scripts |
| **Extensibility** | Add new managers without touching existing code |
| **Debugging** | Easy to isolate issues to specific module |
| **Collaboration** | Multiple developers can work on different modules |
| **Understanding** | Clear separation makes code easier to understand |

---

**Architecture Version:** 1.0  
**Date:** 2024-11-11  
**Design Pattern:** Modular Architecture with Layered Separation
