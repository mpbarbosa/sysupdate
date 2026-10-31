# Hyprland install status — upstream 0.56.2 installed, 0.57.0 upgrade blocked then unblocked

**Status:** ✅ As of 2026-10-31 this machine runs **upstream Hyprland 0.56.2** from `/opt/hyprland`,
registered in the `update-alternatives` group at priority 56. The apt package is still absent
(removed 2026-08-17); the group therefore holds one candidate, not two.
**Scope:** incident 1 (below) was a system problem that sysupdate merely reported. **Incident 2 was
caused by this repo's own `setup-hyprland-alternatives.sh`** — see the fixes recorded there.
**Incident 3** is the 0.57.0 upgrade attempt that the incident-2 rollback caught cleanly.

| What | Expected path | State on 2026-10-31 |
| --- | --- | --- |
| apt build | `/usr/bin/Hyprland` | absent — `apt remove -y hyprland` removed `0.53.3+ds-4` on 2026-08-17 (candidate `0.53.3+ds-4`) |
| upstream build | `/opt/hyprland/bin/Hyprland` | **present** — `Hyprland 0.56.2` (commit `efb5099`), with aquamarine 0.14.0 / hyprutils 0.14.0 / hyprgraphics 0.5.1 in its `lib/` |
| previous generation | `/opt/hyprland.previous/bin/Hyprland` | present, retained by `commit_prefix` — but **not runnable in place**, see the note under incident 3 |
| generic link | `/usr/local/bin/Hyprland` | → `/etc/alternatives/Hyprland` → `/opt/hyprland/bin/Hyprland` |
| alternatives group | — | `Status: auto`, 1 candidate (`/opt/hyprland/bin/Hyprland`, priority 56), slaves `hyprctl` + `hyprpm` |

---

## Incident 3 (2026-10-31) — v0.57.0 needs `libcanberra-dev`, and the rollback held

### What happened

The `hyprland` snippet offered `0.56.2 → 0.57.0`. The rebuild failed at CMake configure:

```
-- Checking for modules 'xkbcommon>=1.11.0;…;lcms2;libcanberra'
--   Package 'libcanberra' not found
CMake Error at …/FindPkgConfig.cmake:1093 (message):
  The following required packages were not found:
   - libcanberra
  CMakeLists.txt:269 (pkg_check_modules)
==> This run did not produce a working build — restoring the previous /opt/hyprland
    restored. The compositor you had before this run is back in place.
```

**The atomic rebuild added after incident 2 did its job — this is its first real-world test.** The
0.56.2 install was staged aside, the failed run restored it, and the running compositor was never
affected. Compare incident 2, where the same class of failure left the machine with no compositor
on disk.

### Root cause

`libcanberra-dev` had never been installed. The runtime library (`libcanberra0 0.30-18ubuntu3`) was
present, so nothing else on the machine noticed; only `pkg-config --exists libcanberra`, which needs
the `.pc` file from the `-dev` package, could see the gap. Hyprland v0.57.0 added `libcanberra` to
the `pkg_check_modules` call at `CMakeLists.txt:269`; 0.56.2 did not ask for it.

Every other module in that call was already satisfied — this was a one-package gap, fixed by:

```bash
sudo apt-get install -y libcanberra-dev     # 0.30-18ubuntu3, 6.8 kB
```

### Contributing cause: the failure message pointed at the wrong fix

`setup-hyprland-alternatives.sh` printed one generic message for every configure failure. It led
with the hypr*-stack source build (`--with-deps`, several minutes) and buried the real fix — "if
instead a plain -dev package is missing, apt-install it and re-run" — in its last line. For a
missing 6.8 kB apt package it steered the reader toward rebuilding four libraries from source.

Fixed by `explain_configure_failure`, which reads the configure log back and names what was actually
unsatisfied and the one command that fixes it:

| Unsatisfied | What the message now says |
| --- | --- |
| `libcanberra` | `sudo apt-get install -y libcanberra-dev` |
| `aquamarine>=0.15.0` | `sudo bash …/setup-hyprland-alternatives.sh --with-deps=aquamarine` |
| both at once | both lines, each naming only its own modules |
| a module with no known apt package | `apt-file search <module>.pc` |
| nothing pkg-config-shaped in the log | says so, and falls back to the generic advice |

