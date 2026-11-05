# Hyprland install status — 0.57.0 built with g++-16, parked by a failed 0.57.1 run

**Status:** ⚠️ As of 2026-11-05 **nothing runnable is at `/opt/hyprland`**: the 0.57.0 build (tag
`v0.57.0`, commit `0aa6745`, built with `g++-16`) sits at `/opt/hyprland.rollback.1375914`, where a
killed run left it, and `update-alternatives` is pointing at a path with no binary behind it. The
install is intact — it is in the wrong directory, not lost. See incidents 4 and 4b, and the recovery
line at the end of 4b. Until then this page's 2026-10-31 state (below) describes where things stood
when 0.57.0 was registered in the `update-alternatives` group at priority 56. The 0.56.2 generation it replaced is retained at
`/opt/hyprland.previous`. The apt package is still absent (removed 2026-08-17), so the group holds
one candidate, not two.
**Scope:** incident 1 (below) was a system problem that sysupdate merely reported. **Incident 2 was
caused by this repo's own `setup-hyprland-alternatives.sh`** — see the fixes recorded there.
**Incident 3** is the 0.57.0 upgrade: four attempts, three rolled back cleanly by the incident-2
guard, each failing on a different and more interesting thing than the last. **Incident 4** is the
0.57.1 attempt: it repeated incident 3's compiler failure because the fix for that one was written
down in this file instead of into the script's default — and then **incident 4b**, found while
checking that rollback: the restore reported success over a prefix with no compositor in it.

| What | Expected path | State on 2026-10-31 |
| --- | --- | --- |
| apt build | `/usr/bin/Hyprland` | absent — `apt remove -y hyprland` removed `0.53.3+ds-4` on 2026-08-17 |
| upstream build | `/opt/hyprland/bin/Hyprland` | **`Hyprland 0.57.0`**, 138 shared libs all resolving, needs `GLIBCXX_3.4.35` |
| its dependencies | `/opt/hyprland/lib`, `/opt/hyprland/share` | aquamarine 0.15.1, hyprutils 0.14.3, hyprgraphics 0.5.1, hyprland-protocols 0.8.0, wayland-protocols 1.50 |
| previous generation | `/opt/hyprland.previous/bin/Hyprland` | the 0.56.2 build — present, **not runnable in place**, see the note under incident 3 |
| generic link | `/usr/local/bin/Hyprland` | → `/etc/alternatives/Hyprland` → `/opt/hyprland/bin/Hyprland` (0.57.0) |
| alternatives group | — | `Status: auto`, 1 candidate at priority 56, slaves `hyprctl` + `hyprpm` |
| generic links | `/usr/local/bin/{Hyprland,hyprctl,hyprpm}` | all three symlinks into `/etc/alternatives/` — `hyprpm` needed a stale 2025 file moved aside first, see incident 3 |
| greeter session entry | `/usr/local/share/wayland-sessions/hyprland.desktop` | present (Dec 2025, from the old `/usr/local` source install), `Exec=Hyprland` — a bare PATH launch, so it follows the alternatives link |

**0.57.0 has since been logged into and verified running**: pid from `/opt/hyprland/bin/Hyprland`, both
monitors up, and the isolated `libaquamarine.so.0.15.1` / `libhyprutils.so.0.14.3` /
`libhyprgraphics.so.0.5.1` mapped into the live process, so the prefix's RPATH holds at runtime too.
During the four rebuild attempts, though, nothing was running it. The session was GNOME
(`XDG_CURRENT_DESKTOP=ubuntu:GNOME`, wayland), there is no `Hyprland` process and no
`/run/user/1000/hypr` instance, which is why four rebuilds could swap `/opt/hyprland` underneath
without consequence. 0.57.0 takes effect the next time the Hyprland session is selected at the
greeter.

---

## Incident 4 (2026-11-05) — v0.57.1 failed on the same C++26 call, and the rollback lost the install

Two separate bugs, found one behind the other. The compiler one wasted a build; the rollback one
left the machine with no runnable compositor **and said everything was fine**.

### What happened

`--snippet hyprland` offered v0.57.1 and the rebuild ran. It failed at 46%, on the same single call
that cost incident 3 two attempts:

