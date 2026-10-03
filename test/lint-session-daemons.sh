#!/bin/bash
# Behavioural checks for bin/omakeb-session-daemons.
#
# Static checks cannot reach this one. The script's whole job is to behave
# DIFFERENTLY depending on something no file records — how the session was
# launched — so the only way to check it is to run it against both worlds and
# look at what it started. And it has to be run the way Hyprland runs it: under
# `set -euo pipefail`, where an empty array or a failing test in the wrong place
# ends the script silently and the desktop comes up with no bar. That exact
# class of fault has already got through review twice in this repo
# (install/60-config.sh, install/80-services.sh).
#
# systemctl and omakeb-daemon are stubbed, so this needs no compositor, no
# systemd and no Debian — it runs on the same hosts as the rest of run-all.sh.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

SCRIPT=bin/omakeb-session-daemons
LIST=default/session-daemons.tsv
[[ -r $SCRIPT ]] || { echo "  FAIL: $SCRIPT is missing"; exit 1; }
[[ -r $LIST ]]   || { echo "  FAIL: $LIST is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- stubs --------------------------------------------------------------------
#
# The fake systemctl reads its answers from $STATES, a file of "unit state"
# lines. A unit with no line is "inactive"; an empty file with $NO_MANAGER set
# is a machine with no user manager at all.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/systemctl" <<'STUB'
#!/bin/bash
# usage seen from lib/units.sh and omakeb-session-daemons:
#   systemctl --user show-environment
#   systemctl --user show <unit> -p LoadState --value
#   systemctl --user is-active <unit>
#   systemctl --user stop <unit>
args=("$@")
[[ ${args[0]:-} == --user ]] && args=("${args[@]:1}")
case "${args[0]:-}" in
  show-environment)
    [[ -n ${NO_MANAGER:-} ]] && exit 1
    echo "LANG=C"; exit 0 ;;
  show)
    [[ -n ${NO_MANAGER:-} ]] && exit 1
    unit=${args[1]}
    if grep -q "^$unit " "$STATES" 2>/dev/null; then echo loaded; else echo "${UNLOADED_STATE:-not-found}"; fi
    exit 0 ;;
  is-active)
    [[ -n ${NO_MANAGER:-} ]] && exit 1
    unit=${args[1]}
    state=$(awk -v u="$unit" '$1 == u { print $2 }' "$STATES" 2>/dev/null)
    : "${state:=inactive}"
    echo "$state"
    [[ $state == active ]] ;;
  stop)
    echo "stop ${args[1]}" >> "$ACTIONS"; exit 0 ;;
esac
exit 0
STUB

cat > "$tmp/bin/omakeb-daemon" <<'STUB'
#!/bin/bash
echo "start $*" >> "$ACTIONS"
STUB
chmod +x "$tmp/bin/systemctl" "$tmp/bin/omakeb-daemon"

# --- runner -------------------------------------------------------------------
#
# A separate shell, errexit/nounset/pipefail on, exactly as Hyprland's
# `exec-once` shell and install.sh would have it. NOT `if ( set -e; ... )` —
# a command whose status is being tested has errexit suspended inside it, so
# that spelling would pass with the bugs present.
run() {
  : > "$tmp/actions"
  ACTIONS=$tmp/actions STATES=$tmp/states \
  NO_MANAGER=${NO_MANAGER:-} UNLOADED_STATE=${UNLOADED_STATE:-} \
  OMAKEB_DAEMON=$tmp/bin/omakeb-daemon \
  OMAKEB_NIGHTLIGHT_APPLY=/nonexistent \
  OMAKEB_STATE=$tmp/state \
  OMAKEB_SESSION_DAEMON_WAIT=${WAIT:-1} \
  PATH="$tmp/bin:$PATH" \
    bash -c 'set -euo pipefail; exec "$0"' "$PWD/$SCRIPT" >/dev/null 2>&1
}

actions() { sort "$tmp/actions" 2>/dev/null | tr '\n' ';' ; }

toggle_on()  { mkdir -p "$tmp/state/toggles"; : > "$tmp/state/toggles/$1"; }
toggle_off() { rm -f "$tmp/state/toggles/$1"; }

all_units=$(awk '!/^#/ && NF == 4 { print $2 }' "$LIST")
all_bins=$(awk  '!/^#/ && NF == 4 { print $3 }' "$LIST")