It reads CMake's own "The following required packages were not found" list rather than the bare
`Package 'x' not found` lines, because Hyprland probes *optional* modules the same way: a real
v0.57.0 log contains `Package 'udis86' not found` immediately followed by "falling back to
subproject", and an earlier version of the function sent the reader hunting for a `udis86` package
the build never needed. Behaviour cover (including that case) is in
[`tests/integration/hyprland_setup_prefix.bats`](../tests/integration/hyprland_setup_prefix.bats).

### What a v0.57.0 attempt needs

Measured on 2026-10-31. v0.57.0's minimums come from its `CMakeLists.txt`:

| Module | Required by 0.57.0 | On this machine | Source |
| --- | --- | --- | --- |
| `aquamarine` | ≥ 0.15.0 | 0.14.0 in `/opt/hyprland`, 0.9.3 in apt | **needs `--with-deps`** (latest tag `v0.15.1`) |
| `hyprutils` | ≥ 0.14.3 | 0.14.0 in `/opt/hyprland`, 0.11.0 in apt | **needs `--with-deps`** (latest tag `v0.14.3`) |
| `hyprgraphics` | ≥ 0.5.1 | 0.5.1 | ok (`--with-deps` rebuilds it anyway) |
| `wayland-protocols` | ≥ 1.49 | 1.50 in `/opt/hyprland`, 1.47 in apt | **needs `--with-deps`** (apt is too old) |
| `hyprlang` | ≥ 0.6.7 | 0.6.7 | ok, exactly at the minimum |
| `hyprcursor` | ≥ 0.1.7 | 0.1.13 | ok |
| `xkbcommon` | ≥ 1.11.0 | 1.13.1 | ok |
| `wayland-server` | ≥ 1.22.91 | 1.24.0 | ok |
| `libinput` | ≥ 1.29 | 1.31.1 | ok |
| `libcanberra` | any | 0.30 | ok **since this incident** |

So the upgrade command is:

```bash
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps      # hyprutils wayland-protocols aquamarine hyprgraphics
```

Do **not** pin the deps to `@v0.14.0` tags here — that pinning is what the incident-2 notes recommend
for rebuilding *0.56.2*, and aquamarine 0.14.0 is below 0.57.0's floor.

### Note: `/opt/hyprland.previous` does not run in place

`commit_prefix` keeps one generation, but the binaries are linked with an absolute
`RUNPATH=/opt/hyprland/lib`, so the retired copy looks for its libraries in the *live* prefix:

```
$ /opt/hyprland.previous/bin/Hyprland --version
error while loading shared libraries: libaquamarine.so.14: cannot open shared object file
```

The libraries are there (`/opt/hyprland.previous/lib/libaquamarine.so.14` exists) — only the path
baked into the binary is wrong. Rolling back therefore means swapping the directories back, not
running the retired binary:

```bash
sudo mv /opt/hyprland /opt/hyprland.bad       # the generation you are rolling back FROM
sudo mv /opt/hyprland.previous /opt/hyprland  # the retired one, now at the path its RUNPATH names
```

A build with `RUNPATH=$ORIGIN/../lib` would make both generations runnable where they stand; that is
not done yet.

---

## Incident 2 (2026-10-28) — a failed rebuild deleted the running compositor

### What happened

`setup-hyprland-alternatives.sh --with-deps` began by doing `rm -rf /opt/hyprland`, then rebuilt the
isolated dependency chain, then failed before installing Hyprland itself. The deps landed
(`libaquamarine 0.15.1`, `libhyprgraphics 0.5.1`, `libhyprutils 0.14.3`, `wayland-protocols`); the
compositor did not. Because the apt build had already been removed in August, **nothing was left on
disk**. The already-running compositor kept working from its deleted inode until the reboot on
2026-10-30, at which point the desktop was gone and the session fell back to GNOME.

### Root cause

