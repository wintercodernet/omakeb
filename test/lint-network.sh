#!/bin/bash
# Executes hand_interfaces_to_nm from install/30-desktop.sh against fixture
# /etc/network/interfaces files, under the same `set -euo pipefail` install.sh
# uses. This edits the file a remote machine's network depends on, so the
# cases that must be LEFT ALONE matter as much as the ones that move.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# sudo becomes a pass-through so the function can write into the fixture dir.
runner=$tmp/run.sh
cat > "$runner" <<'RUNNER'
#!/bin/bash
set -euo pipefail
cd "$1"
export OMAKEB_PATH="$1"
source lib/log.sh
source lib/guard.sh
sudo() { "$@"; }
eval "$(sed -n '/^hand_interfaces_to_nm() {/,/^}/p' install/30-desktop.sh)"
hand_interfaces_to_nm
RUNNER

ifile=$tmp/interfaces
nmdir=$tmp/nm
run() {
  OMAKEB_IFUPDOWN_FILE=$ifile OMAKEB_NM_CONNECTIONS_DIR=$nmdir \
    bash "$runner" "$PWD" >"$tmp/log" 2>&1
}
fresh() { rm -rf "$nmdir" "$ifile" "$ifile.omakeb-backup"; cat > "$ifile"; }
# Lines that are still live config, i.e. what ifupdown will read.
live() { grep -v '^[[:space:]]*#' "$ifile" | grep -v '^[[:space:]]*$'; }

# --- 1. the netinst ethernet case ---------------------------------------------
fresh <<'X'
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug enp130s0
iface enp130s0 inet dhcp
# This is an autoconfigured IPv6 interface
iface enp130s0 inet6 auto
X
before=$fail
if run; then
  [[ "$(live)" == $'source /etc/network/interfaces.d/*\nauto lo\niface lo inet loopback' ]] ||
    bad "ethernet: unexpected live config left:"$'\n'"$(live)"
  [[ -f $ifile.omakeb-backup ]] || bad "ethernet: no backup written"
  grep -q '^allow-hotplug enp130s0' "$ifile.omakeb-backup" 2>/dev/null ||
    bad "ethernet: backup is not the original"
  [[ -e $nmdir ]] && bad "ethernet: wrote an NM connection; NM makes its own for wired"
else
  bad "ethernet: failed under set -e: $(cat "$tmp/log")"
fi
(( fail == before )) && ok "netinst ethernet stanza is handed over, loopback and source kept"

# --- 2. idempotent ------------------------------------------------------------
cp "$ifile" "$tmp/after1"
before=$fail
run || bad "second run failed: $(cat "$tmp/log")"
cmp -s "$ifile" "$tmp/after1" || bad "second run changed the file again"
(( fail == before )) && ok "a second run changes nothing"

# --- 3. Wi-Fi: the password becomes an NM keyfile -----------------------------
fresh <<'X'
auto lo
iface lo inet loopback

allow-hotplug wlp2s0
iface wlp2s0 inet dhcp
	wpa-ssid Home Network
	wpa-psk  "correct horse"
X
before=$fail
key=$nmdir/omakeb-wlp2s0.nmconnection
if run; then
  [[ "$(live)" == $'auto lo\niface lo inet loopback' ]] ||
    bad "wifi: unexpected live config left:"$'\n'"$(live)"
  grep -qx 'ssid=Home Network' "$key" 2>/dev/null || bad "wifi: ssid not carried over"
  grep -qx 'psk=correct horse' "$key" 2>/dev/null || bad "wifi: psk not carried over (quotes stripped?)"
  grep -qx 'interface-name=wlp2s0' "$key" 2>/dev/null || bad "wifi: interface-name missing"
  [[ "$(stat -c %a "$key" 2>/dev/null)" == 600 ]] || bad "wifi: keyfile is not 0600; NM ignores it otherwise"
else
  bad "wifi: failed under set -e: $(cat "$tmp/log")"
fi
(( fail == before )) && ok "a WPA-PSK stanza becomes a 0600 NM keyfile before it is commented out"

# --- 4. what must stay with ifupdown ------------------------------------------
fresh <<'X'
auto lo eth0 eth1
iface lo inet loopback

iface eth0 inet static
    address 192.0.2.10/24
    gateway 192.0.2.1

iface eth1 inet dhcp

allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
X
before=$fail
if run; then
  live | grep -qx 'iface eth0 inet static' || bad "static: eth0 was moved"
  live | grep -q 'address 192.0.2.10/24' || bad "static: eth0's options were commented out"
  live | grep -qx 'iface wlan0 inet dhcp' || bad "wpa-conf: wlan0 was moved"
  live | grep -qx 'allow-hotplug wlan0' || bad "wpa-conf: wlan0's allow-hotplug was removed"
  live | grep -qx 'auto lo eth0' || bad "shared auto line: expected 'auto lo eth0', got: $(live | grep '^auto')"
  live | grep -q 'eth1' && bad "eth1 (plain dhcp) was not handed over"
  grep -q 'leaving eth0' "$tmp/log" || bad "static: no warning that eth0 stays with ifupdown"
else
  bad "mixed: failed under set -e: $(cat "$tmp/log")"
fi
(( fail == before )) && ok "static, wpa-conf and shared auto lines are handled conservatively"

# --- 5. nothing to do ---------------------------------------------------------
fresh <<'X'
auto lo
iface lo inet loopback
X
cp "$ifile" "$tmp/lo"
before=$fail
run || bad "loopback-only: failed: $(cat "$tmp/log")"
cmp -s "$ifile" "$tmp/lo" || bad "loopback-only: file was rewritten"
[[ -e $ifile.omakeb-backup ]] && bad "loopback-only: backup written for no change"
(( fail == before )) && ok "a loopback-only file is left untouched"

rm -f "$ifile"
run || bad "missing file: failed: $(cat "$tmp/log")"

echo
(( fail )) && { echo "network handover: $fail failure(s)"; exit 1; }
echo "network handover checks passed"