# --- 1. systemd session: every unit already up -> start nothing ---------------
: > "$tmp/states"
for u in $all_units; do echo "$u active" >> "$tmp/states"; done
rm -rf "$tmp/state"
before=$fail
run || bad "exited non-zero on a healthy systemd session"
[[ -s $tmp/actions ]] && bad "started something on a session where systemd already had all five: $(actions)"
(( fail == before )) && ok "uwsm session, all units active: starts nothing (the stacked-bar bug stays fixed)"

# --- 2. systemd session, units still starting -> still start nothing ----------
: > "$tmp/states"
for u in $all_units; do echo "$u activating" >> "$tmp/states"; done
rm -rf "$tmp/state"
before=$fail
run || bad "exited non-zero while units were activating"
[[ -s $tmp/actions ]] && bad "raced a unit that was still activating: $(actions)"
(( fail == before )) && ok "a unit that is 'activating' is a promise, not an absence"

# --- 3. no user manager at all -> we start all five ---------------------------
: > "$tmp/states"
rm -rf "$tmp/state"
before=$fail
NO_MANAGER=1 run || bad "exited non-zero with no systemd user manager"
for b in $all_bins; do
  grep -qx "start $b" "$tmp/actions" || bad "did not start $b on a session with no user manager"
done
(( fail == before )) && ok "bare session, no user manager: starts all five itself"

# --- 4. units loaded but never started (the fallback greetd path) -------------
#
# This is the case the old static autostart.conf got wrong: dpkg enabled the
# units, so they are loaded, but nothing reached graphical-session.target, so
# they never run. The session must not be left without a bar or a lock.
: > "$tmp/states"
rm -rf "$tmp/state"
before=$fail
UNLOADED_STATE=loaded WAIT=1 run || bad "exited non-zero on the loaded-but-inactive path"
for b in $all_bins; do
  grep -qx "start $b" "$tmp/actions" || bad "left $b unstarted on a session that never reached graphical-session.target"
done
(( fail == before )) && ok "greetd fallback: units loaded but inactive, all five started after the wait"

# --- 5. an off-toggle stops a unit systemd started ----------------------------
: > "$tmp/states"
for u in $all_units; do echo "$u active" >> "$tmp/states"; done
rm -rf "$tmp/state"; toggle_on bar-hidden
before=$fail
run || bad "exited non-zero with bar-hidden set on a systemd session"
grep -qx "stop waybar.service" "$tmp/actions" ||
  bad "bar-hidden did not stop the waybar unit systemd had started"
grep -q "^start waybar$" "$tmp/actions" && bad "started waybar despite bar-hidden"
(( fail == before )) && ok "bar-hidden on a systemd session stops the unit, and never starts it"

# --- 6. an off-toggle simply withholds the start on a bare session ------------
: > "$tmp/states"
rm -rf "$tmp/state"; toggle_on bar-hidden; toggle_on idle-inhibited
before=$fail
NO_MANAGER=1 run || bad "exited non-zero with toggles set on a bare session"
grep -q "^start waybar$" "$tmp/actions"   && bad "started waybar despite bar-hidden"
grep -q "^start hypridle$" "$tmp/actions" && bad "started hypridle despite idle-inhibited"
grep -qx "start mako" "$tmp/actions" ||
  bad "an unrelated toggle suppressed mako as well"
grep -q "^stop " "$tmp/actions" && bad "tried to stop a unit on a machine with no user manager"
(( fail == before )) && ok "bare session honours off-toggles by not starting, and stops nothing"

# --- 7. a comment-only or short row must not crash it -------------------------
#
# `set -u` plus a hand-edited list is how this script would die at session start,
# taking the whole desktop's bar with it and reporting nothing.
: > "$tmp/states"
rm -rf "$tmp/state"
printf '# comment only\n\nwaybar\twaybar.service\twaybar\n' > "$tmp/short.tsv"
before=$fail
ACTIONS=$tmp/actions STATES=$tmp/states NO_MANAGER=1 \
OMAKEB_DAEMON=$tmp/bin/omakeb-daemon OMAKEB_NIGHTLIGHT_APPLY=/nonexistent \
OMAKEB_STATE=$tmp/state OMAKEB_SESSION_DAEMONS=$tmp/short.tsv \
OMAKEB_SESSION_DAEMON_WAIT=1 PATH="$tmp/bin:$PATH" \
  bash -c 'set -euo pipefail; exec "$0"' "$PWD/$SCRIPT" >/dev/null 2>&1 ||
  bad "died on a row with no off-toggle column (set -u)"
(( fail == before )) && ok "a hand-edited row missing its last column does not kill the session"

echo
if (( fail )); then
  echo "session-daemon checks FAILED"
  exit 1
fi
echo "session-daemon checks passed"