Bug 1 below is what turned a failed build into an outage, and is proven by the state left on disk.
Bug 2 is a latent hazard found while investigating; it may well be why the build failed in the first
place, but that is **unverified** — the run produced no log.

1. **The rebuild was destructive before it was successful.** `rm -rf "$DEST"` ran before the build, so
   any failure — in Hyprland *or* in a dependency — left no compositor. Fixed: the prefix is now moved
   aside, rebuilt, and **restored automatically if the run fails** (`stage_prefix` / `rollback_prefix` /
   `commit_prefix`), keeping one generation at `/opt/hyprland.previous` on success. A build whose
   binary has unresolved libraries, or cannot report `--version`, now counts as a failed build and
   rolls back instead of being accepted with a warning.
2. **Dependencies were unpinned while Hyprland was pinned.** Each `--with-deps` name resolved to that
   dependency's *latest* release tag, so `--ref v0.56.2` was built against whatever the deps are
   today. Fixed: deps accept `name@tag` (`--with-deps=aquamarine@v0.14.0`), and the skew hazard is
   documented at `DEPS_DEFAULT`.

A third, older bug surfaced while investigating: `hyprland_alt_upstream_target` used
`grep … | head -1 && return 0`. `head` exits 0 on empty input and the pipeline takes `head`'s status,
so the guard always fired and every fallback below it was dead code — the function returned an empty
string for any non-`/opt` candidate. Fixed, and it now also resolves a destination when the
alternatives group has been pruned to zero candidates.

### Evidence

```
$ readlink /proc/5693/exe                    # the still-running compositor, before the reboot
/opt/hyprland/bin/Hyprland (deleted)

$ ldd <recovered binary> | grep 'not found'  # the deps had moved on underneath it
libaquamarine.so.13 => not found

$ ls /opt/hyprland/lib | grep aquamarine     # soname 14, not the 13 it was linked against
libaquamarine.so.0.15.1
libaquamarine.so.14
```

The binary itself was recoverable from `/proc/<pid>/exe` while the process lived (it identified as
`v0.56.2`), but `libaquamarine.so.0.14.0` existed **only** in that process's memory, readable through
`/proc/<pid>/map_files` — which `yama ptrace_scope=1` denies to an unprivileged peer. The reboot on
2026-10-30 closed that window permanently.

> **Note on running the fix:** `sudo` does not work from inside the Claude desktop app. The app sets
> `no_new_privs` on itself at startup, and the flag is inherited by every child and cannot be
> cleared, so both the agent's shell and the app's Terminal panel are affected
> (`grep NoNewPrivs /proc/self/status` → `1`). Run privileged recovery from a terminal launched
> outside the app.

### Restoring from here

Memory recovery is no longer possible. Two routes remain:

```bash
sudo apt install hyprland                    # 0.53.3+ds-4, 6 new packages, nothing removed
```

```bash
# upstream v0.56.2, now safe to retry: a failure restores whatever was there before
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps --ref v0.56.2
```

For the upstream route, prefer pinning the deps to tags contemporary with the Hyprland ref if the
build fails on version skew, e.g. `--with-deps=hyprutils@v0.14.0,wayland-protocols,aquamarine@v0.14.0`.
Installing the apt build first is the safer order: it gives a working compositor *and* restores the
apt candidate (priority 53) that the alternatives group is designed around.

Regression cover for the rollback and the dep pinning lives in
[`tests/integration/hyprland_setup_prefix.bats`](../tests/integration/hyprland_setup_prefix.bats).

---

## Incident 1 (2026-07-29, historical) — shared-library ABI mismatch

Resolved on 2026-08-10 by replacing the broken `/usr/local` source build with the distro package.
That package was itself removed a week later, which is how the machine reached the state above. Kept
here because the ABI-mismatch mechanism recurred inside the isolated prefix in incident 2.

> **Coexistence option:** to run the newer **upstream** Hyprland *alongside* the stable apt build and
> switch between them via `update-alternatives`, see
> [`hyprland-dual-install-assessment.md`](./hyprland-dual-install-assessment.md) and
> [`scripts/setup-hyprland-alternatives.sh`](../scripts/setup-hyprland-alternatives.sh). The upstream
> build goes in an isolated `/opt/hyprland` prefix precisely to avoid repeating the ABI mismatch
> described below.