```
[ 46%] Building CXX object CMakeFiles/hyprland_lib.dir/src/keybinds/InputState.cpp.o
error: compilation of v0.57.1 failed
       /tmp/hyprland-build-DWaafp/src/src/ipc/s1/S1.cpp:148:130:
       error: 'std::string' has no member named 'subview'
==> This run did not produce a working build — restoring the previous /opt/hyprland
    restored. The compositor you had before this run is back in place.
```

The incident-2 rollback worked again, so 0.57.0 is still installed and still runnable. Nothing was
lost but the build time.

### Root cause: the compiler default was blind, not wrong

`g++-16` — the compiler incident 3 identified, installed and used — was still on this machine,
unused. The script's default was `CXX="g++"`, the system default, which is GCC 15:

| Compiler | `std::string::subview` | What the default did |
| --- | --- | --- |
| `g++` → `g++-15` | absent | **chosen**, every time |
| `g++-16` | present | installed since 2026-10-31, never considered |

So the one fact that decides the compiler — what its libstdc++ actually provides — was never asked
about. Incident 3's fix was `--cxx g++-16` typed on the command line, recorded in this file and in
the script's header comment. The snippet (`update_hyprland.sh`, which runs the setup script for an
unattended rebuild) passes no `--cxx`, so it could not benefit from a fix that lived in prose.

A header comment is not a default. The route that works has to be the route taken when nobody types
anything.

### The fix: probe, then step up

`setup-hyprland-alternatives.sh` now chooses the compiler instead of assuming one. With no `--cxx`:

1. `cxx_can_build_source` compiles **and runs** a two-line program calling `std::string::subview`
   with the candidate compiler. Both halves matter, and they catch opposite failures: compiling
   catches GCC 15's missing `subview`; *running* catches a binary built against a newer libstdc++
   than the loader will hand it (`GLIBCXX_3.4.NN` at startup). Compiling with `g++-16` proves
   nothing on a machine whose `libstdc++6` is still GCC 15's.
2. If the system `g++` fails that probe, `newer_gxx_majors` lists every `g++-N` on `PATH` with N
   **greater** than the system compiler's major, newest first, and the first one that passes the
   probe is used. Newer only, never older — that is the ABI rule from incident 2's notes, now
   enforced rather than just documented, since an older g++'s libstdc++ cannot resolve apt's C++
   libraries.
3. If nothing on `PATH` passes, the script does not die: refs before v0.57.0 do not call `subview`
   and the system compiler builds them fine. It warns, names the file the build will fail in, and
   gives the exact `apt-get install` line — before the clone, not 46% into the build.

On this machine the auto path now prints:

```
==> g++'s libstdc++ has no std::string::subview — stepping up to g++-16
==> Building with CXX=g++-16 CC=gcc-16 (Hyprland CXXFLAGS: -Wno-template-body)
```

`--cxx` still overrides and is then used exactly as given, with no step-up — it is for forcing a
particular compiler (`clang++`), not for working around the default any more.

## Incident 4b — the restore said "back in place" over a prefix with no binary in it

### What the disk actually held

Checking the result of the rolled-back run (`--snippet hyprland --check-only` reported *no runnable
Hyprland*, and `/usr/local/bin/Hyprland` was a dangling link):

| Path | mtime | Contents |
| --- | --- | --- |
| `/opt/hyprland` | 2026-11-05 10:46 | `include/ lib/ share/` — **no `bin/`**; aquamarine 0.16.0, hyprgraphics 0.6.0 |
| `/opt/hyprland.rollback.1375914` | 2026-10-31 20:17 | the real 0.57.0 install: `bin/Hyprland` (24.1M) + its matching aquamarine 0.15.1 |
| `/opt/hyprland.previous` | 2026-10-31 00:47 | 0.56.2 |

`update-alternatives --query Hyprland` agreed, in its own way: *"alternative
/opt/hyprland/bin/Hyprland ... does not exist; removing from list of alternatives"*.

### The symptom that was visible all along: no `hyprctl`

Checked at 11:30 the same day, while a **Hyprland session was live**: pid 5501, its `/proc/5501/exe`
resolving to `/opt/hyprland.rollback.1375914/bin/Hyprland`, instance `0aa6745f...` — 0.57.0, running
out of the orphaned directory. The staging move is a rename on one filesystem, so the compositor
kept its open inodes and never noticed; `readlink` on `exe` simply follows to the new path. The
compositor was therefore fine. Everything that reaches it by *name* was not:

