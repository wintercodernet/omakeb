#!/bin/bash
# Notice an NVIDIA card and offer the opt-in setup.
#
# This step NEVER enables anything by itself. Installing a proprietary kernel
# module and turning on Debian's non-free component is a policy decision, not a
# technical one, and it belongs to the person at the keyboard.
#
# But leaving it undiscovered is its own failure: without the setup you get
# nouveau — which does drive a Hyprland session, just slowly — and no hint that
# anything better exists. The machine knows whether it has a 0x10de device;
# making the user know is strictly worse than making the installer notice.
#
# So: detect, and either ask (with a terminal) or print the command (without).
# The real work, and the refusals for Secure Boot and hybrid graphics, all stay
# in bin/omakeb-hw-nvidia.
#
# Runs after 30-desktop so the graphics stack it layers onto is already present,
# and well before 80-services hands the machine to greetd.
# shellcheck shell=bash

# Sourced by install.sh inside a loop — never call `exit` here, it would abort
# the whole installer.

_nvidia_present() {
  local vendor
  # Read the PCI vendor id straight from sysfs rather than shelling out to
  # lspci, which a Debian netinst does not install.
  for vendor in /sys/bus/pci/devices/*/vendor; do
    [[ -r $vendor ]] || continue
    [[ "$(cat "$vendor" 2>/dev/null)" == "0x10de" ]] && return 0
  done
  return 1
}

if ! _nvidia_present; then
  # No card, nothing to say. Silence is correct here: most machines are not
  # NVIDIA machines and a "no NVIDIA found" line is noise on every one of them.
  :
elif [[ -d "$OMAKEB_STATE/hw-nvidia" ]]; then
  log_skip "NVIDIA already configured (omakeb-hw-nvidia revert undoes it)"
elif [[ ! -t 0 ]]; then
  # Unattended: the container harness, or a scripted install. Never prompt into
  # a void — say what to run and move on. Same terminal test lib/sudo.sh uses.
  log_warn "NVIDIA card detected, and this install is not interactive."
  log_warn "Hyprland needs extra setup on NVIDIA. When convenient, run:"
  log_warn "    omakeb-hw-nvidia enable"
  log_warn "Until then the session uses nouveau, which works but is slow."
else
  log_info ""
  log_info "An NVIDIA card is present. Hyprland needs additional setup to use it:"
  log_info "  * Debian's contrib and non-free components get enabled"
  log_info "  * a proprietary driver is installed, built as a kernel module"
  log_info "  * DRM modesetting is turned on (without it, a black screen)"
  log_info "  * a reboot is required afterwards"
  log_info ""
  log_info "Declining is safe: the session falls back to nouveau, which is"
  log_info "slower but works, and you can run 'omakeb-hw-nvidia enable' later."
  log_info ""

  # Default no. A stray Enter must not opt anyone into non-free software.
  reply=
  read -r -p "  Set up the NVIDIA driver now? [y/N] " reply || reply=
  case "${reply,,}" in
    y | yes)
      # No --yes: omakeb-hw-nvidia prints the exact list of files it will change
      # and asks again. The two questions are different — "now or later?" here,
      # "here is precisely what changes, proceed?" there — so the second prompt
      # is worth keeping rather than suppressing.
      if command -v omakeb-hw-nvidia >/dev/null 2>&1; then
        omakeb-hw-nvidia enable || log_warn "NVIDIA setup did not complete; the rest of the install continues."
      else
        # 40-shell.sh has not linked bin/ onto PATH yet at this point.
        "$OMAKEB_PATH/bin/omakeb-hw-nvidia" enable ||
          log_warn "NVIDIA setup did not complete; the rest of the install continues."
      fi
      ;;
    *)
      log_skip "NVIDIA setup declined; run 'omakeb-hw-nvidia enable' to change your mind"
      ;;
  esac
  unset reply
fi

unset -f _nvidia_present