### Symptom

The sysupdate dashboard's Hyprland card shows **MAJOR / RETRY**, versions `unknown → unknown`, and the console logs:

```
Checking Hyprland updates...
Failed to get current Hyprland version
  ↳ Hyprland: error while loading shared libraries: libdisplay-info.so.2: cannot open shared object file: No such file or directory
```

Retrying does not help — the binary itself cannot start.

### Root cause

Hyprland (and `hyprctl`) were built against **older shared-library sonames** that a later system upgrade replaced with **incompatible newer majors**. The old binaries can no longer resolve their libraries:

| Binary | Path | Needs | System has now | Result |
| --- | --- | --- | --- | --- |
| `Hyprland` | `/usr/local/bin/Hyprland` | `libdisplay-info.so.2` | only `libdisplay-info.so.3` (pkg `libdisplay-info3` 0.3.0-1) | `cannot open shared object file` |
| `hyprctl` | `/usr/local/bin/hyprctl` | old re2 ABI | `libre2.so.11` | `undefined symbol: …re2…GlobalReplace…` |

Both binaries live in `/usr/local/bin` → this is a **source build** (not a distro package), compiled against library versions that no longer exist on the system.

#### Evidence

```
$ ldd /usr/local/bin/Hyprland | grep 'not found'
        libdisplay-info.so.2 => not found

$ ldconfig -p | grep libdisplay-info
        libdisplay-info.so.3 => /usr/lib/x86_64-linux-gnu/libdisplay-info.so.3
        libdisplay-info.so   => /usr/lib/x86_64-linux-gnu/libdisplay-info.so
# (no .so.2 anywhere)

$ hyprctl version
hyprctl: symbol lookup error: hyprctl: undefined symbol: _ZN3re2…GlobalReplace…

$ dpkg -l | grep display-info
ii  libdisplay-info3:amd64   0.3.0-1   EDID and DisplayID library (shared library)
```

### Fix (as performed at the time)

The correct fix is to **rebuild/reinstall Hyprland and hyprctl against the current libraries**:

1. **Preferred — rebuild from source** with today's dependencies:
   - Ensure current dev deps are installed (incl. `libdisplay-info-dev` 0.3.x, current `libre2-dev`).
   - Rebuild Hyprland from source and `make install` (the sysupdate `hyprland` snippet can drive this — see below).
2. **Alternative — use the distro package** (`apt install hyprland`) if you prefer distro-managed binaries over the `/usr/local` source build. Note this may shadow/conflict with the `/usr/local/bin` copies; remove the stale source-built binaries first.

⚠️ **Do NOT** work around it by symlinking `libdisplay-info.so.2 → libdisplay-info.so.3`. Different major sonames mean **different ABIs**; the symlink would likely crash or silently misbehave at runtime.

### How sysupdate handles this now (after 2026-07-29 changes)

Two sysupdate-side improvements landed so this failure is actionable rather than mysterious:

1. **The underlying error is surfaced.** `config_driven_version_check` (in `scripts/lib/upgrade_utils.sh`) now captures the version command's stderr and prints it (`↳ …libdisplay-info.so.2: cannot open…`) instead of only a generic "Failed to get current version".
2. **The Hyprland snippet offers a repair rebuild.** `scripts/upgrade_snippets/update_hyprland.sh` detects "installed but version unreadable" and offers to rebuild/reinstall (which is what repairs the broken libs). Run it directly:
   ```bash
   ./scripts/system_update.sh --snippet hyprland      # then choose the source-build option when prompted
   ```
   (The rebuild needs sudo + build deps; run it in an interactive terminal.)

### Quick verification once repaired

```bash
Hyprland --version        # should print "Hyprland X.Y.Z …" with no library error
hyprctl version           # should print version info with no symbol error
./scripts/system_update.sh --snippet hyprland --check-only   # card should read a real version, not "unknown"
```