| Link | Resolves |
| --- | --- |
| `/usr/local/bin/Hyprland` | **dangling** — via `/etc/alternatives/Hyprland` → `/opt/hyprland/bin/Hyprland` |
| `/usr/local/bin/hyprctl` | **dangling** |
| `/usr/local/bin/hyprpm` | **dangling** |

So `hyprctl version` answered *command not found* inside a working Hyprland session. That is the
user-visible face of this incident, and it is worth remembering as a diagnostic: a live compositor
whose `hyprctl` has vanished means the prefix moved under it, not that the compositor is unhealthy.
`/var/lib/dpkg/alternatives/Hyprland` still holds the candidate at priority 56 with both slaves, so
putting the directory back at `/opt/hyprland` makes all three links resolve again with no
re-registration needed.

### Root cause: a killed run orphans its own backup, and the next run stages the wreckage

`mv` preserves mtimes, which is what makes the sequence readable. `/opt/hyprland`'s own mtime is
10:46 — so the run that printed *"restored ... back in place"* put back a directory created at
10:46, not the 0.57.0 install from 10-31. Two runs were involved:

1. **~10:40** — run 1 (pid 1375914) staged the working 0.57.0 aside to
   `/opt/hyprland.rollback.1375914` and built the new dependencies into a fresh `/opt/hyprland`
   (10:46). It then died **without its EXIT trap running** — SIGKILL and SIGHUP (a closed terminal
   during a 20-minute build) both do that. Its backup was left parked.
2. **~11:00** — run 2 found `/opt/hyprland` and dutifully protected it, never asking whether it was
   an install or wreckage. It staged the bin-less leftover aside, failed on `subview` at 11:07,
   restored the leftover, and reported the compositor back in place.

So the rollback was not broken; its *premise* was. It assumes `$DEST` is either a good install or
this run's own half-built prefix, and a killed predecessor creates a third state it has no name for.
Run 2's message was true of what it did and false about what the user had — the worst combination,
because that line is the one that would have raised the alarm.

### The fix: a prefix counts as an install only if it can run

* `prefix_is_usable` asks for an executable `bin/Hyprland`. The build installs that last, after
  every dependency, so libs without a binary is precisely the signature of a build that died
  partway.
* `stage_prefix` checks `$DEST` before protecting it. If it cannot run and a `$DEST.rollback.*`
  orphan can, the orphan is **adopted** — moved back to `$DEST` — and the run proceeds from the
  real install. Newest orphan wins, by mtime rather than by glob order. A usable `$DEST` is never
  traded for an orphan.
* `rollback_prefix` reports what is there rather than what it moved: with no runnable binary it says
  so, and names the orphan that does have one.
* `arm_build_rollback` now traps `HUP` too, closing the likeliest way run 1 escaped its own
  rollback. `SIGKILL` stays untrappable — which is exactly why the adoption above is the real fix
  and the trap is only a narrowing.

Recovering this machine needs no manual `mv`: re-running the script adopts
`/opt/hyprland.rollback.1375914`, then builds v0.57.1 on top of it with the probed compiler, and
restores 0.57.0 if that build fails again.

With a session live, the quick recovery is the better *first* move: it puts `hyprctl` and `hyprpm`
back at the same version as the compositor you are running (0.57.0), where building v0.57.1 first
would leave 0.57.1 tools talking to a 0.57.0 compositor until the next login. Per incident 3,
plugins are built per commit and need rebuilding after the switch either way.

`--skip-build` is that recovery, because the adoption also runs on the registration-only path:

```bash
sudo bash scripts/setup-hyprland-alternatives.sh --skip-build
```

It adopts the orphan, re-registers the alternatives group, and builds nothing. Before this incident
that flag could not recover anything — it stages nothing, so it went straight to the
`[ ! -x "$UP_HYPR" ]` validation and exited with *"not found or not executable"* while the real
install sat in a `$DEST.rollback.*` beside it. A flag that means "the install is already there"
should be able to find the install.

By hand it is two renames, in this order:

```bash
sudo bash -c 'mv /opt/hyprland /opt/hyprland.failed-0.57.1 && mv /opt/hyprland.rollback.1375914 /opt/hyprland'
```

`/opt/hyprland` must move out of the way first: `mv src dst` with an existing directory `dst` moves
`src` *inside* it, which buries the install one level deeper instead of restoring it.

### Why this is not cosmetic: nothing can boot Hyprland in this state

