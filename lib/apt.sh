#!/bin/bash
# shellcheck shell=bash

# sudo's env_reset (a Debian default) strips DEBIAN_FRONTEND, so exporting it
# here does nothing for the apt calls below — debconf then walks its whole
# frontend chain looking for a terminal, and on a real TTY would show dialogs
# in the middle of an unattended install. Pass it through `env` on each sudo
# call instead: `sudo VAR=val cmd` is refused unless the sudoers rule carries
# SETENV, but `sudo env VAR=val cmd` always works.
APT_ENV=(env DEBIAN_FRONTEND=noninteractive)

apt_updated=

# Refresh indexes at most once per install run.
apt_refresh() {
  [[ -n $apt_updated ]] && return 0
  sudo "${APT_ENV[@]}" apt-get update -qq
  apt_updated=1
}

pkg_installed() {
  dpkg-query -W -f='${db:Status-Status}\n' "$1" 2>/dev/null | grep -q '^installed$'
}

# apt_install <pkg>...   — installs only what is missing, so re-runs are quiet.
apt_install() {
  local missing=()
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log_skip "already installed: $*"
    return 0
  fi
  apt_refresh
  log_info "installing: ${missing[*]}"
  sudo "${APT_ENV[@]}" apt-get install -y -qq "${missing[@]}" >/dev/null
}

# apt_install_from <suite> <pkg>...  — explicit -t, for the backports stack.
apt_install_from() {
  local suite=$1; shift
  local missing=()
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log_skip "already installed: $*"
    return 0
  fi
  apt_refresh
  log_info "installing from $suite: ${missing[*]}"
  sudo "${APT_ENV[@]}" apt-get install -y -qq -t "$suite" "${missing[@]}" >/dev/null
}

# Read a package list file, stripping comments and blanks.
pkg_list() {
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1" | tr -d ' \t'
}
