#!/bin/bash
# The Debian release omakeb targets: one name, and what happens off it.
#
# Three failures this is about, all of which have happened or were one edit
# away:
#
#   1. The codename spelled out as an apt suite somewhere other than
#      lib/release.sh. Every such copy has to change together when omakeb moves
#      release, and the one that is missed writes a suite for the wrong release
#      onto somebody's machine without a word.
#   2. install/10-sources.sh writing trixie-backports onto a machine that is not
#      running trixie (sid, forky), where it is at best useless and at worst
#      makes the pin check die on a machine that is fine.
#   3. bin/omakeb-update checking for release drift after converge, which on a
#      drifted machine it never reached, because converge died first.
#
# Behaviour is checked by extracting the real code and running it against
# stubs, each case in its own `bash -c` with `set -euo pipefail` and the status
# read afterwards. Not `if ( set -e; ... )`: errexit is
# suspended inside a tested command and the check passes with the bug present.
#
# macOS bash 3.2 runs this. No mapfile, no empty-array expansion under set -u.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

codename=$(sed -n 's/^OMAKEB_DEBIAN_CODENAME=//p' lib/release.sh)
if [[ -z $codename ]]; then
  bad "lib/release.sh does not define OMAKEB_DEBIAN_CODENAME"
  exit 1
fi

# --- 1. one name ---------------------------------------------------------------
#
# A suite-shaped use: the codename alone or with a -backports/-updates/-security
# suffix, on a line that is not a comment and not a log message. A codename in
# prose ("Debian trixie has node 20") is not a suite and reaches no apt file;
# the bug class is a name that ends up in sources, a pin or `-t`.
#
# apps/ is out of scope on purpose: a third-party repository's suite is whatever
# that vendor publishes (Docker's "trixie stable", Microsoft's ".../debian/13"),
# a fact about the vendor rather than a second copy of ours.
hits=$(grep -rnwE --include='*.sh' "$codename(-backports|-updates|-security)?" \
         boot.sh install.sh lib install 2>/dev/null
       grep -nwE "$codename(-backports|-updates|-security)?" bin/omakeb-* 2>/dev/null \
         | sed 's/^/bin:/')
hits=$(printf '%s\n' "$hits" \
  | grep -v '^lib/release.sh:' \
  | grep -vE '^[^:]+:([^:]+:)?[0-9]+:[[:space:]]*#' \
  | grep -vE '(log_[a-z]+|die)[[:space:]]+"' \
  | sed '/^$/d')
if [[ -n $hits ]]; then
  bad "the codename '$codename' is spelled out as a suite outside lib/release.sh:"
  printf '%s\n' "$hits" | sed 's/^/        /'
  echo "        Use \$OMAKEB_DEBIAN_CODENAME or \$OMAKEB_BACKPORTS_SUITE."
else
  ok "'$codename' appears as a suite only in lib/release.sh"
fi

# --- release_codename / release_stale_suites -----------------------------------
mk_os() { printf 'ID=debian\nVERSION_CODENAME=%s\n' "$1" > "$tmp/os-release"; }
mk_src() {  # mk_src <file> <suites line>...
  local f=$1; shift
  : > "$f"
  for s in "$@"; do printf 'Types: deb\nSuites: %s\nComponents: main\n\n' "$s" >> "$f"; done
}

