#!/bin/bash
# Login: greetd + tuigreet, launching Hyprland through uwsm.
#
# This is the step that decides whether the machine boots to a login prompt or
# to a black screen, so it is written to be boring and to say what it is doing.
# Three facts it is built on, each checked against the Debian packaging rather
# than assumed:
#
#   1. The greeter package is `tuigreet`, not `greetd-tuigreet`. (That name was
#      a real bug.) Both it and greetd are tier 1 and
#      already installed from packages/desktop.list.
#
#   2. Debian's hyprland ships BOTH session entries:
#        /usr/share/wayland-sessions/hyprland.desktop
#        /usr/share/wayland-sessions/hyprland-uwsm.desktop
#      and the uwsm one contains exactly
#        Exec=uwsm start -e -D Hyprland hyprland.desktop
#      That is the invocation used below, verbatim. It is the form the Hyprland
#      maintainers ship and test: `-D Hyprland` fills XDG_CURRENT_DESKTOP, `-e`
#      says use that name exclusively rather than appending to whatever the
#      display manager left in the environment, and `hyprland.desktop` is a
#      Desktop Entry ID that uwsm resolves — not a path — which is what lets
#      uwsm read the compositor's real command line, name and comment from the
#      entry. Writing our own `uwsm start -- Hyprland` here would work until the
#      day Debian changes the Exec line, and would drift silently.
#
#   3. greetd.service on Debian has `[Install] Alias=display-manager.service`
#      and no WantedBy. systemd's stock graphical.target has
#      `Wants=display-manager.service`, so enabling greetd plus a graphical
#      default target is the whole mechanism.
#
# RECOVERY, because this is the least-tested path in the design: if the screen
# is black after a reboot, switch to a text console with Ctrl+Alt+F2, log in,
# and run `sudo systemctl disable greetd`. The machine then boots to a console
# and everything else omakeb installed still works.
# shellcheck shell=bash

# --- how the session is started -----------------------------------------------
#
# Decided here rather than hardcoded, so a machine where the backports uwsm did
# not install still gets a login screen instead of a session command that
# cannot run.
session_cmd=""
if command -v uwsm >/dev/null 2>&1 && [[ -r /usr/share/wayland-sessions/hyprland.desktop ]]; then
  # The Desktop Entry ID, not a path. See note 2 above.
  session_cmd="uwsm start -e -D Hyprland hyprland.desktop"
  log_ok "session: Hyprland via uwsm (systemd user session)"
elif command -v Hyprland >/dev/null 2>&1; then
  session_cmd="Hyprland"
  log_warn "uwsm is not installed, or hyprland.desktop is missing."
  log_warn "Falling back to launching Hyprland directly. The session will work,"
  log_warn "but it will not be a systemd user session: systemctl --user, XDG"
  log_warn "autostart and ordered shutdown of session units will not apply."
  # The five unit-backed daemons are the part of that which would otherwise be
  # invisible: nothing reaches graphical-session.target here, so systemd starts
  # none of them. bin/omakeb-session-daemons starts them itself at session start
  # (D15) — unsupervised, but present, which is the difference between a usable
  # fallback and one with no bar and no screen lock.
  log_warn "waybar, mako, hyprpaper, hypridle and hyprsunset will be started by"
  log_warn "omakeb at session start instead, without systemd supervision."
else
  session_cmd=""
  log_warn "Neither uwsm nor Hyprland is installed; skipping the greetd setup."
  log_warn "Re-run install.sh once install/30-desktop.sh has succeeded."
fi

if [[ -n $session_cmd ]]; then
  # --- greetd -----------------------------------------------------------------
  #
  # /etc/greetd/config.toml is a dpkg conffile, so this counts as a local
  # modification and `apt upgrade` will report it. That is the right trade:
  # every piece of greetd documentation points at this path, which matters a
  # great deal when someone is debugging a login screen. Our apt calls run under
  # DEBIAN_FRONTEND=noninteractive, which keeps the local file without asking.
  #
  # vt = 7 matches Debian's own greetd.service, which carries
  # `Conflicts=getty@tty7.service`. The tutorials that say vt = 1 are written
  # for distributions that do not run a getty there; on Debian, getty@tty1 is
  # active and the two would fight over the console.
  #
  # tuigreet flags (0.9.1, contrib/man/tuigreet-1.scd):
  #   --remember               pre-fill the last username
  #   --remember-user-session  and their last session; requires --remember and
  #                            overrides --cmd from the second login onwards
  #   --cmd                    what to run when nothing has been remembered and
  #                            no session was picked from the F3 menu
  # tuigreet also lists /usr/share/wayland-sessions itself, so
  # "Hyprland (uwsm-managed)" is selectable there even though --cmd already
  # points at it.
  write_file_sudo /etc/greetd/config.toml 0644 <<GREETD
# Managed by omakeb. Edits will be overwritten on update.
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --remember --remember-user-session --asterisks --greeting 'omakeb' --cmd '$session_cmd'"
user = "_greetd"
GREETD

  # dh_installsystemd already enables greetd when the package is installed, so
  # this is normally a no-op; it matters on a box where someone disabled it.
  if [[ "$(systemctl is-enabled greetd 2>/dev/null)" == "enabled" ]]; then
    log_skip "greetd already enabled"
  else
    sudo systemctl enable greetd >/dev/null 2>&1 &&
      log_ok "enabled greetd (aliased to display-manager.service)" ||
      log_warn "could not enable greetd; check: systemctl status greetd"
  fi

  # A netinst with no desktop task can be left on multi-user.target, and
  # graphical.target is what pulls in display-manager.service.
  current_target=$(systemctl get-default 2>/dev/null || echo "")
  if [[ $current_target == graphical.target ]]; then
    log_skip "default target already graphical.target"
  else
    sudo systemctl set-default graphical.target >/dev/null 2>&1 &&
      log_ok "default systemd target set to graphical.target (was ${current_target:-unknown})" ||
      log_warn "could not set the default target to graphical.target"
  fi
  unset current_target
