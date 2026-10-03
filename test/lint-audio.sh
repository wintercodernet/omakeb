#!/bin/bash
# omakeb-hw-audio: does it find silent audio, and does it stay quiet otherwise?
#
# This check exists for the fault it was written from — a machine where the
# volume meter moved, the correct device was selected, and the headphones were
# silent, because the ALSA hardware mixer underneath was muted and nothing in
# the desktop displays that layer.
#
# Two failure directions matter equally:
#
#   MISSES. The check reports a healthy machine when audio is inaudible. That
#   is the original bug wearing a badge.
#
#   FALSE ALARMS. With headphones plugged in, PipeWire deliberately mutes the
#   line-out path, so `Front` and `Speaker` sit at [off] on a perfectly working
#   machine. A check that reports those is red on every healthy desktop, and a
#   permanently red check is one people learn to ignore.
#   Case 1 below is the guard for that, and it is the
#   reason the mixer scan is route-aware rather than exhaustive.
#
# Everything is driven from fixtures through OMAKEB_PW_DUMP / OMAKEB_AMIXER.
# Nothing here reads the sound card of the machine running the tests — which is
# the mistake test/lint-nvidia.sh made and that only showed up on the one
# machine that had the hardware (fact 35).

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

command -v jq >/dev/null 2>&1 || { echo "  SKIP: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export OMAKEB_PATH="$PWD"
export OMAKEB_STATE="$tmp/state" OMAKEB_CONFIG="$tmp/config" OMAKEB_CACHE="$tmp/cache"
export XDG_CONFIG_HOME="$tmp/config"
export HOME="$tmp"

# --- fake pw-dump: prints whichever fixture FIXTURE names ---------------------
cat > "$tmp/bin/pw-dump" <<'FAKE'
#!/bin/bash
cat "$FIXTURE"
FAKE

# --- fake amixer: canned control state from MIXER ------------------------------
#
# MIXER is "Control:pct:state,..." — the same shape amixer reports, including a
# control with no mute switch (state "-"), which is how PCM presents.
cat > "$tmp/bin/amixer" <<'FAKE'
#!/bin/bash
ctl=""
while [ $# -gt 0 ]; do
  case "$1" in sget) ctl=$2; shift 2 ;; *) shift ;; esac
done
IFS=',' read -ra entries <<< "${MIXER:-}"
for e in "${entries[@]}"; do
  IFS=':' read -r name pct state <<< "$e"
  if [ "$name" = "$ctl" ]; then
    echo "Simple mixer control '$name',0"
    echo "  Playback channels: Front Left - Front Right"
    echo "  Mono:"
    if [ "$state" = "-" ]; then
      echo "  Front Left: Playback 87 [${pct}%] [0.00dB]"
    else
      echo "  Front Left: Playback 87 [${pct}%] [0.00dB] [$state]"
    fi
    exit 0
  fi
done
exit 1
FAKE
chmod +x "$tmp/bin/pw-dump" "$tmp/bin/amixer"
export PATH="$tmp/bin:$PATH"
export OMAKEB_PW_DUMP=pw-dump OMAKEB_AMIXER=amixer OMAKEB_WPCTL=true

run_check() {
  FIXTURE="$PWD/test/fixtures/audio/$1.json" MIXER="$2" \
    bash bin/omakeb-hw-audio 2>&1
}

# --- 1. healthy, with the line-out path deliberately muted --------------------
#     THE FALSE-ALARM GUARD. Front is [off] because headphones are selected.
out=$(FIXTURE="$PWD/test/fixtures/audio/healthy.json" \
      MIXER="Master:89:on,PCM:100:-,Headphone:100:on,Front:100:off,Speaker:0:off" \
      bash bin/omakeb-hw-audio 2>&1); rc=$?
if (( rc == 0 )) && ! grep -q "FAIL\|problem" <<<"$out"; then
  ok "a healthy machine reports nothing, even with the line-out path muted"
