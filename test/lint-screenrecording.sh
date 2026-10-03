#!/bin/bash
# Behavioural checks for bin/omakeb-capture-screenrecording.
#
# It used to start wf-recorder with every byte of output thrown away and then
# announce "Recording" whether or not anything was recording. A bad codec, a
# missing portal or an output that had gone away all looked like success until
# stop found no file — and stop then said "Saved to ..." anyway. So:
#
#   * a wf-recorder that exits at once is reported, critically, with its error
#   * so is one that runs for a moment and then dies (the common shape)
#   * neither leaves the state key behind or claims "Recording"
#   * stop only says "Saved" when the file has something in it
#
# wf-recorder, setsid, pgrep, pkill and notify-send are stubbed, so this needs
# no compositor and runs on macOS like the rest of run-all.sh.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

SCRIPT=bin/omakeb-capture-screenrecording
[[ -r $SCRIPT ]] || { echo "  FAIL: $SCRIPT is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- stubs --------------------------------------------------------------------
#
# "Running" is a flag file: the fake wf-recorder creates it, pgrep tests it,
# pkill removes it. WF_MODE picks the behaviour:
#   ok     starts, writes a few bytes to the -f file
#   empty  starts, writes nothing (the file exists, zero bytes)
#   fail   prints an error and exits at once
#   late   starts, then dies 0.2 s later — alive at the first pgrep
mkdir -p "$tmp/bin"
cat > "$tmp/bin/wf-recorder" <<'STUB'
#!/bin/bash
out=
while (( $# )); do [[ $1 == -f ]] && out=$2; shift; done
case $WF_MODE in
  ok)    : > "$RUN_FLAG"; printf 'data' > "$out" ;;
  empty) : > "$RUN_FLAG"; : > "$out" ;;
  fail)  echo "selected region 0,0 1920x1080"; echo "Failed to find codec 'libx264'" >&2; exit 1 ;;
  late)  : > "$RUN_FLAG"; : > "$out"; echo "Using output DP-1"
         echo "wl_registry: portal went away" >&2
         ( sleep 0.2; rm -f "$RUN_FLAG" ) >/dev/null 2>&1 & ;;
esac
exit 0
STUB
cat > "$tmp/bin/setsid" <<'STUB'
#!/bin/bash
[[ ${1:-} == -f ]] && shift
exec "$@"
STUB
cat > "$tmp/bin/pgrep" <<'STUB'
#!/bin/bash
[[ -e $RUN_FLAG ]]
STUB
cat > "$tmp/bin/pkill" <<'STUB'
#!/bin/bash
rm -f "$RUN_FLAG"
STUB
cat > "$tmp/bin/notify-send" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
STUB
cat > "$tmp/bin/xdg-user-dir" <<'STUB'
#!/bin/bash
echo "$VIDEOS"
STUB
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/hyprctl"
printf '#!/bin/bash\ncat >/dev/null; exit 0\n' > "$tmp/bin/jq"
chmod +x "$tmp/bin/"*

# --- runner -------------------------------------------------------------------
#
# A separate shell under errexit/nounset/pipefail — never `if ( set -e; ... )`,
# which suspends errexit inside the thing being tested.
run() {
  : > "$tmp/calls"
  CALLS=$tmp/calls RUN_FLAG=$tmp/running WF_MODE=${WF_MODE:-ok} VIDEOS=$tmp/videos \
  HOME=$tmp/home OMAKEB_PATH="$PWD" OMAKEB_STATE=$tmp/state \
  OMAKEB_CONFIG=$tmp/config OMAKEB_CACHE=$tmp/cache \
  PATH="$tmp/bin:$PATH" \
    bash -c 'set -euo pipefail; exec "$0"' "$PWD/$SCRIPT" >/dev/null 2>&1
}
reset() { rm -rf "$tmp/state" "$tmp/videos" "$tmp/running"; }
said()     { grep -q -- "$1" "$tmp/calls"; }
critical() { grep -- "$1" "$tmp/calls" | grep -q -- '-u critical'; }
state_key=$tmp/state/screenrecording

# --- 1. wf-recorder exits at once ---------------------------------------------
before=$fail
reset
WF_MODE=fail run && bad "exited 0 although wf-recorder did not start"
said 'Recording' && bad "announced 'Recording' for a wf-recorder that exited immediately"
critical "Failed to find codec 'libx264'" ||
  bad "no critical notification carrying wf-recorder's last line: $(cat "$tmp/calls")"
[[ -e $state_key ]] && bad "left the state key naming a recording that never started"
[[ -s $tmp/state/screenrecording.log ]] || bad "wf-recorder's output was not kept in screenrecording.log"
(( fail == before )) && ok "immediate failure: critical notice with the error, no state left behind"

# --- 2. wf-recorder runs briefly, then dies -----------------------------------
before=$fail
reset
WF_MODE=late run && bad "exited 0 although wf-recorder died within 0.2 s"
said 'Recording' && bad "announced 'Recording' for a wf-recorder that died a moment after starting"
critical 'portal went away' || bad "late failure not reported with its error: $(cat "$tmp/calls")"
[[ -e $state_key ]] && bad "late failure left the state key behind"
ls "$tmp/videos/Screenrecordings/"*.mp4 >/dev/null 2>&1 &&
  bad "late failure left an empty .mp4 behind"
(( fail == before )) && ok "failure a moment after start is caught too (a single early pgrep would miss it)"

# --- 3. a real start ----------------------------------------------------------
before=$fail
reset
WF_MODE=ok run || bad "exited non-zero on a successful start"
said 'Recording' || bad "did not announce 'Recording' on a successful start"
[[ -s $state_key ]] || bad "did not record the output file in state"
(( fail == before )) && ok "successful start: state recorded, 'Recording' announced"

# --- 4. stop with a real file -------------------------------------------------
before=$fail
file=$(cat "$state_key" 2>/dev/null)
run || bad "stop exited non-zero"
said 'Saved to' || bad "stop did not report the saved file"
[[ -e $state_key ]] && bad "stop left the state key behind"
[[ -e $tmp/running ]] && bad "stop did not stop wf-recorder"
(( fail == before )) && ok "stop with a non-empty file: 'Saved to ...'"

# --- 5. stop with an empty file -----------------------------------------------
before=$fail
reset
WF_MODE=empty run || bad "exited non-zero starting the empty-file case"
run
said 'Saved to' && bad "said 'Saved' for a zero-byte file"
critical 'nothing was saved' || bad "stop did not warn that the file is empty: $(cat "$tmp/calls")"
(( fail == before )) && ok "stop with a zero-byte file: critical 'nothing was saved', not 'Saved'"

# --- 6. stop with the file gone -----------------------------------------------
before=$fail
reset
WF_MODE=ok run
rm -f "$(cat "$state_key")"
run
said 'Saved to' && bad "said 'Saved' for a file that does not exist"
critical 'nothing was saved' || bad "stop did not warn that the file is missing"
(( fail == before )) && ok "stop with the file missing: critical 'nothing was saved'"

echo
if (( fail )); then
  echo "screen recording checks FAILED ($fail)"
  exit 1
fi
echo "screen recording checks passed"
