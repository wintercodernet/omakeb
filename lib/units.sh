#!/bin/bash
# Session daemons that Debian ships as systemd user units.
#
# This is a real Debian-vs-Arch difference and the cause of the "two bars" bug.
# Debian's waybar, mako, hyprpaper, hypridle and hyprsunset packages enable
# their user units at install time (dh_installsystemduser drops symlinks into
# /etc/systemd/user/graphical-session.target.wants/). Upstream Omarchy starts
# these from Hyprland `exec-once`, which is correct on Arch — nothing enables
# them there. On Debian, launching the session through uwsm actually reaches
# graphical-session.target, so systemd starts all five and an exec-once line
# starts a second copy of each.
#
# So on a uwsm session systemd owns them, and we neither start nor stop them by
# process name.
#
# The fallback matters though, and for a long time only half of it was wired up.
# Hyprland started bare from a TTY (no uwsm) never reaches
# graphical-session.target, so the units do not run and the binaries are the
# only mechanism available. Every helper below prefers the unit and degrades to
# the process — but a helper only runs when something CALLS it, and until
# bin/omakeb-session-daemons existed the only callers were the toggle scripts.
# A fallback session therefore started none of the five at all: no bar, no
# notifications, no wallpaper daemon, no night light, and no hypridle, so
# nothing locked the screen. The list of the five now lives in
# default/session-daemons.tsv, and omakeb-session-daemons applies it at session
# start; these helpers are what the toggles use afterwards.
#
# shellcheck shell=bash

user_manager_available() { systemctl --user show-environment >/dev/null 2>&1; }

unit_loaded() {
  [[ "$(systemctl --user show "$1" -p LoadState --value 2>/dev/null)" == loaded ]]
}

# True when systemd is the right mechanism for this daemon on this machine.
unit_managed() {
  user_manager_available && unit_loaded "$1"
}

# service_up <unit> <binary> [args...]
service_up() {
  local unit=$1; shift
  if unit_managed "$unit"; then
    systemctl --user start "$unit"
  else
    omakeb-daemon "$@"
  fi
}

# service_down <unit> <binary>
service_down() {
  local unit=$1 binary=$2
  if unit_managed "$unit"; then
    # `stop` is explicit, so Restart=on-failure does not fire. Killing the
    # process instead WOULD look like a failure to systemd and get restarted
    # straight back — which is exactly the trap this helper exists to avoid.
    systemctl --user stop "$unit"
  else
    pkill -x "$binary" || true
  fi
}

# service_restart <unit> <binary> [args...]
#
# Used to drop state a daemon cannot be told to let go of — waybar's leaked
# layer surfaces after a display hotplug (bin/omakeb-monitor-watch). A reload
# will not do: SIGUSR2 re-reads the config but keeps the bars it already has.
service_restart() {
  local unit=$1; shift
  if unit_managed "$unit"; then
    systemctl --user restart "$unit"
  else
    pkill -x "$1" || true
    # omakeb-daemon is a no-op while the old process is still on the process
    # table, so give the kill a moment to land or the restart silently does
    # nothing.
    sleep 1
    omakeb-daemon "$@"
  fi
}

# service_running <unit> <binary>
service_running() {
  local unit=$1 binary=$2
  if unit_managed "$unit"; then
    systemctl --user is-active --quiet "$unit"
  else
    pgrep -x "$binary" >/dev/null 2>&1
  fi
}