fi
unset session_cmd

# --- the notification daemon's two front doors --------------------------------
#
# Debian wires mako up twice, and both are enabled:
#
#   * mako.service — a systemd user unit, enabled at package install and pulled
#     in by graphical-session.target. Type=dbus, BusName=org.freedesktop.Notifications.
#   * /usr/share/dbus-1/services/fr.emersion.mako.service — which makes it D-Bus
#     activatable, so the session's first notify-send can start it on demand.
#
# That D-Bus file carries no `SystemdService=` line. Without one, dbus-daemon
# starts /usr/bin/mako ITSELF instead of asking systemd for the unit — so an
# early notification and graphical-session.target race for the bus name, and
# whichever loses exits with "Is a notification daemon already running?".
#
# On the test machine systemd was the loser: mako.service sat `failed` for the
# whole session while a stray mako under dbus.service quietly served the
# notifications. Nothing looked broken, because nothing was — until you asked
# systemd about it, or until lib/units.sh believed `is-active` and concluded the
# notification daemon was down.
#
# This is the D-Bus name race autostart.conf's header already mentions. Taking
# mako out of exec-once was necessary and, it turns out, not sufficient: the
# second starter was never Hyprland, it was dbus-daemon.
#
# `SystemdService=` makes both doors open onto the same unit. A service file in
# XDG_DATA_HOME shadows the one in /usr/share, so this needs no root, no dpkg
# diversion, and survives an upgrade of the mako package.
reconcile_mako_activation() {
  # Overridable so the tests can drive this against fixture service files;
  # nothing but the tests ever sets it.
  local sys=${OMAKEB_MAKO_DBUS_SERVICE:-/usr/share/dbus-1/services/fr.emersion.mako.service}
  local ours="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/fr.emersion.mako.service"
  local name exec_line

  if [[ ! -r $sys ]]; then
    log_skip "mako is not D-Bus activatable on this machine; nothing to reconcile"
    return 0
  fi

  # If Debian ever ships the line themselves, ours would only shadow theirs with
  # a stale copy. Stand down instead.
  if grep -q '^SystemdService=' "$sys"; then
    if [[ -e $ours ]]; then
      rm -f "$ours"
      log_ok "removed our mako activation override; the packaged file now sets SystemdService"
    else
      log_skip "mako D-Bus activation already routes through systemd"
    fi
    return 0
  fi

  # Copied from the packaged file rather than hardcoded: if the binary ever
  # moves, a shadow file pointing at the old path is worse than none at all.
  # `sed -n 's///p' | head -1` reads innocently and is a trap here: install.sh
  # runs with `set -o pipefail`, head closes the pipe after one line, sed can die
  # of SIGPIPE, and the pipeline returns 141 — which under `set -e` aborts the
  # installer. Let sed stop by itself instead; one process, no pipe, no signal.
  name=$(sed -n '/^Name=/{s/^Name=//;p;q;}' "$sys")
  exec_line=$(sed -n '/^Exec=/{s/^Exec=//;p;q;}' "$sys")
  : "${name:=org.freedesktop.Notifications}"
  : "${exec_line:=/usr/bin/mako}"

  write_file "$ours" 0644 <<MAKODBUS
# Managed by omakeb. Edits are overwritten on update.
#
# Shadows $sys, which omits SystemdService=.
# Without that line dbus-daemon starts its own copy of mako rather than
# mako.service, and the two race for $name.
[D-BUS Service]
Name=$name
Exec=$exec_line
SystemdService=mako.service
MAKODBUS
}

reconcile_mako_activation

# --- user services ------------------------------------------------------------
#
# Deliberately short. Under uwsm the session units (wayland-wm@, the environment
# preloader, xdg-autostart) are generated at login, and the portals are D-Bus
# activated — none of that is ours to enable. Debian's pipewire packages enable
# their user units through dh_installsystemduser at package install time, so
# audio is already wired up too.
#
# What is left is verification: if any of the three is disabled the desktop
# comes up mute, which is a miserable thing to debug from inside a session.
#
# `systemctl --user` needs a running user manager. There is none inside the
# install container, and there may be none over a bare SSH session, so a failure
# to reach it is reported and never fatal.
if systemctl --user show-environment >/dev/null 2>&1; then
  for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    systemctl --user list-unit-files "$unit" >/dev/null 2>&1 || continue
    state=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
    case "$state" in
      enabled | enabled-runtime | static | indirect)
        log_skip "user unit $unit: $state"
        ;;
      "")
        log_skip "user unit $unit: not installed"
        ;;
      *)
        if systemctl --user enable "$unit" >/dev/null 2>&1; then
          log_ok "enabled user unit $unit (was $state)"
        else
          log_warn "could not enable user unit $unit; audio may not start"
        fi
        ;;
    esac
  done
  unset unit state
else
  log_skip "no systemd user manager reachable; skipping user-unit checks"
fi
