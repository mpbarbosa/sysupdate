# Feasibility: two kitty installs switchable via `update-alternatives`

**Question:** Can we keep two kitty versions configured with `update-alternatives` — one from **apt**, one from the **upstream repo/installer** — and switch between them?

**Verdict:** ✅ **Feasible** — but *not* by managing `/usr/bin/kitty`, and with real caveats. For a single-user machine it is also heavier than necessary; a plain symlink/PATH approach may be the better trade.

**Assessed:** 2026-08-02 (assessment only — no changes made; setup needs `sudo`).

---

## Current state (measured)

| Install | Path | Version | Ownership |
| --- | --- | --- | --- |
| **apt** | `/usr/bin/kitty` + `/usr/bin/kitten` | **0.45.0** | real files, **dpkg-owned** (pkg `kitty 0.45.0-1build1`) |
| **upstream** | `~/.local/kitty.app/bin/{kitty,kitten}` (+ `~/.local/bin/kitty` symlink) | **0.48.2** | user files |

- **Active now:** apt 0.45.0 — PATH order is `/usr/local/bin` → `/usr/bin` → `~/.local/bin` → `~/.local/kitty.app/bin`, so `/usr/bin/kitty` (apt) wins.
- No `kitty` alternatives group exists; **`/usr/local/bin/kitty` is free**.
- The apt package registers kitty only in the **`x-terminal-emulator`** group (priority 20) — *not* a per-kitty alternative. `/usr/bin/kitty` remains a plain dpkg-owned file.

## The blocker, and the way around it

`update-alternatives` needs its *link* path to be a symlink it manages. `/usr/bin/kitty` is a **real file owned by the apt package**, so it can't be that link — alternatives would fight dpkg (every `apt upgrade`/reinstall clobbers it).

The workable design puts the **generic link in `/usr/local/bin`** (unowned, and it precedes `/usr/bin` in PATH so it wins), with **`kitty` as master and `kitten` as slave** (the two binaries are version-coupled — never mix apt-kitty with upstream-kitten):

```bash
sudo update-alternatives --install /usr/local/bin/kitty kitty /usr/bin/kitty 45 \
    --slave  /usr/local/bin/kitten kitten /usr/bin/kitten
sudo update-alternatives --install /usr/local/bin/kitty kitty /opt/kitty.app/bin/kitty 48 \
    --slave  /usr/local/bin/kitten kitten /opt/kitty.app/bin/kitten
sudo update-alternatives --config kitty      # interactively switch
# or pin one:  sudo update-alternatives --set kitty /opt/kitty.app/bin/kitty
```

## Caveats (these decide whether it's worth it)

1. **Move the upstream install to `/opt`.** A system-wide alternative (`/etc/alternatives`, root) pointing into `~/.local` (one user's home) works technically but is fragile: single-user only, dangles if the home isn't mounted, permission oddities. For a proper system alternative, relocate upstream to `/opt/kitty.app`. (If you want a *per-user* choice instead, don't use system `update-alternatives` at all — see Recommendation.)
2. **Group kitty + kitten (master/slave).** `kitten` and `kitty` are released together and are version-locked; switching them independently will break.
3. **Manual cleanup on removal.** Because the alternative is registered by hand (not by the package), `apt remove kitty` will **not** remove the `/usr/bin/kitty` entry — it would dangle. Remove it yourself: `sudo update-alternatives --remove kitty /usr/bin/kitty`. (An `apt upgrade` of kitty is fine — the real file updates in place.)
4. **Desktop launcher + terminfo.** Point the `.desktop` `Exec=` at `/usr/local/bin/kitty` so the GUI launcher follows the active alternative. Both installs ship the `xterm-kitty` terminfo, so terminal capabilities are fine either way.
5. **sysupdate snippet mismatch (important here).** `scripts/upgrade_snippets/kitty.yaml` is `source: github` (tracks upstream `kovidgoyal/kitty`) but reads `kitty --version` — which under alternatives is *whichever is active*. If apt is active while the snippet tracks upstream, it reports/installs against the wrong channel (same class as the aws-cli/fastfetch channel issues). Coexistence makes this worse; you'd want the snippet to match the active channel, or to split it into two snippets (apt kitty via apt, upstream kitty via github).

## Recommendation

- **Use `update-alternatives`** if you want a root-managed, prioritized, `--config`-switchable, **system-wide** selection (or multi-user, or to integrate with `x-terminal-emulator`). Feasible via the `/usr/local/bin` link + kitty/kitten group + upstream in `/opt`.
- **Skip it** if this is just you flipping between two kitties: a single symlink in `~/.local/bin` (or `/usr/local/bin`) to the one you want, or PATH ordering, achieves the same with **no root, no dpkg friction, and none of the manual-cleanup/home-path caveats**.
- Either way, reconcile the `kitty` snippet's channel with whichever install you consider "the one to update."

## Verification (after setting it up)

```bash
update-alternatives --display kitty          # shows both links + which is active
command -v kitty                             # -> /usr/local/bin/kitty (the generic link)
kitty --version                              # the active version
sudo update-alternatives --config kitty      # switch, then re-check `kitty --version`
```