Checked before recommending anything: **no Hyprland on the machine could start.** The session entry
is `Exec=Hyprland`, a bare PATH launch through the dangling link, and both parked builds fail on
their own libraries:

```
/opt/hyprland.rollback.1375914/bin/Hyprland -> libaquamarine.so.14: cannot open shared object file
/opt/hyprland.previous/bin/Hyprland         -> libaquamarine.so.13: cannot open shared object file
```

That is the RPATH isolation working exactly as designed, against us. Their `RUNPATH` is
`/opt/hyprland/lib`, an absolute path — so a prefix moved aside looks for its libraries in whatever
now occupies `/opt/hyprland`, which the dead run had refilled with 0.16.0 deps (`libaquamarine.so.15`
where `.so.14` was wanted). The libraries each binary needs are sitting *in the same directory as
the binary*, and unreachable, because the directory has the wrong name. Forcing the path proves it:

```
$ LD_LIBRARY_PATH=/opt/hyprland.rollback.1375914/lib /opt/hyprland.rollback.1375914/bin/Hyprland --version
Hyprland 0.57.0 built from branch at commit 0aa6745f... clean (VERSION: bump to 0.57.0)
```

The live session survived only because its libraries were mapped before the move. So a logout or
reboot in this state does not degrade Hyprland, it removes it — the greeter's Hyprland entry fails
and you land on GNOME. Worth stating plainly in the orphan warning, which is why `rollback_prefix`
names the parked directory rather than only reporting that the restore happened.

### Verification

`tests/integration/hyprland_setup_prefix.bats` covers all of the above through the existing
`SYSUPDATE_HYPRLAND_SETUP_DEFINE_ONLY=1` seam, with stub compilers standing in for a real
toolchain — including the compiles-but-will-not-run case, which is the ABI half of the probe — plus
the killed-run states for the staging: wreckage at `$DEST` with an orphan to adopt, a usable `$DEST`
that must not be traded, two orphans where the newer must win, and an orphan that cannot run either.

Each of the eleven new guards was then deleted in turn to confirm a named test went red for it.
Ten did immediately. The eleventh — *pick the newest orphan* — stayed **green**: the fixture's pids
happened to list newest-last, so taking the last match it saw passed without comparing mtimes at
all. The test now uses pids whose glob order disagrees with their mtime order, and asserts that
disagreement, so it cannot go quietly green that way again.

---

## Incident 3 (2026-10-31) — the 0.57.0 upgrade: four attempts, four different causes

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

Measured on 2026-10-31, **before** the upgrade — what is installed now is in "How it was
unblocked" below. v0.57.0's minimums come from its `CMakeLists.txt`:

| Module | Required by 0.57.0 | On this machine | Source |
| --- | --- | --- | --- |
| `aquamarine` | ≥ 0.15.0 | 0.14.0 in `/opt/hyprland`, 0.9.3 in apt | **needs `--with-deps`** (latest tag `v0.15.1`) |
| `hyprutils` | ≥ 0.14.3 | 0.14.0 in `/opt/hyprland`, 0.11.0 in apt | **needs `--with-deps`** (latest tag `v0.14.3`) |
| `hyprgraphics` | ≥ 0.5.1 | 0.5.1 | ok (`--with-deps` rebuilds it anyway) |
| `hyprland-protocols` | ≥ 0.8.0 | 0.7.0 in apt, nothing in `/opt/hyprland` | **needs `--with-deps`** (latest tag `v0.8.0`) |
| `wayland-protocols` | ≥ 1.49 | 1.50 in `/opt/hyprland`, 1.47 in apt | **needs `--with-deps`** (apt is too old) |
| `hyprlang` | ≥ 0.6.7 | 0.6.7 | ok, exactly at the minimum |
| `hyprcursor` | ≥ 0.1.7 | 0.1.13 | ok |
| `xkbcommon` | ≥ 1.11.0 | 1.13.1 | ok |
| `wayland-server` | ≥ 1.22.91 | 1.24.0 | ok |
| `libinput` | ≥ 1.29 | 1.31.1 | ok |
| `libcanberra` | any | 0.30 | ok **since this incident** |

So the upgrade command is:

```bash
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps
# builds: hyprutils wayland-protocols aquamarine hyprgraphics hyprland-protocols
```

