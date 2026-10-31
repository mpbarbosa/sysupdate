# Hyprland install status — UNRESOLVED (no Hyprland installed)

**Status:** ❌ As of 2026-10-30 this machine has **no Hyprland binary at all**. The apt package was
removed on 2026-08-17 and the upstream `/opt/hyprland` build was destroyed by its own failed rebuild
on 2026-10-28. `/usr/local/bin/Hyprland` is a dangling symlink and the `update-alternatives` group
holds zero candidates.
**Scope:** incident 1 (below) was a system problem that sysupdate merely reported. **Incident 2 was
caused by this repo's own `setup-hyprland-alternatives.sh`** — see the fixes recorded there.

| What | Expected path | State on 2026-10-30 |
| --- | --- | --- |
| apt build | `/usr/bin/Hyprland` | absent — `apt remove -y hyprland` removed `0.53.3+ds-4` on 2026-08-17 |
| upstream build | `/opt/hyprland/bin/Hyprland` | absent — prefix holds `include/`, `lib/`, `share/` but no `bin/` |
| generic link | `/usr/local/bin/Hyprland` | dangling → `/etc/alternatives/Hyprland` → the missing file above |
| alternatives group | — | registered, **0 candidates** (both pruned as their files vanished) |

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
