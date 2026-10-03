#!/bin/bash
# Static checks for bin/omakeb-monitor-apply.
#
# The policy is "best mode, and scale 2 above 4K", and every part of that has a
# way of being subtly wrong that looks fine on the machine you wrote it on:
#
#   * "best mode" has to break ties on refresh rate. The test machine's 8K panel
#     offers 7680x4320 at 59.94, 50 and 29.97. Picking the resolution and taking
#     whichever refresh comes first turns a fix into a regression nobody would
#     describe as one — the desktop is simply worse and still "8K".
#   * "above 4K" must not catch 4096x2160. DCI 4K has MORE pixels than
#     3840x2160 without being any more above 4K than it is, which is why the
#     threshold is a width and not a pixel count.
#   * a scale that does not divide the mode into whole logical pixels is
#     rejected by Hyprland, and a rejected rule leaves the output on whatever it
#     had — a silent no-op dressed as a success.
#   * the user's own `monitor =` rule has to win, and the COMMENTED examples in
#     the seeded config must not read as rules, or the policy would opt itself
#     out on every fresh install.
#
# Driven through a fake hyprctl, so no compositor is involved and this runs
# anywhere the rest of the suite does.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

SCRIPT_UNDER_TEST=bin/omakeb-monitor-apply
[[ -x $SCRIPT_UNDER_TEST ]] || { echo "  FAIL: $SCRIPT_UNDER_TEST missing or not executable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "  skip: jq is not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"

cat > "$tmp/bin/hyprctl" <<'FAKE'
#!/bin/bash
if [[ "${1:-}" == monitors && "${2:-}" == -j ]]; then
  cat "$FAKE_MONITORS"
  exit 0
fi
if [[ "${1:-}" == keyword && "${2:-}" == monitor ]]; then
  printf '%s\n' "$3" >> "$FAKE_CALLS"
  exit 0
fi
exit 0
FAKE
chmod +x "$tmp/bin/hyprctl"

# monitors_json <name> <cur_w> <cur_h> <cur_rr> <cur_scale> <mode...>
monitors_json() {
  local name=$1 w=$2 h=$3 rr=$4 sc=$5; shift 5
  local modes="" m
  for m in "$@"; do modes+="\"$m\","; done
  modes=${modes%,}
  printf '[{"name":"%s","width":%s,"height":%s,"refreshRate":%s,"scale":%s,"availableModes":[%s]}]\n' \
    "$name" "$w" "$h" "$rr" "$sc" "$modes"
}

# run <expected-rule-or-SKIP> <label> ; monitors json on stdin
run() {
  local want=$1 label=$2 got
  cat > "$tmp/monitors.json"
  : > "$tmp/calls"
  FAKE_MONITORS=$tmp/monitors.json FAKE_CALLS=$tmp/calls \
  OMAKEB_CONFIG=$tmp/config \
  PATH="$tmp/bin:$PATH" ./$SCRIPT_UNDER_TEST >/dev/null 2>&1
  got=$(cat "$tmp/calls")
  if [[ $want == SKIP ]]; then
    [[ -z $got ]] && ok "$label" || bad "$label: expected no change, got '$got'"
  else
    [[ $got == "$want" ]] && ok "$label" || bad "$label: expected '$want', got '${got:-<nothing>}'"
  fi
}

: > "$tmp/config/hyprland.conf"

# --- best mode: most pixels, then highest refresh -----------------------------
monitors_json DP-1 3840 2160 60 1 \
  "3840x2160@60.00Hz" "7680x4320@29.97Hz" "7680x4320@59.94Hz" "7680x4320@50.00Hz" |
  run "DP-1,7680x4320@59.94,auto,2" "8K panel: highest refresh among the 8K modes, scale 2"

monitors_json DP-1 3840 2160 60 1 \
  "3840x2160@60.00Hz" "3840x2160@119.88Hz" "1920x1080@60.00Hz" |
  run "DP-1,3840x2160@119.88,auto,auto" "4K panel: 4K120 chosen, scale left automatic"

# --- the "above 4K" threshold -------------------------------------------------
monitors_json DP-1 4096 2160 60 1 "4096x2160@60.00Hz" |
  run "SKIP" "DCI 4K (4096x2160) is not above 4K and is already current"

monitors_json DP-1 1920 1080 60 1 "4096x2160@60.00Hz" "1920x1080@60.00Hz" |
  run "DP-1,4096x2160@60,auto,auto" "DCI 4K keeps an automatic scale"

monitors_json DP-1 1920 1080 60 1 "5120x2880@60.00Hz" "1920x1080@60.00Hz" |
  run "DP-1,5120x2880@60,auto,2" "5K is above 4K and gets scale 2"

# --- a scale that would not divide cleanly ------------------------------------
monitors_json DP-1 1920 1080 60 1 "4098x2161@60.00Hz" "1920x1080@60.00Hz" |
  run "DP-1,4098x2161@60,auto,auto" "an odd mode above 4K falls back to an automatic scale"

# --- nothing to do ------------------------------------------------------------
monitors_json DP-1 7680 4320 59.94 2 "7680x4320@59.94Hz" "3840x2160@60.00Hz" |
  run "SKIP" "already on the best mode at the right scale: no rule emitted"

# --- the user's own rules win -------------------------------------------------
printf 'monitor = DP-1, 3840x2160@60, auto, 1\n' > "$tmp/config/hyprland.conf"
monitors_json DP-1 3840 2160 60 1 "7680x4320@59.94Hz" "3840x2160@60.00Hz" |
  run "SKIP" "a user rule naming the output is left alone"

printf 'monitor = , preferred, auto, 1\n' > "$tmp/config/hyprland.conf"
monitors_json DP-1 3840 2160 60 1 "7680x4320@59.94Hz" |
  run "SKIP" "a catch-all user rule opts out of the whole policy"

printf 'monitor = HDMI-A-1, preferred, auto, 1\n' > "$tmp/config/hyprland.conf"
monitors_json DP-1 3840 2160 60 1 "7680x4320@59.94Hz" "3840x2160@60.00Hz" |
  run "DP-1,7680x4320@59.94,auto,2" "a rule for another output does not shield this one"

# The seeded ~/.config/omakeb/hyprland.conf is mostly commented examples that
# name eDP-1 and DP-1. Reading those as rules would disable the policy on every
# fresh install, and it would look like it was working.
cat > "$tmp/config/hyprland.conf" <<'X'
# Monitors — `hyprctl monitors` prints the names:
#
#   monitor = eDP-1, preferred, 0x0, 1.5
#   monitor = DP-1, 2560x1440@144, 2560x0, 1
X
monitors_json DP-1 3840 2160 60 1 "7680x4320@59.94Hz" "3840x2160@60.00Hz" |
  run "DP-1,7680x4320@59.94,auto,2" "commented-out examples are not user rules"

# --- the session actually runs it ---------------------------------------------
grep -q '^exec-once = omakeb-monitor-apply$' default/hypr/autostart.conf ||
  bad "autostart.conf does not run omakeb-monitor-apply; the policy would never apply at login"
grep -q 'omakeb-monitor-apply' bin/omakeb-monitor-watch ||
  bad "omakeb-monitor-watch does not re-apply the policy after a hotplug"

echo
if (( fail )); then
  echo "monitor checks FAILED"
  exit 1
fi
echo "monitor checks passed"
