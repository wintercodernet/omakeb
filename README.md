# omakeb

Turns a minimal Debian 13 install into a Hyprland tiling desktop, in one command.

omakeb is inspired by [Omarchy](https://omarchy.org). From a practical
standpoint it gives you a similar setup — Hyprland with a bar, a launcher,
notifications, a themed terminal, a keyboard-driven menu and opinionated
keybindings — built from the same kind of common core components. It shares no
code with Omarchy: it is an independent, Debian-native implementation written
from scratch. What it borrows are ideas, not files.

It is a collection of shell scripts and plain-text config files — not a
distribution, package or daemon. It targets Debian 13 (trixie) stable and wants
the machine to itself: start from a netinst with no desktop selected, and omakeb
installs and owns the whole graphical stack. Everything comes from Debian
`main`, except the Hyprland stack, which comes from narrowly pinned
`trixie-backports`.

The desktop is Hyprland, Waybar, fuzzel, mako and kitty, wired together. Optional
software comes from vendors' official apt repositories rather than Flatpak.
This is early software: it has run end to end on VMs and real hardware, but
that is still a small sample.

## Installing

Start from a fresh **Debian 13 netinst** with **no desktop environment**
selected in tasksel, and **leave the root password blank** so your user lands in
the `sudo` group. You need a network connection and at least 4 GB free on `/usr`.

```sh
sudo apt install -y git
git clone https://github.com/wintercodernet/omakeb.git ~/.local/share/omakeb
cd ~/.local/share/omakeb
./install.sh
sudo reboot
```

It asks for your password once, then runs unattended. After the reboot, log in
at the greetd prompt and you land in Hyprland. Re-running `./install.sh` is safe
and is the supported repair for anything that looks half-configured.

If the screen stays black after reboot, switch to a console with `Ctrl+Alt+F2`
and run `sudo systemctl disable greetd`; nothing else is affected.

## How it works

**Keybindings.** `SUPER+SPACE` opens the menu, `SUPER+K` lists every binding
(generated from the running compositor, so it is always accurate),
`SUPER+RETURN` opens a terminal, `SUPER+W` closes a window, `SUPER+1…9` switches
workspace and `SUPER+ESCAPE` locks, suspends or powers off.

**The menu.** A searchable tree for launching apps, switching themes, screen
capture, toggles, installing software, updating and power. It is defined as
data in `menu/`.

**Commands.** The `omakeb-*` scripts in `bin/` are the public API. Keybindings
and the menu just call them, and so can you — see
[`docs/commands.md`](docs/commands.md).

**Themes.** `omakeb-theme-set <name>` renders a colour palette through the
templates in `templates/` and reloads every themed app in place. Catppuccin,
Gruvbox and Tokyo Night ship. `omakeb-theme-install <git-url|path>` imports a
palette from an Omarchy-compatible `colors.toml` — only the palette, not
Omarchy's theme artwork or shell.

**Optional software.** `omakeb-install-app` (or the menu) installs curated apps
such as VS Code, Claude Code, Docker, Spotify, 1Password and Steam, each
declaring which CPU architectures it supports.

**Your settings.** `~/.config/omakeb/apps.conf` chooses which programs the keys
open, and `~/.config/omakeb/bindings.conf` holds your own keybindings. Both are
seeded once and never overwritten by an update.

**Updating.** `omakeb-update` pulls the repository, applies migrations, re-runs
the install steps to bring the machine in line with the checkout, and upgrades
Debian's packages. On a current machine it changes nothing.

## More

- [`docs/README.md`](docs/README.md) — how it is built and why
- [`docs/decisions.md`](docs/decisions.md) — design decisions and contracts
- [`docs/commands.md`](docs/commands.md) — every `omakeb-*` command

## License

MIT — see [`LICENSE`](LICENSE). The vendored palette test fixtures in
`test/fixtures/palettes/` keep their upstream MIT notices in
[`LICENSE.upstream`](test/fixtures/palettes/LICENSE.upstream).
