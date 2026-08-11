# Feasibility: two Hyprland installs switchable via `update-alternatives`

**Question:** Can we keep two Hyprland versions configured with `update-alternatives` — one from **apt**, one built from the **upstream repo** — and switch between them? (The kitty treatment, applied to Hyprland.)

**Verdict:** ⚠️ **Feasible, but materially harder and riskier than kitty.** kitty is a self-contained app bundle (two binaries, no system libraries). Hyprland is a compositor with its own shared-library stack (`hyprutils`, `hyprlang`, `hyprcursor`, `aquamarine`, …) plus plugins (`hyprpm`). Doing this safely requires **isolating the upstream build in its own `/opt/hyprland` prefix** so its libraries can never collide with apt's — that collision is exactly what broke Hyprland before (see [`hyprland-status.md`](./hyprland-status.md)).

**Assessed:** 2026-08-10 (assessment + setup script; the source build itself needs `sudo` and must be run by the user).

---

## Current state (measured)

| Install | Path | Version | Ownership |
| --- | --- | --- | --- |
| **apt** | `/usr/bin/Hyprland` (+ `hyprctl`, `hyprpm`, `start-hyprland`) | **0.53.3** (`0.53.3+ds-4`) | real files, **dpkg-owned** (pkg `hyprland`); libs under `/usr/lib/x86_64-linux-gnu/hyprland/` |
| **upstream** | *(not yet installed)* → target `/opt/hyprland/bin/Hyprland` | **0.56.2** (latest github release) | to be built into an isolated prefix |

- **Active now:** apt 0.53.3 (the earlier broken `/usr/local` source build is gone; the distro package replaced it and runs clean).
- No `Hyprland` alternatives group exists; **`/usr/local/bin/Hyprland` is free** (and precedes `/usr/bin` in PATH).
- apt is **3 minor releases behind** upstream (0.53.3 vs 0.56.2), which is the real motivation for coexistence: keep the stable distro build while running bleeding-edge upstream on demand.

## Why this is harder than kitty (read before deciding)

1. **It's a dependency *chain*, not one binary.** Building upstream 0.56.2 needs the matching 0.56-era `hyprutils`/`hyprlang`/`hyprcursor`/`aquamarine`/`hyprland-protocols`/`hyprwayland-scanner`. apt ships the 0.53.3-era versions. So a from-source 0.56.2 typically means building that whole `hypr*` stack too — into the same isolated prefix. This is the bulk of the work and the main fragility.
2. **ABI isolation is mandatory.** The previous breakage was a `/usr/local` build linking `/usr/lib` sonames that a later `apt upgrade` replaced with an incompatible major. The mitigation here: install upstream **entirely under `/opt/hyprland`** (bin + lib + share) and bake an install RPATH (`-DCMAKE_INSTALL_RPATH=/opt/hyprland/lib`) so the upstream `Hyprland` resolves *its own* libraries, independent of apt. Never let it fall back to `/usr/lib` hypr* libs.
3. **Runtime coupling beyond the binary.** Plugins (`hyprpm`), the wayland session file (`/usr/share/wayland-sessions/hyprland.desktop`), and `XDG_DATA_DIRS`/portal wiring may need the active build's `share/` on the path. Switching the binary via alternatives does **not** switch those automatically — document and handle at login-session level.
4. **A running compositor cannot swap under itself.** `update-alternatives --config Hyprland` changes what the *next* login launches; it does not migrate a live session.

## The design (mirrors kitty, adapted)

- **Isolated upstream prefix:** build/install upstream into `/opt/hyprland` (unowned by dpkg), with RPATH so it's self-contained.
- **Generic link in `/usr/local/bin`** (unowned, precedes `/usr/bin`), with **`Hyprland` as master** and **`hyprctl` + `hyprpm` as slaves** (they are released and version-locked together — never mix apt-`Hyprland` with upstream-`hyprctl`).

