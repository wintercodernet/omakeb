# Command reference

Every omakeb command lives in `bin/` and is on your `PATH`. This file is
generated from the `# omakeb:summary=` line in each script — run
`docs/regenerate-commands.sh` after adding one.

Commands marked *(internal)* are called by the session or the menu rather than
typed by hand.

## Launching things

- **`omakeb-launch-browser`** `[--private] [url...]` — Open the web browser, optionally in a private window.
- **`omakeb-launch-editor`** `[file...]` — Open the editor in a terminal window.
- **`omakeb-launch-filemanager`** `[path]` — Open the graphical file manager.
- **`omakeb-launch-once`** `<command> [args...]` — Focus an app's existing window, or launch it if it has none.
- **`omakeb-launch-terminal`** `[tmux]` — Open a terminal, optionally running tmux.
- **`omakeb-launch-tui`** `<command> [args...]` — Run a terminal program in a floating window.
- **`omakeb-launch-webapp`** `<url> [class]` — Open a URL as a standalone application window.
- **`omakeb-system-lid`** `close|open` — React to the laptop lid opening or closing.
- **`omakeb-system-lock`** — Lock the session.

## Menus and pickers

- **`omakeb-menu`** `[route]` — Open the omakeb menu.
- **`omakeb-menu-clipboard`** — Pick an entry from clipboard history and put it back on the clipboard.
- **`omakeb-menu-emoji`** — Pick an emoji, copy it, and type it into the focused window.
- **`omakeb-menu-keybindings`** — Show every active keybinding in a searchable list.

## Themes

- **`omakeb-prompt-list`** `[--long | --annotate]` — List the available shell prompt layouts.
- **`omakeb-prompt-set`** `[layout]` — Choose the shell prompt's layout; its colours still follow the theme.
- **`omakeb-theme-install`** `<git-url|path> [name]` — Install a theme from a git URL or a local directory.
- **`omakeb-theme-list`** `[--long]` — List the installed themes.
- **`omakeb-theme-set`** `[--no-reload] [theme]` — Switch the desktop theme and reload every themed app in place.

## Optional software

- **`omakeb-install-app`** `[list|install [app]|remove [app]|upgrade [app]] (no app name opens a picker; upgrade with none checks every tier-3 app)` — Install or remove optional software from apps/.

## Toggles

- **`omakeb-nightlight-apply`** — Apply the current night light state to the display.
- **`omakeb-toggle-bar`** — Show or hide the top bar.
- **`omakeb-toggle-dnd`** — Toggle do not disturb.
- **`omakeb-toggle-enabled`** `<name>` — Exit 0 if the named toggle is currently on.
- **`omakeb-toggle-gaps`** — Toggle window gaps, borders and rounding for a full-bleed layout.
- **`omakeb-toggle-idle`** — Toggle locking and screen blanking on idle.
- **`omakeb-toggle-nightlight`** — Toggle the warm night light filter.
- **`omakeb-toggle-transparency`** — Toggle window transparency.

## Capture and clipboard

- **`omakeb-capture-color`** — Pick a colour from the screen and copy it to the clipboard.
- **`omakeb-capture-screenrecording`** `[region] [audio]` — Start a screen recording, or stop the one in progress.
- **`omakeb-capture-screenshot`** `<region|window|screen> [edit]` — Take a screenshot of a region, the focused window or the screen.
- **`omakeb-clipboard`** `<copy|paste|cut>` — Copy, paste or cut in the focused window, terminals included.

## Hardware controls

- **`omakeb-audio-volume`** `<up|down|mute|mic-mute> [step]` — Raise, lower or mute the volume.
- **`omakeb-brightness`** `<up|down|max|min> [step]` — Raise or lower the screen backlight.
- **`omakeb-hw-audio`** `[status|fix [--yes]]` — Find audio that is playing but inaudible, and optionally fix it.
- **`omakeb-hw-nvidia`** `detect|show|enable [--yes] [--no-early-kms]|revert [--yes] [--keep-packages]` — Set up, inspect or undo NVIDIA proprietary driver support.

## Session internals

- **`omakeb-daemon`** `<command> [args...]` — Start a session daemon, but only if that exact command is not already running.
- **`omakeb-gl-fallback`** — Fall back to software OpenGL when the GPU cannot drive GL apps.
- **`omakeb-hyprland-window-pop`** — Pop the active window out: float it, pin it and centre it.
- **`omakeb-monitor-apply`** — Put every display on its best mode, and scale a display above 4K by 2.
- **`omakeb-monitor-watch`** — Repair the bar after a display hotplug leaves duplicate copies stacked at the top. (internal)
- **`omakeb-session-daemons`** — Start the session daemons that systemd did not start.
- **`omakeb-update`** `[--no-pull] [--no-converge] [--no-upgrade]` — Pull the latest omakeb, apply migrations, and reconverge this machine.

