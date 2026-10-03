#!/bin/bash
# The graphical stack. Debian main first, then the compositor packages.
# shellcheck shell=bash

mapfile -t desktop_pkgs < <(pkg_list "$OMAKEB_PATH/packages/desktop.list")
apt_install "${desktop_pkgs[@]}"

mapfile -t bp_pkgs < <(pkg_list "$OMAKEB_PATH/packages/backports.list")
if (( ${OMAKEB_BACKPORTS:-0} )); then
  apt_install_from "$OMAKEB_BACKPORTS_SUITE" "${bp_pkgs[@]}"
else
  # No backports suite for this architecture, or this machine is not running
  # the release omakeb targets (install/10-sources.sh says which). That step
  # already verified these packages resolve from whatever suites are
  # configured, so a plain install is correct here rather than an error.
  apt_install "${bp_pkgs[@]}"
fi

# Portals: without an explicit preference, xdg-desktop-portal picks an
# implementation by guess and screenshare or file pickers break in ways that
# are miserable to debug. Be explicit.
#
# /etc, not /usr/share. xdg-desktop-portal (portals.conf(5)) looks for
# <desktop>-portals.conf in the user's config dir, then XDG_CONFIG_DIRS, then
# the sysconfdir (/etc/xdg-desktop-portal), and only after all of those in
# XDG_DATA_DIRS — so /etc is where an admin override belongs, and it wins over
# anything a package ships. /usr/share is package-owned space: upstream
# xdg-desktop-portal-hyprland installs a hyprland-portals.conf there, and if
# Debian's package does too, a file of ours at that path is reverted by every
# package upgrade, rewritten by every converge, and flagged by `dpkg --verify`.
#
# Machines installed by an older omakeb still have our copy in /usr/share. It
# is left alone, deliberately, with no migration: its content is the same as
# this, so it does no harm, and the /etc file shadows it regardless. Deleting
# it would be worse — if dpkg owns that path, we would be removing a packaged
# file, and the next upgrade would put it back anyway.
write_file_sudo /etc/xdg-desktop-portal/hyprland-portals.conf 0644 <<'PORTALS'
# Managed by omakeb.
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Settings=gtk
PORTALS
