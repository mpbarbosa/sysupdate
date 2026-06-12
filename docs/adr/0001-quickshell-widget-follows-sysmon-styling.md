# QuickShell Widget follows sysmon's styling and architecture, not web/DESIGN.md's Cyber-Terminal HUD

**Status:** accepted

The sysupdate QuickShell Widget sits on the same desktop as the `sysmon` sibling widget
(`~/Documents/GitHub/sysmon`). `web/DESIGN.md` (the Web Dashboard's design doc) was imported as a
shared design-language reference for sysupdate's front-ends, including a neon "Cyber-Terminal
HUD" palette (`#00f3ff`/`#ffabf3`/`#39ff14` on `#05080a`). We decided the QuickShell Widget
instead adopts `sysmon`'s established Catppuccin Mocha palette (`#1e1e2e`/`#cdd6f4`/`#89b4fa`) and
architecture (compositor detection, `Process` + JSON polling, interactive-terminal-launch
pattern), because visual cohesion between two widgets that sit side-by-side on the same desktop
outweighs matching the Web Dashboard's browser-app aesthetic. `web/DESIGN.md` remains a reference
for the QuickShell Widget's information architecture and data shapes only, not its visual
styling.

**Consequences:** the two sysupdate front-end experiments (Web Dashboard and QuickShell Widget)
will look visually unrelated to each other — "sysupdate" does not have one consistent visual
identity across front-ends.
