#!/bin/bash
# Apt sources and pinning.
#
# The whole Hyprland stack lives in trixie-backports, not trixie main, so
# backports is mandatory on a release architecture. But backports must not
# become a general upgrade channel, or an unrelated `apt upgrade` starts
# dragging newer libraries onto a stable box. So: enable backports, pin it to
# 100 globally (never chosen on its own), then lift exactly the packages we
# need to 500.
#
# Get this right on day one. Retrofitting a pin after users have installed
# means their machines have already drifted.
#
# Nothing here is conditional on a named architecture. Whether the stack is
# installable is settled at the end, by asking apt.
# shellcheck shell=bash

apt_install ca-certificates

# Backports is only written when both hold:
#
#   - the architecture is a release architecture. debian-ports architectures
#     have no backports suite at all; adding the source would produce nothing
#     but 404s on every apt update.
#   - the running release IS the one omakeb targets (lib/release.sh). On sid or
#     forky, which preflight lets through with a warning, a trixie-backports
#     source is worse than useless. The 500 pin ties with the machine's own
#     main, so apt takes the newer sid/forky version anyway and the pin check
#     below dies on a machine that is fine — or, the day backports happens to
#     be newer, passes and installs a compositor built against the previous
#     release's libraries. Those suites carry Hyprland in main already.
#
# Otherwise skip it, exactly as for debian-ports, and let the availability check
# below decide whether the machine is usable. A backports source an earlier run
# already wrote is left where it is: removing apt sources is not something this
# step does unasked (D13), and bin/omakeb-update reports the mismatch.
_running_codename=$(release_codename)
if ! arch_is_release_arch; then
  log_warn "skipping $OMAKEB_BACKPORTS_SUITE: not available for $(arch_dpkg)"
  OMAKEB_BACKPORTS=0
elif [[ $_running_codename != "$OMAKEB_DEBIAN_CODENAME" ]]; then
  log_warn "skipping $OMAKEB_BACKPORTS_SUITE: this machine runs '${_running_codename:-unknown}', not $OMAKEB_DEBIAN_CODENAME"
  log_warn "the Hyprland stack must come from the suites already configured"
  OMAKEB_BACKPORTS=0
else
  write_file_sudo /etc/apt/sources.list.d/omakeb-backports.sources 0644 <<SOURCES
# Managed by omakeb. Edits will be overwritten on update.
Types: deb
URIs: http://deb.debian.org/debian
Suites: $OMAKEB_BACKPORTS_SUITE
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES

  write_file_sudo /etc/apt/preferences.d/omakeb-backports 0644 <<PINS
# Managed by omakeb. Edits will be overwritten on update.
#
# Debian backports already carries NotAutomatic: yes, which apt reads as
# priority 100. Stating it explicitly documents the intent and survives any
# future change to that convention.
Package: *
Pin: release n=$OMAKEB_BACKPORTS_SUITE
Pin-Priority: 100

# The Hyprland stack, promoted to the default candidate. Globs cover the
# shared libraries (libhyprutils, libhyprlang, libhyprgraphics, libhyprcursor)
# without pinning each one by name as upstream renames them between releases.
Package: hypr* libhypr* xdg-desktop-portal-hyprland uwsm quickshell libquickshell*
Pin: release n=$OMAKEB_BACKPORTS_SUITE
Pin-Priority: 500
PINS

  OMAKEB_BACKPORTS=1
fi
unset _running_codename
export OMAKEB_BACKPORTS

apt_updated=
apt_refresh

# The real architecture check. Everything above is arch-agnostic; this is where
# an architecture that cannot run omakeb finds out, with the full list of what
# is missing rather than a single package name.
mapfile -t _bp_pkgs < <(pkg_list "$OMAKEB_PATH/packages/backports.list")
mapfile -t _base_pkgs < <(pkg_list "$OMAKEB_PATH/packages/base.list")
mapfile -t _desktop_pkgs < <(pkg_list "$OMAKEB_PATH/packages/desktop.list")

require_packages "compositor stack" "${_bp_pkgs[@]}"
require_packages "terminal environment" "${_base_pkgs[@]}"
require_packages "desktop environment" "${_desktop_pkgs[@]}"

# Confirm the pin actually took effect, rather than the candidate coming from
# somewhere unexpected. A silent mis-pin surfaces much later as a mysteriously
# old Hyprland.
if (( OMAKEB_BACKPORTS )); then
  if apt-cache policy hyprland | grep -qF -- "$OMAKEB_BACKPORTS_SUITE"; then
    log_ok "hyprland candidate: $(apt-cache policy hyprland | awk '/Candidate:/{print $2}') (backports)"
  else
    die "hyprland is installable but not from $OMAKEB_BACKPORTS_SUITE; check /etc/apt/preferences.d/omakeb-backports."
  fi
fi
