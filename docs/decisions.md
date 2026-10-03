# Design decisions and contracts

Comments throughout the code cite these by number — `(D9)`, `(C3)` — so the
reason for a choice can be found without repeating it everywhere. The numbers
are stable; gaps are decisions that were folded into others.

## Decisions

**D1 — Shell stack: Waybar + fuzzel + mako.** Not a QML shell. Everything is in
Debian main, configuration is plain text, and the risk is low. The cost is a
polish ceiling below a purpose-built shell. The menu is data and the theme is
tokens, so the renderer can be replaced later without touching either.

**D2 — Independent of Omarchy, inspired by it.** Our own repository and scripts,
Debian-native from the start, with no git relationship to Omarchy. We take
*ideas* — the menu schema, theme tokens, `bin/` as the public API, `# summary=`
metadata, epoch-named migrations — not code.

**D3 — Base system: minimal netinst, no desktop task.** omakeb installs and owns
the entire graphical stack. No coexistence with GNOME or another desktop; the
preflight warns if one is present rather than trying to cope.

**D4 — Three package tiers.** Tier 1 is Debian trixie plus the pinned
backports, and is all the base install uses. Tier 2 is vendors' official apt
repositories, opt-in. Tier 3 is a download or a build into `/opt` or
`~/.local`, opt-in. Nobody ships security updates for tier 3, so it is kept
short, its versions are recorded, and `omakeb-update` reports staleness.

**D5 — Name: `omakeb`.** Command prefix `omakeb-`, installed to
`~/.local/share/omakeb`, state in `~/.local/state/omakeb`, user config in
`~/.config/omakeb`.

**D6 — Default terminal: kitty.** It is in Debian main and installs with apt;
the alternatives would have needed building from source.

**D7 — Editor: neovim from trixie main.** That is 0.10.4, so LazyVim and
anything tracking nvim HEAD will not work. A newer neovim belongs in `apps/`,
not in the base.

**D8 — One non-Debian item in the base.** Nerd Font symbols are not packaged
for trixie, so a single font file is downloaded into `~/.local/share/fonts`.
A font has no executable surface and no architecture question.

**D9 — Architecture-agnostic: ask apt, never an allowlist.** No script names a
CPU to decide whether it can run. Debian 13 builds the full stack on eight of
its nine release architectures; on the ninth (mips64el) the preflight lists
everything that is missing instead of dying on the first package.

**D10 — Optional software is apt, not Flatpak.** Third-party apps come from
their vendors' official apt repositories. For the apps in question Flatpak
offered nothing extra and cost a second package universe, runtimes, update
path and permissions model. Availability is therefore per-app *and*
per-architecture, and each app declares what its vendor actually ships.

**D11 — Themes: our own format, palette-compatible, palette-only importer.**
The omakeb theme format is deliberately key-compatible with Omarchy's
`colors.toml`, and `omakeb-theme-install` imports **only the palette**, with a
fallback cascade so older and sparser palettes still render. Per-app theme
files are ignored, and no theme artwork is imported or shipped. This is not
"Omarchy theme support" and is not described that way.

**D12 — Reading upstream is fine; copying is not.** Reading another project's
source to understand a documented behaviour is ordinary engineering. Copying
code into this repository is not done — for architectural independence, not
licensing.

**D13 — The base install is Debian stable; newness is opt-in, per app.**
Everything in the base comes from trixie main except the Hyprland stack (from
narrowly pinned `trixie-backports`, because it is not in main at all) and the
font from D8. Anything newer is an `apps/` entry the user asks for.

**D14 — npm-based tools install per user, never with `sudo npm`.** Agentic CLIs
install with `NPM_CONFIG_PREFIX=$HOME/.local`, so no package install script
runs as root and nothing lands in `/usr/local` where dpkg cannot track it.

**D15 — Session daemons: one list, resolved at run time.** waybar, mako,
hyprpaper, hypridle and hyprsunset are declared once in
`default/session-daemons.tsv` and started by `bin/omakeb-session-daemons`,
which decides per session whether systemd already runs them, so a daemon is
never started twice.

## Contracts

Conventions that independent scripts rely on. Changing one means changing
every consumer.

**C1 — Script conventions.** Every file in `bin/` is executable,
`#!/bin/bash`, `set -euo pipefail`, and carries `# omakeb:summary=` (and
`# omakeb:args=` if it takes arguments) directly under the shebang.
`docs/commands.md` is generated from those lines.

**C2 — `~/.config/omakeb/apps.conf`.** Plain `KEY=value` lines (`TERMINAL`,
`BROWSER`, `BROWSER_PRIVATE_FLAG`, `EDITOR_CMD`, `FILE_MANAGER`), seeded once
and never overwritten. The `omakeb-launch-*` wrappers read it at run time, so a
change takes effect with no reload; they tolerate it being absent or partial.

**C3 — Toggle state.** A toggle is ON when `$OMAKEB_STATE/toggles/<name>`
exists; files have no contents, so `ls` shows the state. Names are chosen so
that *absent* means the default (`bar-hidden`, `dnd`, `no-gaps`,
`transparency`, `idle-inhibited`, `nightlight`). Captured values are stashed
outside `toggles/`. `omakeb-toggle-enabled <name>` exits 0 when on.

**C4 — Menu.** `menu/menu.jsonc` uses Omarchy's menu schema: dotted ids imply
hierarchy, each row has `icon`, `label` and `action`, plus optional `when`,
`checked`, `disabled` and `aliases`. User additions in
`~/.config/omakeb/menu.jsonc` merge over it.

**C5 — Notifications.** User-visible feedback goes through `notify-send`, never
stdout, because these scripts run from keybindings with no terminal. A stable
synchronous hint per topic makes repeated volume or brightness presses replace
the previous notification instead of stacking.
