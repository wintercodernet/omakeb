#!/bin/bash
# Refuse to run on anything we have not designed for, and explain the fix.
# shellcheck shell=bash

log_step "preflight"

[[ $EUID -ne 0 ]] || die "Do not run omakeb as root; it writes into \$HOME."

# --- Debian 13 only -----------------------------------------------------------
[[ -r /etc/os-release ]] || die "No /etc/os-release; this is not a Debian system."
# shellcheck disable=SC1091
. /etc/os-release

if [[ ${ID:-} != debian ]]; then
  die "omakeb targets Debian. Found ID=${ID:-unknown}."
fi

case "${VERSION_ID:-}" in
  13) log_ok "Debian 13 (${VERSION_CODENAME:-trixie})" ;;
  "")
    # No VERSION_ID means a rolling suite: sid or forky.
    # 10-sources.sh only configures trixie-backports on trixie itself (its
    # header says why); sid and forky carry Hyprland in main already.
    log_warn "Rolling Debian (${VERSION_CODENAME:-unknown}). omakeb targets stable 13;"
    log_warn "backports will not be configured. omakeb will use whatever suites you"
    log_warn "already have, and will stop if the Hyprland stack is unavailable."
    ;;
  *) die "omakeb targets Debian 13. Found ${VERSION_ID}. Upgrade first." ;;
esac

# --- Architecture -------------------------------------------------------------
# Deliberately not an allowlist. Debian builds the Hyprland stack on eight of
# its nine release architectures, and which packages exist is a question for
# apt, not for a hardcoded list here. install/10-sources.sh does the real check
# once the suites are configured. See lib/arch.sh.
arch=$(arch_dpkg)
if arch_is_release_arch; then
  log_ok "architecture: $arch"
else
  log_warn "architecture: $arch is not a Debian 13 release architecture."
  log_warn "trixie-backports does not exist for debian-ports. omakeb will rely on"
  log_warn "whatever suites you already have configured, and will stop if the"
  log_warn "Hyprland stack turns out to be unavailable."
fi

# --- sudo ---------------------------------------------------------------------
# Re-checked here as well as in boot.sh, because install.sh is also the repair
# path and may be run directly on a box that never saw boot.sh.
#
# No `sudo` group test. What matters is whether sudo will run a command for us,
# and a user with only a NOPASSWD rule in /etc/sudoers.d can, without being in
# the group. sudo_keepalive_start asks sudo itself (`sudo -n true`, then one
# prompt on a TTY) and dies with the "leave the root password blank / adduser"
# explanation when it cannot. Doing that here as well would prompt twice.
if ! command -v sudo >/dev/null 2>&1; then
  die "sudo is not installed, so omakeb cannot install anything.
$(_sudo_fix_hint)"
fi
# Prime the sudo timestamp and keep it warm for the rest of the install, so a
# long unattended run is not interrupted by a re-prompt. See lib/sudo.sh.
sudo_keepalive_start
log_ok "sudo available (keepalive running)"

# --- Existing desktop ---------------------------------------------------------
# D3 says we own the whole graphical stack. A pre-existing desktop is not fatal,
# but it means a second display manager and competing portals, so say so plainly.
for desktop_pkg in gnome-shell plasma-desktop xfce4-session cinnamon-session mate-session; do
  if pkg_installed "$desktop_pkg"; then
    log_warn "$desktop_pkg is installed. omakeb assumes a bare netinst and will"
    log_warn "install its own display manager (greetd) and portals. Expect to"
    log_warn "choose a session at login, and possible portal conflicts."
    break
  fi
done

# --- Network ------------------------------------------------------------------
getent hosts deb.debian.org >/dev/null 2>&1 || die "Cannot resolve deb.debian.org. Check networking."
log_ok "network reachable"

# --- Disk ---------------------------------------------------------------------
avail_mb=$(df -Pm /usr | awk 'NR==2{print $4}')
if (( avail_mb < 4096 )); then
  die "Only ${avail_mb}MB free on /usr; omakeb needs at least 4GB."
fi
log_ok "disk: ${avail_mb}MB free"

state_init