Do **not** pin the deps to `@v0.14.0` tags here — that pinning is what the incident-2 notes recommend
for rebuilding *0.56.2*, and aquamarine 0.14.0 is below 0.57.0's floor.

`hyprland-protocols` joined `DEPS_DEFAULT` for this: apt ships 0.7.0 and 0.57.0 asks for ≥ 0.8.0, so
the first attempt cleared `libcanberra` and the hypr* versions and then failed at
`CMakeLists.txt:545` on a dependency the script did not know how to build. It needed no new builder —
the project is data-only (protocol XMLs plus a configured `.pc`) but has been CMake-based since
v0.8.0, so `build_hypr_dep` installs it unchanged.

Also note what a `--with-deps=<one name>` suggestion would have cost: each run rebuilds the prefix
from scratch, so building only the dependency that failed leaves the other four out and the next
configure fails on one of them. `explain_configure_failure` therefore prints the union of
`DEPS_DEFAULT` and whatever was unsatisfied, never the failing module alone.

### Why v0.57.0 would not build: one C++26 call

With the dependency chain satisfied, the third attempt reached the compositor itself and stopped at
47%:

```
src/ipc/s1/S1.cpp:148:130: error: 'std::string' has no member named 'subview'
```

`std::string::subview` is C++26, added to libstdc++ in **GCC 16** (`__cpp_lib_string_subview`,
`v = 202506`, `cxxmin = 26` in GCC 16's `version.def`; GCC 15.2 does not define the macro, verified
by compiling for it). Measured facts, all on 2026-10-31:

| | |
| --- | --- |
| uses of `subview` in the whole v0.57.0 tree | **1** — this line |
| distinct compile errors in the failed build | 1 |
| installed C++ header trees | `/usr/include/c++/14`, `/usr/include/c++/15` — no 16 |
| installed `libstdc++6` runtime | **`16-20260322-1ubuntu1`**, exporting `GLIBCXX_3.4.35` |
| `g++-16` in apt | candidate `16-20260322-1ubuntu1`, not installed |
| upstream `main` still calls `subview` | yes — not a bug awaiting a patch release |
| tags after v0.57.0 | none |

So this is a toolchain gap, not a Hyprland bug and not a dependency problem. The runtime half is
already in place: the `libstdc++6` on this machine *is* GCC 16's, which is why nothing else noticed
that the compiler is a major version behind its own runtime library.

The route, which worked — see the next section for the verification:

```bash
sudo apt-get install -y g++-16
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps --cxx g++-16
```

`--cxx` with a newer g++ is explicitly fine — the warning in the script's header is about *older*
ones, whose libstdc++ cannot resolve apt's C++ libraries. It needed one fix to work cleanly:
`derive_cc_for` chose the matching C compiler from a hardcoded list naming g++-13 and g++-14, so
`g++-16` fell through to `cc` (GCC 15) and silently mixed toolchains. It now derives `gcc-N` from
`g++-N` by pattern.

The alternatives, for the record:

- **Wait.** `libstdc++6` is already GCC 16's, so the distro's default `g++` moving to 16 is a matter
  of time, and 0.56.2 keeps running meanwhile.
- **Patch the one line** (`std::string_view(request).substr(i, 2)` is what `subview(i, 2)` does).
  Not done, and not wanted: the script's policy is to work around stdlib gaps with a force-included
  shim rather than editing upstream source — see the `std::ranges::starts_with` compat header — and
  a member function cannot be shimmed that way, so this would be the first real source patch.

### How it was unblocked: g++-16

Installing the newer compiler and pointing the script at it was enough — no source patch, no change
to the dependency set:

```bash
sudo apt-get install -y g++-16 gcc-16
sudo bash scripts/setup-hyprland-alternatives.sh --with-deps --cxx g++-16
```

Checked before spending fifteen minutes on a build, because the two previous attempts were lost to
inference:

```
g++-16 (Ubuntu 16-20260322-1ubuntu1) 16.0.1 20260322 (experimental) [trunk r16-8246-g569ace1fa50]
__cpp_lib_string_subview: defined
std::string_view v = s.subview(1,2);   compiles
```

The run took 585 s end to end — four dependencies plus the compositor, all built with the same
`g++-16` so everything under `/opt/hyprland` links one libstdc++. Verified afterwards:

