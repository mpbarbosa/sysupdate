# sysupdate

A modular Bash script suite for updating and maintaining a Linux system: OS packages, language
toolchains, and individual applications — with a QuickShell GUI front-end planned.

## Features

- Multi-package-manager support: APT/DPKG (Debian/Ubuntu) and Pacman (Arch Linux)
- Interactive and quiet (`-q`) modes, with consistent color-coded output
- Smart handling of kept-back packages, broken dependencies, and unattended-upgrade config
- Package listing and system summary (via `fastfetch`)
- A config-driven **upgrade snippets** system for keeping individual applications up to date
  (browsers, terminals, CLIs, dev tools, etc.) independent of the OS package manager
- Modular architecture: each package manager / tool lives in its own script, so it can be
  extended, tested, or reused on its own

## Quick start

```bash
cd scripts

./system_update.sh                  # interactive full update
./system_update.sh -q                # quiet mode, no prompts
./system_update.sh -f                # full mode: system summary + dist-upgrade
./system_update.sh -s                # simple mode: skip cleanup
./system_update.sh -c                # cleanup only
./system_update.sh -l                # list installed packages
./system_update.sh --list-detailed   # list installed packages with details

./system_update.sh --list-snippets       # list available app upgrade snippets
./system_update.sh --snippet firefox     # run a single upgrade snippet by ID
```

Run `./system_update.sh -h` for the full list of options.

## Project layout

```
scripts/
├── system_update.sh      # main orchestrator
├── system_summary.sh      # system info summary (fastfetch)
├── lib/                    # core utilities and package-manager modules
└── upgrade_snippets/       # per-application update scripts/configs
```

See `CLAUDE.md` for a detailed architecture overview.

## Engineering guides

Cross-cutting engineering and testing guides adapted for this repo live in
[`docs/guides/`](docs/guides/). Start with
[`docs/guides/README.md`](docs/guides/README.md).

## Status

This project is under active development. The QuickShell GUI front-end is planned but not yet
implemented; the script suite is fully usable from the command line in the meantime.

## License

MIT — see [LICENSE](LICENSE).