stale() {  # stale <expect: clean|drift> <label> <files>...
  local want=$1 label=$2 out rc; shift 2
  out=$(OMAKEB_OS_RELEASE="$tmp/os-release" bash -c '
    set -euo pipefail
    source lib/release.sh
    release_stale_suites "$@"
  ' _ "$@")
  rc=$?
  if (( rc != 0 )); then
    bad "$label: release_stale_suites exited $rc under set -e"
  elif [[ $want == clean && -z $out ]] || [[ $want == drift && -n $out ]]; then
    ok "$label"
  else
    bad "$label: expected $want, got '${out:-nothing}'"
  fi
}

bp="$tmp/omakeb-backports.sources"
comp="$tmp/omakeb-components.sources"

mk_os "$codename"
mk_src "$bp" "$codename-backports"
mk_src "$comp" "$codename $codename-updates" "$codename-security"
stale clean "target release with omakeb's own files is not drift" "$bp" "$comp"

mk_os forky
stale drift "a machine moved to forky with $codename-backports is drift" "$bp"
stale drift "a machine moved to forky with a $codename components file is drift" "$comp"
rm -f "$bp" "$comp"
stale clean "a sid/forky machine installed without backports is not drift" "$bp" "$comp"

rm -f "$tmp/os-release"
out=$(OMAKEB_OS_RELEASE="$tmp/os-release" bash -c '
  set -euo pipefail
  source lib/release.sh
  c=$(release_codename)
  echo "reached:$c"
')
[[ $out == "reached:" ]] \
  && ok "a missing os-release gives an empty codename and does not end a set -e caller" \
  || bad "release_codename with no os-release: got '$out'"

# --- 2. 10-sources.sh gates backports on the running release -------------------
#
# The block between `_running_codename=` and `unset _running_codename`, run
# against stubs. The rest of the step needs apt and mapfile, neither of which
# this host has, and neither of which is what is being tested.
block=$(sed -n '/^_running_codename=/,/^unset _running_codename/p' install/10-sources.sh)
if [[ -z $block ]]; then
  bad "install/10-sources.sh: could not find the backports block (_running_codename= ... unset)"
else
  printf '%s\n' "$block" > "$tmp/block.sh"
  sources_case() {  # sources_case <os codename> <release arch? 0|1> <expect BACKPORTS> <label>
    local out
    mk_os "$1"
    out=$(OMAKEB_OS_RELEASE="$tmp/os-release" RELEASE_ARCH=$2 bash -c '
      set -euo pipefail
      source lib/log.sh
      source lib/release.sh
      arch_is_release_arch() { (( RELEASE_ARCH )); }
      arch_dpkg() { echo testarch; }
      write_file_sudo() { cat >/dev/null; echo "WROTE $1"; }
      source "$1"
      echo "BACKPORTS=$OMAKEB_BACKPORTS"
    ' _ "$tmp/block.sh" 2>/dev/null)
    local wrote=0 good=0
    grep -q '^WROTE .*omakeb-backports' <<<"$out" && wrote=1
    grep -q "^BACKPORTS=$3\$" <<<"$out" && (( wrote == $3 )) && good=1
    if (( good )); then
      ok "$4"
    else
      bad "$4: got: $(tr '\n' ' ' <<<"$out")"
    fi
  }
  sources_case "$codename" 1 1 "10-sources: $codename on a release arch writes backports"
  sources_case forky        1 0 "10-sources: forky skips backports and writes nothing"
  sources_case ""           1 0 "10-sources: an unknown codename skips backports"
  sources_case "$codename" 0 0 "10-sources: a debian-ports arch skips backports"
fi

# --- _components_write refuses another release ---------------------------------
fn=$(sed -n '/^_components_write() {/,/^}/p' lib/apps.sh)
printf '%s\n' "$fn" > "$tmp/components.sh"
components_case() {  # components_case <os codename> <expect: write|refuse> <label>
  local out rc
  mk_os "$1"
  out=$(OMAKEB_OS_RELEASE="$tmp/os-release" bash -c '
    set -uo pipefail
    source lib/log.sh
    source lib/release.sh
    OMAKEB_COMPONENTS_SOURCE=/nonexistent
    sudo() { return 1; }
    apt_refresh() { :; }
    write_file_sudo() { cat; }
    source "$1"
    _components_write contrib
  ' _ "$tmp/components.sh" 2>/dev/null)
  rc=$?
  case $2 in
    write)  (( rc == 0 )) && grep -q "^Suites: $codename $codename-updates\$" <<<"$out" \
              && grep -q "^Suites: $codename-security\$" <<<"$out" ;;
    refuse) (( rc != 0 )) && ! grep -q '^Suites:' <<<"$out" ;;
  esac && ok "$3" || bad "$3 (rc=$rc)"
}
components_case "$codename" write  "components source names the $codename suites on $codename"
components_case forky        refuse "components source is refused, not written, on forky"

# --- 3. omakeb-update checks drift before converging ---------------------------
#
# Line order is the property: after the re-exec (so the pulled code judges the
# machine) and before the converge loop (so 10-sources.sh cannot die first).
u=bin/omakeb-update
exec_line=$(grep -n 'exec bash "\$OMAKEB_PATH/bin/omakeb-update"' "$u" | tail -1 | cut -d: -f1)
drift_line=$(grep -n '^release_drift=\$(release_stale_suites' "$u" | head -1 | cut -d: -f1)
loop_line=$(grep -n 'for step in "\$OMAKEB_PATH"/install/' "$u" | head -1 | cut -d: -f1)
if [[ -z $drift_line || -z $exec_line || -z $loop_line ]]; then
  bad "$u: could not locate the re-exec, the drift check or the converge loop"
elif (( exec_line < drift_line && drift_line < loop_line )); then
  ok "omakeb-update checks release drift after the re-exec and before converge"
else
  bad "$u: drift check at line $drift_line is not between the re-exec ($exec_line) and converge ($loop_line)"
fi
grep -q 'do_converge=$' "$u" && grep -q 'skipped_for_drift=1' "$u" \
  && ok "drift turns converge off" \
  || bad "$u: drift does not skip converge"
if grep -A30 'if \[\[ -n \$release_drift \]\]' "$u" | grep -q 're-run install.sh'; then
  bad "$u: drift advice tells the user to re-run install.sh, which preflight refuses off Debian 13"
else
  ok "drift advice does not send the user to install.sh"
fi

# --- portal preferences live in /etc -------------------------------------------
if grep -q 'write_file_sudo /usr/share/xdg-desktop-portal/' install/*.sh; then
  bad "portal preferences are written into package-owned /usr/share"
elif grep -q 'write_file_sudo /etc/xdg-desktop-portal/hyprland-portals.conf' install/30-desktop.sh; then
  ok "portal preferences are written to /etc/xdg-desktop-portal"
else
  bad "install/30-desktop.sh no longer writes /etc/xdg-desktop-portal/hyprland-portals.conf"
fi

echo
if (( fail )); then
  echo "$fail release check(s) failed"
  exit 1
fi
echo "release handling is consistent"
