# omakeb

Turns a minimal Debian 13 install into a Hyprland tiling desktop.

It is a collection of shell scripts and config files — not a distribution, not a
package, not a daemon. You run one command on a fresh Debian box and end up with
a tiling window manager, a bar, a menu, themes, sane keybindings, and a way to
install the software people actually want.

Where Omarchy does this for Arch and Omakub did it for Ubuntu+GNOME, omakeb does
it for Debian. It copies ideas from Omarchy, never code.

---

## The shape of it

Five things, roughly in the order they matter:

**1. A desktop.** Hyprland, waybar, fuzzel, mako, kitty — installed, configured
and wired together, with 141 keybindings and a set of window rules. This is the
part you look at.

**2. A menu.** One keypress (`SUPER+SPACE`) opens a tree of 89 entries covering
everything below: launching apps, changing themes, capture, toggles, system
power. Defined as *data* in `menu/menu.jsonc`, walked by a script that renders
each level through fuzzel.

**3. Commands.** 42 small scripts in `bin/`, each doing one thing. They are the
project's public API — the keybindings and the menu both just call them, and so
can you. See [commands.md](commands.md).

**4. Optional software.** Thirteen curated installers, each declaring which
architectures it actually supports:

| | |
|---|---|
| editors and agents | VS Code, Claude Code, OpenCode, OpenAI Codex, GitHub Copilot CLI |
| runtimes | OpenJDK (Debian's `default-jdk`), .NET SDK |
| desktop | Docker, Spotify, 1Password, Edge, Steam, LocalSend |

Plus a raw picker over the whole Debian archive.

**5. Themes.** Nine app configs generated from a palette of colours, so one
command retints the entire desktop. Palettes from the Omarchy community can be
imported.

---

## What happens when you install it

`install.sh` runs ten steps in order. Each is idempotent — re-running the
installer is the supported way to repair or update a machine, and a second run
must rewrite nothing.

| step | what it does |
|---|---|
| `preflight` | Refuses to run on the wrong thing: not Debian 13, no sudo, no network, too little disk. Explains the fix rather than just failing. |
| `05-migrations` | Applies any pending `migrations/<epoch>.sh` — fixes for machines built by an older omakeb. On a fresh install there is nothing to fix, so it records them as applied instead of replaying them. |
| `10-sources` | Enables `trixie-backports` and **pins it narrowly** — the Hyprland stack comes from there, everything else must not. Then verifies every package resolves for this machine's architecture. |
| `20-base` | Terminal environment: shell tools, neovim, tmux, starship, git. |
| `30-desktop` | The graphical stack: Hyprland, waybar, fuzzel, mako, kitty, firefox-esr, pipewire, portals, and fonts with enough coverage not to draw tofu. |
| `40-shell` | Bash configuration, aliases, and symlinks every `bin/` command onto your `PATH`. |
| `50-fonts` | Nerd Font symbols, so icons render. |
| `60-config` | Writes `~/.config/*` for Hyprland, waybar, mako, fuzzel, kitty, hypridle, hyprlock, hyprpaper. Seeds your override files once. |
| `70-theme` | Renders the default palette through the templates. |
| `80-services` | greetd + tuigreet, launching Hyprland through uwsm as a proper systemd user session. |

Reboot, log in at the greeter, and you are in Hyprland.

---

## Keeping it up to date

```sh
omakeb-update
```

Or `SUPER+SPACE` → Update → omakeb.

It pulls the checkout, applies pending migrations, **re-runs the install steps
above**, then upgrades Debian's own packages and reports on what it found.

Re-running the install steps is the point. Update has no separate idea of what a
configured machine looks like — it converges on the same target `install.sh`
does, using the same code. So adding a package to `packages/*.list`, changing a
template, adding a command to `bin/` or editing anything in `default/` reaches
every existing machine with no further work. On a machine that is already
current it rewrites nothing and says so.

A migration is only needed for what converging cannot express — *removing* or
*renaming* something an older omakeb created. See
[migrations/README.md](../migrations/README.md).

| flag | |
|---|---|
| `--no-pull` | use the checkout as it is on disk |
| `--no-converge` | skip re-running the install steps (migrations still run) |
| `--no-upgrade` | skip `apt upgrade`; omakeb's own changes still apply |

Update deliberately does **not** run preflight, which refuses anything that is
not Debian 13. A machine that has moved to the next release is exactly the one
whose owner needs to be told something useful rather than shown `exit 1`, so
update checks the release itself and reports a stale backports suite instead.

---

## What is running in a session

Worth knowing, because it explains where to look when something misbehaves.

**systemd owns five daemons** — waybar, mako, hyprpaper, hypridle, hyprsunset.
Debian ships user units for all of them and enables them at package install, and
uwsm reaches `graphical-session.target`, so systemd starts them. omakeb must
*not* start its own copies; that produced a memorable bug where two bars stacked
on top of each other.

**Hyprland's `exec-once` owns the rest** — the graphics capability probe, the
polkit agent, the two clipboard-history watchers, and re-applying any toggles you
left set. These have no packaged units, and go through `omakeb-daemon` so a
compositor restart cannot duplicate them.

Toggles that stop a systemd-managed daemon use `systemctl --user stop`, never
`pkill` — killing one looks like a failure to systemd, which restarts it
immediately.

---

## Who owns which file

The rule that keeps updates from destroying your work:

- **omakeb owns `default/` and everything it generates into `~/.config/`.**
  Regenerated on every update. Do not edit these; your changes will vanish.
- **You own `~/.config/omakeb/`.** Seeded once at install and never touched
  again. This is where your keybindings, your app choices and your Hyprland
  overrides live.

Hyprland's config sources your overrides *last*, so anything you put there wins.
Rebinding a key omakeb already binds does not replace it — Hyprland runs both
dispatchers — so `unbind` first. `~/.config/omakeb/bindings.conf` has worked
examples.

Apps without an include mechanism (waybar, mako, fuzzel, kitty) are *generated*
rather than sourced, which is why their colours come from the theme system.

---

## The three software tiers

Not everything can come from Debian, and the difference matters:

| tier | source | examples | notes |
|---|---|---|---|
| **1** | trixie + backports | everything in the base install; Steam | Debian-maintained, security updates, no extra trust |
| **2** | official upstream apt repos | VS Code, Docker, Spotify, 1Password, Edge | opt-in only, never in the base; each pins its own signing key |
| **3** | direct download | Nerd Font symbols | **no security updates from anyone** — kept deliberately tiny |

The base install is tier 1 only, with one deliberate exception: the icon font,
which is a TTF with no executable surface.

**Availability is per-app *and* per-architecture.** A third-party repo genuinely
may not exist for your machine — Microsoft publishes an arm64 index for Edge
containing zero packages — so each app declares what upstream actually ships and
omakeb refuses cleanly rather than leaving a broken apt source behind.

Flatpak is deliberately not used; see D10 in [`decisions.md`](decisions.md) for
the reasoning.

---

## NVIDIA

**Untested.** Every other feature in omakeb was verified on a real machine.
This one has never been run on the hardware it targets — there is no NVIDIA
card in the project. Treat it as a well-researched draft, not as something that
is known to work, and read the recovery notes before you reboot.

Debian's netinst leaves you on `nouveau`, which drives a Hyprland session but
slowly. The proprietary driver is in `non-free`, and one thing stands between
installing it and a working Wayland session: **no Debian nvidia package ships
anything in `/etc/modprobe.d`**, so DRM kernel modesetting is off, and a
compositor with no modesetting is a black screen.

`omakeb-hw-nvidia` is the whole feature. It is opt-in, the installer never
touches it, and it is reversible.

```sh
omakeb-hw-nvidia detect    # what is in this machine; changes nothing
omakeb-hw-nvidia show      # the exact files enable would write; changes nothing
omakeb-hw-nvidia enable    # summarises everything, then asks
omakeb-hw-nvidia revert    # undoes all of it
```

`enable` asks **`nvidia-detect`** — Debian's own tool — which driver this card
needs, rather than carrying a map from PCI id to driver generation that would
rot and would get legacy cards wrong. If it cannot read an answer, it stops
instead of guessing.

It then enables `contrib` and `non-free` (additively, through the same
mechanism Steam uses), installs the recommended driver plus the kernel headers
DKMS needs, writes `options nvidia_drm modeset=1 fbdev=1`, adds the modules to
the initramfs for early KMS, and sets the two environment variables Hyprland's
wiki currently recommends — `LIBVA_DRIVER_NAME` and `__GLX_VENDOR_LIBRARY_NAME`
— and no others. `GBM_BACKEND=nvidia-drm`, which half the tutorials still tell
you to set, is deliberately absent.

**It refuses, without changing anything, in three cases:**

| refusal | why |
|---|---|
| no NVIDIA card | nothing to do |
| **Secure Boot enabled** | DKMS modules are unsigned and will not load. The install would succeed, report nothing wrong, and the machine would come up black. MOK enrolment is the real fix; omakeb will not do it for you. |
| **hybrid / Optimus** | An Intel or AMD display controller alongside the NVIDIA one needs PRIME render offload — different packages, different config, per-app variables. omakeb does not implement it, and half-doing it bricks the session. |

The Hyprland environment goes into `~/.config/hypr/nvidia.conf`, sourced from a
four-line marked block appended to your own `~/.config/omakeb/hyprland.conf`.
It cannot be sourced from omakeb's own config: hyprlang has no conditionals and
treats a missing `source =` target as an error, so an unconditional line would
break the config on every machine *without* an NVIDIA card. `revert` removes
exactly the marked block and leaves the rest of your file alone.

Early KMS (the initramfs part) removes boot flicker but **can break resume from
hibernation** on some machines. `enable --no-early-kms` skips it; everything
else works the same.

### If it goes wrong

```
Ctrl+Alt+F2 gives a console:   omakeb-hw-nvidia revert --yes && sudo reboot
no console either:             at the GRUB menu press `e`, add `nomodeset` to
                               the `linux` line, boot with Ctrl+X, then revert
```

`revert` removes the modprobe file, the initramfs block, the Hyprland env and
its source line, rebuilds the initramfs, and purges the driver — including the
DKMS package apt pulled in, which would otherwise keep rebuilding a module
after a "revert". It leaves `contrib` and `non-free` enabled, because other
software may have arrived through them since.

---

## Themes

A theme is a **palette** — around 26 colours in a `colors.toml` — and nothing
else. `omakeb-theme-set <name>` renders nine templates from it and reloads each
app in place:

```
waybar.css  mako.ini  fuzzel.ini  kitty.conf  hyprland-colors.conf
hyprlock.conf  btop.theme  gtk.css  starship.toml
```

(A tenth, `starship-palette.toml`, is not a config of its own: it is the
palette appended to the chosen prompt layout, below.)

Adding a theme is one `colors.toml`. Adding a *themed app* is one template.
Neither requires touching the other.

The shell prompt is starship, and its **layout** is a separate choice from the
theme: `omakeb-prompt-set <layout>` (or `SUPER+SPACE` → Style → Prompt) picks
one of ours, one of starship's built-in presets, or a file of your own in
`~/.config/omakeb/prompts/<name>.toml`. A new install gets `darkgreen`, the
two-line bracketed shape of oh-my-posh's darkblood in the theme's green;
`omakeb` is the compact single-line one machines installed earlier keep. The theme's colours are appended to
whichever layout you choose as a starship palette named `omakeb` (`accent`,
`muted`, `warning`, `urgent`, `ok`, `info`, `dim`, `foreground`), so a layout
that sets `palette = "omakeb"` keeps following the theme. Presets written in
ANSI colour names follow it through the terminal; the few that hardcode their
own colours do not, and `omakeb-prompt-list --long` says which.

`omakeb-theme-install <git-url>` imports palettes from the Omarchy community
ecosystem — the palette only. Theme repos are arbitrary third-party content, so
anything executable is refused, symlinks are skipped, and nothing is cached.

---

## Where things live

```
boot.sh              curl|bash entry point
install.sh           orchestrator
install/             the ten steps above
lib/                 shared shell helpers, sourced by everything
bin/                 42 commands — the public API
default/             our config; regenerated on update
config/              seed files copied once into ~/.config/omakeb
packages/            the 82 base packages, as plain lists
apps/                optional software, one file each
themes/              palettes
templates/           one per themed app
prompts/             shipped starship prompt layouts
menu/menu.jsonc      the whole menu tree, as data
test/                see below
docs/                you are here
```

---

## Testing

Three tiers, fastest first. Details in `test/vm/README.md`.

```sh
./test/run-all.sh              # static — runs on macOS, seconds
./test/vm/nspawn-install.sh    # container install on Debian, <3 min on arm64
./install.sh                   # the real thing; snapshot the VM first
```

The static checks are worth knowing about because several exist to catch bugs
that already happened: keybinding syntax and duplicate chords, architecture
assumptions, commands referenced but never written, autostart entries that
duplicate a systemd unit, web-CSS selectors GTK cannot parse, and every palette
rendering every template with no token left unresolved.

`test/lint-nvidia.sh` is there for a different reason: the NVIDIA feature has no
hardware behind it, so the parts that *can* be checked without a card are
checked hard — the generated hyprlang file against hyprlang's `#` truncation,
the two environment variables against being "helpfully" extended, the
`nvidia-detect` parser against three real output shapes, and the editor that
appends to your own `hyprland.conf` against a byte-for-byte round trip.

The container tier asserts the apt pin works **in both directions**, that a
second install rewrites nothing, and — the most valuable single check —
`Hyprland --verify-config`, which parses the entire config including all 141
bindings without needing a GPU.

---

## Design decisions

[`decisions.md`](decisions.md) records each one, with the reasoning, along with
the contracts scripts rely on. The ones that shape everything else:

- **D1** — waybar + fuzzel + mako, not Omarchy's Quickshell. Lower ceiling,
  far less risk, and everything is in Debian.
- **D3** — we assume a bare netinst and own the whole graphical stack.
- **D9** — never allowlist architectures; ask apt. Debian builds the Hyprland
  stack on eight of its nine release architectures.
- **D11** — our own theme format, deliberately palette-compatible with Omarchy's.