else
  bad "false alarm on a healthy machine (exit $rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
if grep -qi "'Front'\|'Speaker'" <<<"$out"; then
  bad "reported the inactive line-out path; the mixer scan is not route-aware"
else
  ok "the inactive line-out path is not reported"
fi

# --- 2. the original fault: hardware mixer muted under a working stream -------
out=$(run_check healthy "Master:0:off,PCM:100:-,Headphone:0:off"); rc=$?
if (( rc != 0 )) && grep -q "MUTED" <<<"$out"; then
  ok "a muted ALSA Master under a working PipeWire sink is caught"
else
  bad "missed the muted hardware mixer (exit $rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
grep -q "moving meter and no sound" <<<"$out" &&
  ok "the report names the symptom the user actually sees" ||
  bad "the report does not connect the mute to the observed symptom"

# --- 3. Master audible but the route's own control muted ----------------------
out=$(run_check healthy "Master:89:on,PCM:100:-,Headphone:0:off"); rc=$?
if (( rc != 0 )) && grep -q "Headphone" <<<"$out"; then
  ok "a muted Headphone control is caught even when Master is fine"
else
  bad "missed a mute on the active route's own control (exit $rc)"
fi

# --- 4. a shared control at zero is silence too -------------------------------
out=$(run_check healthy "Master:89:on,PCM:0:-,Headphone:100:on"); rc=$?
if (( rc != 0 )) && grep -q "PCM" <<<"$out"; then
  ok "a switchless control at 0% is reported as silence"
else
  bad "missed PCM at 0% (exit $rc)"
fi

# --- 5. the self-sustaining card-Off fault ------------------------------------
out=$(run_check card-off "Master:89:on,PCM:100:-"); rc=$?
if (( rc != 0 )) && grep -qi "switched Off" <<<"$out"; then
  ok "a card stuck in the Off profile is caught"
else
  bad "missed the card stuck Off (exit $rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# --- 6. no outputs at all -----------------------------------------------------
out=$(run_check no-sinks "Master:89:on"); rc=$?
if (( rc != 0 )) && grep -qi "no audio outputs" <<<"$out"; then
  ok "a machine with no audio outputs is caught"
else
  bad "missed having no outputs at all (exit $rc)"
fi

# --- 7. a PipeWire-level mute ---------------------------------------------------
out=$(run_check pw-muted "Master:89:on,PCM:100:-,Headphone:100:on"); rc=$?
if (( rc != 0 )) && grep -qi "muted in PipeWire" <<<"$out"; then
  ok "a PipeWire-level mute is caught"
else
  bad "missed a PipeWire-level mute (exit $rc)"
fi

# --- 8. fix without --yes must change nothing ---------------------------------
before=$(find "$tmp/config" -type f 2>/dev/null | sort)
out=$(FIXTURE="$PWD/test/fixtures/audio/card-off.json" MIXER="Master:0:off,PCM:100:-" \
      bash bin/omakeb-hw-audio fix 2>&1)
after=$(find "$tmp/config" -type f 2>/dev/null | sort)
if [[ "$before" == "$after" ]] && grep -q "would " <<<"$out" && grep -q "Nothing was changed" <<<"$out"; then
  ok "'fix' without --yes reports what it would do and writes nothing"
else
  bad "'fix' without --yes was not inert"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# --- 9. the profile is chosen by name, never by a hardcoded index -------------
#     Profile numbering differs between codecs, so an index that is "Analog
#     Stereo Output" on one machine is something else entirely on another.
if grep -q 'select(.description|test("Analog Stereo Output' bin/omakeb-hw-audio &&
   ! grep -qE 'set-profile "\$id" [0-9]' bin/omakeb-hw-audio; then
  ok "the analog profile is resolved by description, not a fixed index"
else
  bad "an output profile index looks hardcoded; it is not portable between codecs"
fi

echo
if (( fail )); then
  echo "$fail audio check(s) failed"
  exit 1
fi
echo "audio: all checks passed"
