#!/bin/bash
# Render our config into ~/.config, and seed the user's override files once.
#
# The ownership rule: omakeb owns default/, the user
# owns ~/.config/omakeb/, and an update only ever rewrites our half.
#
#   * Hyprland has `source =`, so ~/.config/hypr/hyprland.conf is a thin entry
#     point that points back into the checkout. Updating Hyprland's defaults
#     means editing default/hypr/*.conf; this file is regenerated only because
#     it carries absolute paths.
#   * waybar, mako, fuzzel and kitty have no include mechanism, so their configs
#     are written out whole. write_file only touches a file whose content would
#     change, which is what keeps a second install run silent.
#   * Anything a COLOUR appears in is not written here at all. It is rendered
#     from templates/*.tpl by install/70-theme.sh, the step immediately after
#     this one, and re-rendered by omakeb-theme-set on every theme change. This
#     step keeps only the structure no theme can alter.
#   * The user's override files are seeded with run_once, never with write_file.
#     They are the one category of file we must not fix up on a re-run, because
#     "unchanged" and "the user deleted everything on purpose" look identical.
# shellcheck shell=bash

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

# --- user override files, seeded exactly once ---------------------------------

seed_from_repo() {
  local src=$1 dest=$2
  if [[ -e $dest ]]; then
    log_skip "kept existing $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  chmod 0644 "$dest"
  log_ok "seeded $dest"
}

# C2: read at run time by the omakeb-launch-* wrappers, so editing it takes
# effect on the next keypress with no reload.
run_once seed-apps-conf \
  seed_from_repo "$OMAKEB_PATH/config/apps.conf" "$OMAKEB_CONFIG/apps.conf"

run_once seed-bindings-conf \
  seed_from_repo "$OMAKEB_PATH/config/bindings.conf" "$OMAKEB_CONFIG/bindings.conf"

# hyprland.conf.in sources this file unconditionally, and hyprlang treats a
# missing `source =` target as a config error, so it has to exist even when it
# is empty. There is no repo seed for it — the whole file is explanation.
seed_user_hyprland_conf() {
  local dest="$OMAKEB_CONFIG/hyprland.conf"
  if [[ -e $dest ]]; then
    log_skip "kept existing $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<'USERHYPR'
# Your own Hyprland settings. Seeded once by omakeb; never overwritten.
#
# This file is sourced LAST, after every omakeb default, so anything here wins
# for ordinary options. Keybindings are the exception — Hyprland runs every
# dispatcher bound to a chord, so redefining one adds to it rather than
# replacing it. Put bindings in bindings.conf next door, and `unbind` first.
#
# hyprlang truncates a line at an unescaped '#'. Write a literal hash as '##'.
# Colours are rgb()/rgba(), so this rarely comes up.

# Keyboard layout:
#
#   input {
#       kb_layout = us,no
#       kb_options = grp:alt_shift_toggle,caps:escape
#   }

# Monitors — `hyprctl monitors` prints the names:
#
#   monitor = eDP-1, preferred, 0x0, 1.5
#   monitor = DP-1, 2560x1440@144, 2560x0, 1

# Turn blur off if the compositor feels slow (a VM, or old integrated graphics):
#
#   decoration:blur:enabled = false

# Start something with the session:
#
#   exec-once = nm-applet --indicator
USERHYPR
  chmod 0644 "$dest"
  log_ok "seeded $dest"
}

run_once seed-hyprland-conf seed_user_hyprland_conf

