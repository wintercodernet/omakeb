#!/bin/bash
# Keep the sudo timestamp warm for the length of the install.
#
# A full install downloads and unpacks several hundred megabytes, which takes
# well over sudo's default 15-minute timestamp_timeout on a slow link or an
# emulated VM. Without this, sudo re-prompts somewhere in the middle of an
# unattended run and the install stalls waiting for a password nobody is
# watching for.
#
# shellcheck shell=bash

_sudo_keepalive_pid=

# Do we already have usable sudo access without being asked anything?
#
# This must be `sudo -n true` and not `sudo -v`. On a machine where the user has
# a NOPASSWD rule *and* ordinary %sudo group membership — which is the normal
# state of CI images, cloud images and provisioned test boxes — `sudo -v` still
# demands a password, because the group rule that matches has no NOPASSWD tag.
# `sudo -n true` reports what actually happens when we run a command, which is
# the thing we care about.
sudo_available_now() { sudo -n true 2>/dev/null; }

# What to tell someone who cannot sudo at all. This is the Debian trap: the
# installer only adds the first user to the sudo group when the root password is
# left blank, so a box where one was set has a user who cannot sudo, and often
# no sudo package either. Asking what sudo can DO (below) rather than testing
# for the group is deliberate: a NOPASSWD rule in /etc/sudoers.d is just as good
# and common on cloud and provisioned images, and a group test refuses it.
_sudo_fix_hint() {
  printf '%s\n' \
    "This is normal on Debian when a root password was set during installation," \
    "which leaves the first user out of the sudo group. Fix it as root:" \
    "    su -" \
    "    apt install -y sudo" \
    "    /sbin/adduser ${USER:-\$USER} sudo" \
    "then log out and back in (group changes need a fresh session) and re-run."
}

sudo_keepalive_start() {
  [[ -n $_sudo_keepalive_pid ]] && return 0

  command -v sudo >/dev/null 2>&1 \
    || die "sudo is not installed, so omakeb cannot install anything.
$(_sudo_fix_hint)"

  if ! sudo_available_now; then
    if [[ -t 0 ]]; then
      # Interactive: prompt once, up front, rather than partway through. This
      # also fails, after the prompt, for a user sudo does not know at all,
      # which is the case the hint is for.
      sudo -v || die "${USER:-this user} cannot use sudo (authentication failed or not permitted).
$(_sudo_fix_hint)"
    else
      die "sudo needs a password but no terminal is available to ask on.
Run omakeb from an interactive shell, or give this user a NOPASSWD sudo rule.
If this user cannot use sudo at all:
$(_sudo_fix_hint)"
    fi
  fi

  # Refresh well inside the default timeout. The loop exits on its own if the
  # parent dies, so an interrupted install cannot leave it running.
  while true; do
    sudo -n true 2>/dev/null || exit
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done &
  _sudo_keepalive_pid=$!

  # Stop the keepalive however the script ends, including on failure.
  trap sudo_keepalive_stop EXIT
}

sudo_keepalive_stop() {
  [[ -z $_sudo_keepalive_pid ]] && return 0
  kill "$_sudo_keepalive_pid" 2>/dev/null || true
  _sudo_keepalive_pid=
}