```bash
sudo update-alternatives --install /usr/local/bin/Hyprland Hyprland /usr/bin/Hyprland 53 \
    --slave /usr/local/bin/hyprctl hyprctl /usr/bin/hyprctl \
    --slave /usr/local/bin/hyprpm  hyprpm  /usr/bin/hyprpm
sudo update-alternatives --install /usr/local/bin/Hyprland Hyprland /opt/hyprland/bin/Hyprland 56 \
    --slave /usr/local/bin/hyprctl hyprctl /opt/hyprland/bin/hyprctl \
    --slave /usr/local/bin/hyprpm  hyprpm  /opt/hyprland/bin/hyprpm
sudo update-alternatives --config Hyprland      # interactively switch
# or pin one: sudo update-alternatives --set Hyprland /opt/hyprland/bin/Hyprland
```

Priorities encode the versions (apt 53, upstream 56); in **auto** mode the higher priority (upstream) wins, matching the kitty arrangement.

A ready-to-run, idempotent implementation lives at [`scripts/setup-hyprland-alternatives.sh`](../scripts/setup-hyprland-alternatives.sh):

```bash
sudo bash scripts/setup-hyprland-alternatives.sh              # build upstream latest into /opt/hyprland + register alternatives
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps  # also build hypr* libs apt lacks (hyprutils, hyprgraphics)
sudo bash scripts/setup-hyprland-alternatives.sh --ref v0.56.2
sudo bash scripts/setup-hyprland-alternatives.sh --skip-build # register only (upstream already in /opt/hyprland)
sudo bash scripts/setup-hyprland-alternatives.sh --remove     # tear the group down (leaves both installs in place)
```

The script **registers alternatives deterministically**; the source build aborts with an explicit, actionable message (install a `-dev` package, or pass `--with-deps`) if a dependency isn't satisfiable, rather than producing a silently-broken binary.

### Dependency chain (measured 2026-08-10, building upstream v0.56.2 on Ubuntu resolute)