| Check | Result |
| --- | --- |
| `/opt/hyprland/bin/Hyprland --version` | `Hyprland 0.57.0`, tag `v0.57.0`, commit `0aa6745` |
| `ldd` | 138 libraries, none missing |
| libstdc++ symbols required | up to `GLIBCXX_3.4.35` — the GCC 16 runtime, which was already installed |
| alternatives | `auto`, value `/opt/hyprland/bin/Hyprland` |
| `command -v Hyprland` → version | `/usr/local/bin/Hyprland` → 0.57.0 |
| previous generation | 0.56.2 retired to `/opt/hyprland.previous` by `commit_prefix` |
| leftovers | no `/opt/hyprland.rollback.*`, no `/tmp/hyprland-build-*` |

Note that `g++-16` describes itself as *experimental trunk* — it is what Ubuntu resolute ships
today, and it is the same snapshot the installed `libstdc++6` was built from, so compiler and
runtime now match. `--cxx g++-16` was the manual route at the time; since incident 4 the script
finds that compiler by itself, and once the distro's default `g++` reaches 16 the step-up stops
firing on its own.

### The slave `update-alternatives` could not take over

0.57.0 ran correctly from the first login, but one of the three generic links was not a link at all:

```
$ ls -l /usr/local/bin/hyprpm
-rwxr-xr-x 1 root root 536480 Dec 14  2025 /usr/local/bin/hyprpm     # a real file, not ours
$ ls -l /etc/alternatives/hyprpm
lrwxrwxrwx 1 root root 24 Oct 31 20:17 /etc/alternatives/hyprpm -> /opt/hyprland/bin/hyprpm
```

`update-alternatives` will not replace a path that is a real file it does not own. It said so — once,
on **line 2025** of the registration output:

```
update-alternatives: warning: not replacing /usr/local/bin/hyprpm with a link
```

Afterwards everything *looked* right: `--display Hyprland` listed the slave and
`/etc/alternatives/hyprpm` pointed at the new build. Only `PATH` disagreed, because
`/usr/local/bin` precedes everything and held a file left by the old `/usr/local` source install from
December 2025. So the compositor was 0.57.0 while `hyprpm` — the tool you reach for to rebuild
plugins after an upgrade, which is exactly what an upgrade creates work for — was ten months older.
`Hyprland` and `hyprctl` were unaffected; both were already symlinks the group owned.

Fixed by moving the stale binary aside (kept, not deleted) and re-registering:

```bash
sudo mv /usr/local/bin/hyprpm /usr/local/bin/hyprpm.stale-2025-12-14
sudo bash scripts/setup-hyprland-alternatives.sh --skip-build
```

All three now resolve through the group: `/usr/local/bin/{Hyprland,hyprctl,hyprpm}` →
`/etc/alternatives/*` → `/opt/hyprland/bin/*`.

And the script no longer leaves that to chance. `report_unmanaged_links` checks each managed path
after registering and prints the offending file with the command that fixes it, as the **last** lines
of the run rather than one line in the middle. It is deliberately not fatal: the build and the group
are fine, it is `PATH` that disagrees with them.

### Plugins must be rebuilt per commit, not per release

The first 0.57.0 session rejected a plugin:

```
ERR [PluginSystem] Plugin ~/.local/share/hyprland/plugins/HyprWindowShade.so
    could not be loaded. (API version mismatch)
```

Hyprland's plugin check compares a version ABI string that **begins with the compositor's commit
hash** — here `0aa6745f705f2c4b0a5004eb019ef76e5bbdb426_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6` — so a
plugin built against a different commit of the same release is still rejected. Rebuilding it means
pinning its build to that exact commit and using the same `g++-16`. Nothing else was affected:
`hyprctl plugin list` reports no plugins loaded, and the session is otherwise clean (two monitors up,
no `[ERR]` lines in 1.9 MB of log beyond this one).

### Note: `/opt/hyprland.previous` does not run in place

`commit_prefix` keeps one generation, but the binaries are linked with an absolute
`RUNPATH=/opt/hyprland/lib`, so the retired copy looks for its libraries in the *live* prefix:

```
# with 0.56.2 live and the newer build retired:
error while loading shared libraries: libaquamarine.so.14: cannot open shared object file
# and again after the 0.57.0 upgrade, with the generations the other way round:
$ /opt/hyprland.previous/bin/Hyprland --version
error while loading shared libraries: libaquamarine.so.13: cannot open shared object file
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
