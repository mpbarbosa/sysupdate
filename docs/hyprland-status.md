# Hyprland install status — RESOLVED (was: shared-library ABI mismatch)

**Status:** ✅ Resolved as of 2026-08-10 — the broken `/usr/local` source build was replaced by the
distro package (`apt` `hyprland 0.53.3+ds-4`, at `/usr/bin/Hyprland`), which runs clean
(`Hyprland --version` → 0.53.3, no missing libraries).
**Originally discovered:** 2026-07-29, via the sysupdate dashboard (Hyprland card showed
`unknown → unknown`, "Failed to get current Hyprland version").
**Scope:** This was a **system / installation** problem, not a sysupdate bug. sysupdate reported it
faithfully.

> **Coexistence option:** to run the newer **upstream** Hyprland (0.56.x) *alongside* the stable apt
> build and switch between them via `update-alternatives`, see
> [`hyprland-dual-install-assessment.md`](./hyprland-dual-install-assessment.md) and
> [`scripts/setup-hyprland-alternatives.sh`](../scripts/setup-hyprland-alternatives.sh). The upstream
> build must go in an isolated `/opt/hyprland` prefix precisely to avoid repeating the ABI mismatch
> described below.

The remainder of this document records the original breakage for reference.

---

## Symptom

The sysupdate dashboard's Hyprland card shows **MAJOR / RETRY**, versions `unknown → unknown`, and the console logs:

```
Checking Hyprland updates...
Failed to get current Hyprland version
  ↳ Hyprland: error while loading shared libraries: libdisplay-info.so.2: cannot open shared object file: No such file or directory
```

Retrying does not help — the binary itself cannot start.

## Root cause

Hyprland (and `hyprctl`) were built against **older shared-library sonames** that a later system upgrade replaced with **incompatible newer majors**. The old binaries can no longer resolve their libraries:

| Binary | Path | Needs | System has now | Result |
| --- | --- | --- | --- | --- |
| `Hyprland` | `/usr/local/bin/Hyprland` | `libdisplay-info.so.2` | only `libdisplay-info.so.3` (pkg `libdisplay-info3` 0.3.0-1) | `cannot open shared object file` |
| `hyprctl` | `/usr/local/bin/hyprctl` | old re2 ABI | `libre2.so.11` | `undefined symbol: …re2…GlobalReplace…` |

Both binaries live in `/usr/local/bin` → this is a **source build** (not a distro package), compiled against library versions that no longer exist on the system.

### Evidence

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

## Fix (to perform in the other session)

The correct fix is to **rebuild/reinstall Hyprland and hyprctl against the current libraries**:

1. **Preferred — rebuild from source** with today's dependencies:
   - Ensure current dev deps are installed (incl. `libdisplay-info-dev` 0.3.x, current `libre2-dev`).
   - Rebuild Hyprland from source and `make install` (the sysupdate `hyprland` snippet can drive this — see below).
2. **Alternative — use the distro package** (`apt install hyprland`) if you prefer distro-managed binaries over the `/usr/local` source build. Note this may shadow/conflict with the `/usr/local/bin` copies; remove the stale source-built binaries first.

⚠️ **Do NOT** work around it by symlinking `libdisplay-info.so.2 → libdisplay-info.so.3`. Different major sonames mean **different ABIs**; the symlink would likely crash or silently misbehave at runtime.

## How sysupdate handles this now (after 2026-07-29 changes)

Two sysupdate-side improvements landed so this failure is actionable rather than mysterious:

1. **The underlying error is surfaced.** `config_driven_version_check` (in `scripts/lib/upgrade_utils.sh`) now captures the version command's stderr and prints it (`↳ …libdisplay-info.so.2: cannot open…`) instead of only a generic "Failed to get current version".
2. **The Hyprland snippet offers a repair rebuild.** `scripts/upgrade_snippets/update_hyprland.sh` detects "installed but version unreadable" and offers to rebuild/reinstall (which is what repairs the broken libs). Run it directly:
   ```bash
   ./scripts/system_update.sh --snippet hyprland      # then choose the source-build option when prompted
   ```
   (The rebuild needs sudo + build deps; run it in an interactive terminal.)

## Quick verification once repaired

```bash
Hyprland --version        # should print "Hyprland X.Y.Z …" with no library error
hyprctl version           # should print version info with no symbol error
./scripts/system_update.sh --snippet hyprland --check-only   # card should read a real version, not "unknown"
```