Configuring v0.56.2 on this system resolved almost everything from apt and surfaced exactly the gaps below (CMake stops at the first miss, so it's iterative):

| Dependency | apt provides | v0.56.2 needs | Action |
| --- | --- | --- | --- |
| `glslang` (cmake config) | `glslang-dev` | present | `sudo apt install glslang-dev` |
| `hyprlang` | 0.6.7 | ≥ 0.6.7 | ✅ apt |
| `hyprcursor` | 0.1.13 | ≥ 0.1.7 | ✅ apt |
| **`aquamarine`** | **0.9.3** | pkg-check `≥0.9.3` passes, but 0.56.2's *code* uses `SBackendOptions::logConnection` (added after 0.9.3) → **compile error** | ❌ too old → `--with-deps` builds it |
| **`hyprutils`** | **0.11.0** | **≥ 0.14.0** | ❌ too old → `--with-deps` builds it |
| `hyprgraphics` | *(not packaged)* | required | ❌ → `--with-deps` builds it |
| `libinput` | 1.31.1 (`libinput-dev`) | ≥ 1.29 | `sudo apt install libinput-dev` |
| `libeis-1.0` | 1.5.0 (`libeis-dev`) | required | `sudo apt install libeis-dev` |
| **`lua`** | 5.5.0 (`liblua5.5-dev`) | `≥5.5, <5.6` | `sudo apt install liblua5.5-dev` |
| **`wayland-protocols`** | **1.47** | **≥ 1.49** | ❌ too old → `--with-deps` installs it (data-only*) |

\* wayland-protocols is installed **data-only** (no meson build). Building it runs `wayland-scanner --strict` to generate per-protocol enum headers that *are* install targets in 1.49, and that step fails DTD validation on newer staging XMLs against the older system wayland-scanner — so both `meson install` and `meson install --no-rebuild` fail. But Hyprland never needs those C headers; it consumes wayland-protocols purely as data (the XML files, located via `pkg-config --variable=pkgdatadir`). So the script copies the XML tree (stable/staging/unstable) into `/opt/hyprland/share/wayland-protocols` and writes a `.pc` with the version + pkgdatadir — no meson, no wayland-scanner, no compile.

So the working sequence here is:

```bash
sudo apt install glslang-dev libinput-dev libeis-dev liblua5.5-dev
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps
```

> **Compiler / GCC 15:** Build with the **system g++ (GCC 15)** — this is required, not
> optional: apt's C++ libraries (re2, hyprutils, …) are built with GCC 15 and need its
> libstdc++ (`GLIBCXX_3.4.34`). An older g++ (e.g. `g++-14`) links an older libstdc++ and
> every apt C++ lib then fails to link (`undefined reference to …@GLIBCXX_3.4.34`).
> Use `--cxx clang++` only if you prefer clang (also libstdc++-based); never an older g++.
>
> **libstdc++ gap — `std::ranges::starts_with`:** Ubuntu resolute's libstdc++ (GCC 15.2)
> does **not** implement `std::ranges::starts_with` (P1659) — `__cpp_lib_ranges_starts_ends_with`
> is undefined and it's absent from `<algorithm>`. Hyprland 0.56.2 uses it in exactly one spot
> (`helpers/MiscFunctions.cpp`), on a lazy `transform_view` — so the `std::string_view::starts_with`
> member won't substitute; the *range* algorithm is genuinely required. When the toolchain lacks
> it, the script provides it via a **force-included compat shim** (`-include`) that defines
> `std::ranges::starts_with` for input ranges, rather than patching Hyprland's source. The shim is
> guarded on `__cpp_lib_ranges_starts_ends_with`, so it's a no-op once the stdlib gains the
> algorithm. (`-Wno-template-body` alone wasn't enough — the symbol is genuinely absent, not just
> eagerly diagnosed; it's kept as a harmless safety net.)

`--with-deps` (default list: `hyprutils wayland-protocols aquamarine hyprgraphics`) installs each dependency's latest release into the isolated prefix — `hyprwm/<dep>` built via CMake with RPATH, `wayland-protocols` copied in data-only — in an order where earlier deps are visible to later ones (hyprutils first; wayland-protocols before aquamarine), and points Hyprland's `PKG_CONFIG_PATH`/`CMAKE_PREFIX_PATH` at `/opt/hyprland` so those fresh builds win over apt's.

## Caveats (these decide whether it's worth it)

1. **Maintenance burden is ongoing.** Every future upstream bump re-triggers the whole `hypr*` dependency-chain build. Unlike kitty's "copy the app bundle", there is no cheap refresh. Budget for it.
2. **A future `apt upgrade` won't touch `/opt/hyprland`** (good — that's the isolation), but it *also* means the upstream build won't get security fixes automatically. You own its updates.
3. **Manual cleanup on removal.** Because the alternatives are registered by hand, `apt remove hyprland` will **not** remove the `/usr/bin/Hyprland` entry — it would dangle. Remove it yourself (`sudo update-alternatives --remove Hyprland /usr/bin/Hyprland`) or run the setup script's `--remove`.
4. **Session launcher.** Ensure `/usr/share/wayland-sessions/hyprland.desktop` (or your login manager) launches `Hyprland` via PATH (so `/usr/local/bin` wins) — or point it at `/usr/local/bin/Hyprland`. `start-hyprland` (apt) is a wrapper; if you rely on it, keep the apt build for session bring-up and switch only for manual runs.
5. **sysupdate snippet.** `scripts/upgrade_snippets/hyprland.yaml` reads `Hyprland --version` (the active build) but `version.source: github`. Under alternatives that is honest for the active build, but the snippet must also stop steering apt installs toward a `/usr/local` source rebuild. The companion PR makes `update_hyprland.sh` alternatives-aware (refresh the `/opt/hyprland` candidate in place; never purge apt).

## Recommendation

- **Use `update-alternatives`** if you specifically want to run **upstream 0.56.2 alongside stable apt 0.53.3** with a root-managed, `--config`-switchable selection — accepting the dependency-chain build and its maintenance cost. The isolated `/opt/hyprland` prefix is what makes it safe.
- **Skip it** if you just want the newest Hyprland: track upstream only (and drop the apt package), or stay on apt. The dual setup pays off only if you genuinely need *both* available and switchable.
- Either way, the companion snippet change keeps sysupdate from pushing Hyprland back into the fragile `/usr/local` source build.

## Verification (after setting it up)

```bash
update-alternatives --display Hyprland        # both links + which is active
command -v Hyprland                            # -> /usr/local/bin/Hyprland (the generic link)
Hyprland --version                             # the active version
ldd /opt/hyprland/bin/Hyprland | grep -i hypr  # upstream libs must resolve under /opt/hyprland, not /usr/lib
sudo update-alternatives --config Hyprland     # switch, log out/in, re-check `Hyprland --version`
```
