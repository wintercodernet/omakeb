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

# --- hand the network to NetworkManager ---------------------------------------
#
# The Debian installer writes the interface it installed over into
# /etc/network/interfaces, for ifupdown. Debian's NetworkManager.conf has
# `[ifupdown] managed=false`, which means NM leaves any interface named there
# alone — so on a netinst machine every NM front-end (the bar's nmtui, the
# connection editor) showed an empty list. That was the "blank network page".
#
# The fix is the one Debian's NM README gives: take those stanzas out of the
# file. `managed=true` instead would leave ifupdown and NM both holding the same
# interface, which is how you get two DHCP clients and a flaky link.
#
# Only stanzas we fully understand are moved: DHCP (or SLAAC for inet6), with
# at most a WPA-PSK network, which is everything the installer writes. A static
# address, a bridge, a bond, a wpa-conf file or a mapping stays with ifupdown
# and is reported — guessing at someone's hand-written network config is how a
# remote machine stops answering.
#
# The Wi-Fi password lives in that stanza, so it becomes an NM keyfile BEFORE
# the stanza is commented out. Ethernet needs no file: NM creates its "Wired
# connection 1" by itself for any managed interface with no connection.
#
# Nothing is restarted. NM reads the file when it starts, so the switch happens
# at the reboot that ends the install (or the next one, on a machine updated in
# place) and an SSH session over the old link is not cut out from under us.
hand_interfaces_to_nm() {
  # Overridable so the tests can run this against fixtures; nothing else sets them.
  local file=${OMAKEB_IFUPDOWN_FILE:-/etc/network/interfaces}
  local nmdir=${OMAKEB_NM_CONNECTIONS_DIR:-/etc/NetworkManager/system-connections}
  local -A bad=() ssid=() psk=() seen=()
  local -a lines=() out=() names=() kept=() moved=()
  local line cur="" key val fam method n changed=0 skipping=0

  if [[ ! -r $file ]]; then
    log_skip "no $file; nothing for ifupdown to hold back from NetworkManager"
    return 0
  fi
  mapfile -t lines < "$file"

  # Pass 1: what does each interface's config consist of?
  for line in "${lines[@]}"; do
    read -r key val _ <<< "$line" || true
    case "$key" in
      "" | \#*) ;;
      iface)
        read -r _ cur fam method _ <<< "$line" || true
        seen[$cur]=1
        case "$fam/$method" in
          inet/dhcp | inet6/auto | inet6/dhcp) ;;
          *) bad[$cur]="$fam $method" ;;
        esac
        ;;
      mapping)
        cur="#mapping"
        for n in $val; do bad[$n]=mapping; done
        ;;
      auto | allow-* | source | source-directory | source-dir) cur="" ;;
      wpa-ssid | wpa-psk)
        [[ -n $cur && $cur != \#* ]] || continue
        val=${line#*"$key"}
        val=${val#"${val%%[![:space:]]*}"}
        val=${val%"${val##*[![:space:]]}"}
        [[ $val == \"*\" ]] && val=${val:1:${#val}-2}
        # Characters a GKeyFile value would need escaping for. Rare in a
        # network name; not worth getting subtly wrong.
        if [[ -z $val || $val == *[\;\\]* || $val =~ ^[[:space:]]|[[:space:]]$ ]]; then
          bad[$cur]="$key with characters omakeb does not convert"
        elif [[ $key == wpa-ssid ]]; then
          ssid[$cur]=$val
        else
          psk[$cur]=$val
        fi
        ;;
      *)
        [[ -n $cur && $cur != \#* ]] && bad[$cur]=${bad[$cur]:-"option $key"}
        ;;
    esac
  done
  for n in "${!psk[@]}"; do
    [[ -n ${ssid[$n]:-} ]] || bad[$n]="wpa-psk without wpa-ssid"
  done

  for n in "${!seen[@]}"; do
    [[ $n == lo ]] && continue
    if [[ -n ${bad[$n]:-} ]]; then
      log_warn "leaving $n with ifupdown ($file: ${bad[$n]})."
      log_warn "NetworkManager will not manage it until that stanza is removed by hand."
    else
      moved+=("$n")
    fi
  done
  if ((${#moved[@]} == 0)); then
    log_skip "ifupdown holds no interface NetworkManager should have"
    return 0
  fi

  # Wi-Fi credentials first, so a failure here leaves the old config working.
  for n in "${moved[@]}"; do
    [[ -n ${ssid[$n]:-} ]] || continue
    {
      printf '%s\n' "# Written by omakeb from the $n stanza in $file." \
        "[connection]" "id=${ssid[$n]}" "uuid=$(cat /proc/sys/kernel/random/uuid)" \
        "type=wifi" "interface-name=$n" "" \
        "[wifi]" "mode=infrastructure" "ssid=${ssid[$n]}" ""
      [[ -n ${psk[$n]:-} ]] &&
        printf '%s\n' "[wifi-security]" "key-mgmt=wpa-psk" "psk=${psk[$n]}" ""
      printf '%s\n' "[ipv4]" "method=auto" "" "[ipv6]" "method=auto"
    } | write_file_sudo "$nmdir/omakeb-$n.nmconnection" 0600
  done

  # Pass 2: comment out what moved, and nothing else.
  for line in "${lines[@]}"; do
    read -r key val _ <<< "$line" || true
    case "$key" in
      iface | mapping)
        read -r _ n _ <<< "$line" || true
        skipping=0
        if [[ " ${moved[*]} " == *" $n "* ]]; then skipping=1; fi
        ;;
      auto | allow-*)
        skipping=0
        kept=()
        read -r -a names <<< "${line#*"$key"}" || true
        for n in "${names[@]}"; do
          [[ " ${moved[*]} " == *" $n "* ]] || kept+=("$n")
        done
        if ((${#kept[@]} != ${#names[@]})); then
          out+=("#omakeb# $line")
          ((${#kept[@]})) && out+=("$key ${kept[*]}")
          changed=1
          continue
        fi
        ;;
      source | source-directory | source-dir) skipping=0 ;;
    esac
    if ((skipping)) && [[ -n $key ]]; then
      out+=("#omakeb# $line")
      changed=1
    else
      out+=("$line")
    fi
  done
  ((changed)) || return 0

  if ! sudo test -e "$file.omakeb-backup"; then
    sudo cp -a "$file" "$file.omakeb-backup"
    log_ok "saved the installer's network config to $file.omakeb-backup"
  fi
  {
    printf '%s\n' \
      "# omakeb commented out the lines marked #omakeb# so that NetworkManager" \
      "# manages these interfaces: ${moved[*]}. The original is $file.omakeb-backup." \
      ""
    printf '%s\n' "${out[@]}"
  } | write_file_sudo "$file" 0644
  log_ok "NetworkManager takes over ${moved[*]} at the next reboot"
}

if pkg_installed network-manager; then
  hand_interfaces_to_nm
else
  log_skip "network-manager is not installed; leaving /etc/network/interfaces alone"
fi