# --- Hyprland entry point -----------------------------------------------------
#
# Substituted in bash rather than with sed: a path is arbitrary text, and every
# sed delimiter is a character a path is allowed to contain.
hyprland_conf=$(cat "$OMAKEB_PATH/default/hypr/hyprland.conf.in")
hyprland_conf=${hyprland_conf//@OMAKEB_PATH@/$OMAKEB_PATH}
hyprland_conf=${hyprland_conf//@OMAKEB_CONFIG@/$OMAKEB_CONFIG}
hyprland_conf=${hyprland_conf//@CONFIG_HOME@/$config_home}
printf '%s\n' "$hyprland_conf" | write_file "$config_home/hypr/hyprland.conf" 0644
unset hyprland_conf

# --- keyboard layout ----------------------------------------------------------
#
# Debian already asked which keyboard this is, during installation, and wrote the
# answer to /etc/default/keyboard (XKBLAYOUT="se" on a Swedish machine). Hyprland
# does not read that file. It has its own input:kb_layout, defaulting to "us", so
# without this step the compositor ignores a choice the user already made — and
# hyprlock with it, which is the worst place to discover your keyboard is not the
# one you typed your password on.
#
# Rendered rather than pointed at: /etc/default/keyboard is shell syntax and
# hyprlang is not.
#
# This is sourced AFTER default/hypr/input.conf and BEFORE the user's own
# hyprland.conf, so it beats our defaults and loses to theirs — a user who wants
# a layout other than the system one still just sets kb_layout in their file.
render_keyboard_conf() {
  # Overridable so the render can be exercised against layouts this machine
  # does not have; nothing but the tests ever sets it.
  local kb=${OMAKEB_KEYBOARD_FILE:-/etc/default/keyboard}
  local layout="" variant="" model="" options="" body=""

  if [[ -r $kb ]]; then
    # /etc/default/keyboard is shell syntax by design — console-setup's own
    # scripts source it — so do the same, in a subshell so nothing it sets
    # leaks into ours.
    # The trailing `.` is a sentinel, and it is load-bearing. Command
    # substitution strips trailing newlines, so with XKBOPTIONS="" — which is
    # the normal content of this file — the fourth line simply would not be
    # there, the fourth `read` would hit EOF and return non-zero, and under
    # install.sh's `set -e` that ends the installer. It did: a real install died
    # here, at 60-config, having written nothing and printed no error.
    local vals
    vals=$(. "$kb" >/dev/null 2>&1; printf '%s\n%s\n%s\n%s\n.\n' \
             "${XKBLAYOUT:-}" "${XKBVARIANT:-}" "${XKBMODEL:-}" "${XKBOPTIONS:-}")
    # One `read` per line: a single `read a b c d` would take only the FIRST
    # line and split it into four, quietly dropping everything but the layout.
    # `IFS=` keeps each value exactly as the file spelled it.
    { IFS= read -r layout
      IFS= read -r variant
      IFS= read -r model
      IFS= read -r options
    } <<<"$vals"
  fi

  # hyprlang truncates a line at an unescaped '#', and '##' is its escape. No
  # XKB value has ever contained one, but this file is generated from something
  # outside our control, so do not bet the whole config on that.
  escape_hash() { printf '%s' "${1//\#/##}"; }

  # Emit only what is actually set. An empty kb_variant or kb_options is already
  # Hyprland's default, and writing one changes nothing except the diff.
  #
  # `if`, not `[[ ... ]] && ...`. install.sh runs under `set -e`, where a bare
  # `test && assignment` whose test FAILS is a statement returning non-zero, and
  # that aborts the entire installer. XKBVARIANT="" and XKBOPTIONS="" are the
  # normal state of /etc/default/keyboard, so the common case was the fatal one:
  # this killed a real install at 60-config, silently, after writing nothing.
  # None of the tests caught it because none of them ran under `set -e`.
  if [[ -n $layout ]]; then
    body+="    kb_layout = $(escape_hash "$layout")"$'\n'
  fi
  if [[ -n $variant ]]; then
    body+="    kb_variant = $(escape_hash "$variant")"$'\n'
  fi
  if [[ -n $model ]]; then
    body+="    kb_model = $(escape_hash "$model")"$'\n'
  fi
  if [[ -n $options ]]; then
    body+="    kb_options = $(escape_hash "$options")"$'\n'
  fi

  {
    echo "# Managed by omakeb. Edits are overwritten on update."
    echo "#"
    if [[ -n $body ]]; then
      echo "# Taken from /etc/default/keyboard, which Debian filled in when you chose"
      echo "# your keyboard during installation."
      echo "#"
      echo "# To use a different layout in Hyprland only, set input:kb_layout in"
      echo "# ~/.config/omakeb/hyprland.conf — that file is sourced after this one and"
      echo "# wins."
      echo "#"
      echo "# To change it everywhere — console, greeter and Hyprland:"
      echo "#     sudo dpkg-reconfigure keyboard-configuration"
      echo "#     bash $OMAKEB_PATH/install.sh"
      echo "# The first takes effect at once for the console and the greeter. This file"
      echo "# is only rewritten by the installer, so Hyprland keeps the old layout until"
      echo "# the second command runs."
      echo "input {"
      printf '%s' "$body"
      echo "}"
    else
      echo "# /etc/default/keyboard is missing or sets no XKB values, so Hyprland keeps"
      echo "# its own default (us)."
      echo "#"
      echo "# Either set input:kb_layout in ~/.config/omakeb/hyprland.conf, or tell"
      echo "# Debian which keyboard this is and regenerate this file:"
      echo "#     sudo dpkg-reconfigure keyboard-configuration"
      echo "#     bash $OMAKEB_PATH/install.sh"
      echo "#"
      echo "# hyprlang errors on a missing \`source =\` target, so this file exists even"
      echo "# when it has nothing to say."
    fi
  } | write_file "$config_home/hypr/keyboard.conf" 0644
}

render_keyboard_conf

# --- hyprpaper ----------------------------------------------------------------
# No wallpaper is preloaded: shipped themes carry no images (we do not
# redistribute artwork of unknown provenance), so until a theme with a
# backgrounds/ directory is imported, misc:background_color from the rendered
# hypr/colors.conf is the desktop. ipc must stay on —
# the menu's background switcher drives hyprpaper entirely over `hyprctl
# hyprpaper preload` / `wallpaper`.
write_file "$config_home/hypr/hyprpaper.conf" 0644 <<'HYPRPAPER'
# Managed by omakeb. Edits are overwritten on update.
ipc = on
splash = false
HYPRPAPER

# --- hypridle -----------------------------------------------------------------
# The whole idle policy lives here, and SUPER+CTRL+I (omakeb-toggle-idle) turns
# it off by stopping the process. Timeouts escalate: dim, lock, screen off.
#
# `loginctl lock-session` rather than calling hyprlock directly, so that
# anything else asking logind to lock (a lid close, `loginctl lock-sessions`)
# takes the same path — and so before_sleep_cmd cannot race a second locker.
write_file "$config_home/hypr/hypridle.conf" 0644 <<'HYPRIDLE'
# Managed by omakeb. Edits are overwritten on update.
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
    ignore_dbus_inhibit = false
}

listener {
    timeout = 150
    on-timeout = brightnessctl -s set 10
    on-resume = brightnessctl -r
}

listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

listener {
    timeout = 600
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}
HYPRIDLE

# --- waybar -------------------------------------------------------------------
# Structure and style are separate files, which suits us: the theme slice will
# regenerate style.css from tokens and leave config.jsonc alone.
#
# Icon glyphs come from the Nerd Font symbols installed by install/50-fonts.sh.
# No font stack names that font: the fontconfig snippet shipped with it makes
# the symbol face a global fallback, so plain "JetBrains Mono" resolves icons.
write_file "$config_home/waybar/config.jsonc" 0644 <<'WAYBARCONF'
// Managed by omakeb. Edits are overwritten on update.
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "spacing": 6,

  "modules-left": ["custom/omakeb", "hyprland/workspaces", "hyprland/submap"],
  "modules-center": ["clock"],
  "modules-right": ["tray", "pulseaudio", "bluetooth", "network", "cpu", "memory", "battery"],

  "custom/omakeb": {
    "format": "󰣚",
    "tooltip": false,
    "on-click": "omakeb-menu"
  },

  "hyprland/workspaces": {
    "format": "{id}",
    "on-click": "activate",
    "sort-by-number": true
  },

  "hyprland/submap": {
    "format": "{}",
    "tooltip": false
  },

  "clock": {
    "format": "{:%a %d %b  %H:%M}",
    "tooltip-format": "<tt>{calendar}</tt>",
    "calendar": {
      "mode": "month",
      "on-scroll": 1
    },
    "on-click": "omakeb-menu"
  },

  "tray": {
    "icon-size": 16,
    "spacing": 8
  },

  "pulseaudio": {
    "format": "{icon} {volume}%",
    "format-muted": "󰝟",
    "format-icons": { "default": ["󰕿", "󰖀", "󰕾"] },
    "scroll-step": 5,
    "on-click": "omakeb-launch-once pavucontrol"
  },

  "bluetooth": {
    "format": "󰂯",
    "format-disabled": "",
    "format-connected": "󰂱 {num_connections}",
    "tooltip-format": "{controller_alias}\t{controller_address}",
    "on-click": "omakeb-launch-once blueman-manager"
  },

  "network": {
    "format-wifi": "󰖩 {signalStrength}%",
    "format-ethernet": "󰈀",
    "format-linked": "󰈀",
    "format-disconnected": "󰖪",
    "tooltip-format": "{ifname}  {ipaddr}",
    "on-click": "omakeb-launch-tui nmtui connect"
  },

  "cpu": {
    "format": "󰘚 {usage}%",
    "interval": 5,
    "on-click": "omakeb-launch-tui btop"
  },

  "memory": {
    "format": "󰍛 {percentage}%",
    "interval": 5,
    "on-click": "omakeb-launch-tui btop"
  },

  // Waybar disables this module on a machine with no battery, so it costs
  // nothing on a desktop.
  "battery": {
    "states": { "warning": 25, "critical": 10 },
    "format": "{icon} {capacity}%",
    "format-charging": "󰂄 {capacity}%",
    "format-icons": ["󰁺", "󰁼", "󰁾", "󰂀", "󰂂", "󰁹"]
  }
}
WAYBARCONF

# --- themed files -------------------------------------------------------------
# waybar's style.css, mako's config, fuzzel.ini, kitty.conf, hyprlock.conf,
# hypr/colors.conf, the btop theme, gtk.css and starship.toml are NOT written
# here. They are rendered from the active palette by install/70-theme.sh, which
# runs immediately after this step, and re-rendered by omakeb-theme-set every
# time the theme changes.
#
# The split is by ownership, not by file type: this step owns structure that no
# theme can change (waybar's module list above, hypridle's timeouts, the
# Hyprland entry point), and templates/*.tpl own everything a colour appears in.
# Keeping a colour in both places is how they drift.

# --- session PATH -------------------------------------------------------------
# The Hyprland session's PATH comes from ~/.profile, which contributes only
# ~/.local/bin. That makes the symlinks 40-shell.sh creates load-bearing: a
# command added to bin/ after the last install has no link, and every
# `exec-once` or keybinding naming it silently does nothing — Hyprland does not
# report a failed exec. That bit us with omakeb-gl-fallback.
#
# uwsm sources uwsm/env-${compositor} for the graphical session, so put the
# checkout's bin/ on PATH directly. The symlinks stay (they serve plain login
# shells and anything not started by uwsm); this removes the failure mode where
# stale links silently disable a feature.
#
# env-hyprland rather than env, so a user's own uwsm/env stays theirs.
write_file "$config_home/uwsm/env-hyprland" 0644 <<UWSMENV
# Managed by omakeb. Edits are overwritten on update.
# Sourced by uwsm for the graphical session.
case ":\$PATH:" in
  *":$OMAKEB_PATH/bin:"*) ;;
  *) PATH="$OMAKEB_PATH/bin\${PATH:+:\$PATH}" ;;
esac
export PATH
UWSMENV

unset config_home
