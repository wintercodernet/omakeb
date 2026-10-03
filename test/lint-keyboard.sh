#!/bin/bash
# Static checks for the keyboard block install/60-config.sh renders.
#
# Debian records the keyboard the user chose at install time in
# /etc/default/keyboard. Hyprland does not read it, so we translate it into
# hyprlang. Everything about that translation is easy to get quietly wrong, and
# the symptom is always the same and always remote: someone types their password
# into hyprlock on the wrong layout.
#
#   * every XKB value must survive, not just the layout. The first version of
#     this used one `read a b c d` on four lines of input, which takes only the
#     FIRST line and splits it into four — so kb_model, kb_variant and
#     kb_options silently vanished and the file still looked plausible.
#   * hyprlang truncates a line at an unescaped '#'. Nothing in an XKB value has
#     ever contained one, but this is generated from a file outside our control.
#   * the file must exist even with nothing to say. hyprlang treats a missing
#     `source =` target as a config error, which is a broken session, not a
#     warning.
#
# Runs anywhere: the function is extracted and fed fixtures, so no Debian, no
# /etc/default/keyboard and no compositor are involved.

set -uo pipefail
cd "$(dirname "$0")/.."

# A COUNTER, not a flag. The per-group "did this group pass" checks below
# compare it against its value before the group ran; with a flag that only ever
# goes 0 -> 1, every group after the first failure compares 1 against 1 and
# cheerfully reports itself as passing.
fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

STEP=install/60-config.sh
[[ -r $STEP ]] || { echo "  FAIL: $STEP is missing"; exit 1; }

# --- load just the renderer ---------------------------------------------------
# It needs write_file and the log_* helpers, and a config_home to write into.
source lib/log.sh
source lib/guard.sh

# The renderer names the checkout in its guidance, and lib/all.sh always has
# this set in the real installer. Under `set -u` an unset one would abort the
# render rather than produce a wrong file, but the test should mirror reality.
OMAKEB_PATH=$(pwd)

fn=$(sed -n '/^render_keyboard_conf() {/,/^}/p' "$STEP")
[[ -n $fn ]] || { echo "  FAIL: render_keyboard_conf not found in $STEP"; exit 1; }
eval "$fn"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
config_home=$tmpdir/config
out=$config_home/hypr/keyboard.conf

# render <fixture-content>; empty content means "no file at all"
render() {
  local kb=$tmpdir/keyboard
  rm -f "$out"
  if [[ -n ${1:-} ]]; then
    printf '%s' "$1" > "$kb"
    OMAKEB_KEYBOARD_FILE=$kb render_keyboard_conf >/dev/null 2>&1
  else
    OMAKEB_KEYBOARD_FILE=$tmpdir/absent render_keyboard_conf >/dev/null 2>&1
  fi
}

has()     { grep -qF "    $1" "$out" || bad "$2: expected '$1'"; }
lacks()   { grep -qF "    $1" "$out" && bad "$2: did not expect '$1'"; return 0; }

# --- 1. every value is carried across, not just the layout --------------------
render 'XKBMODEL="pc105"
XKBLAYOUT="se"
XKBVARIANT="nodeadkeys"
XKBOPTIONS="caps:escape"
'
before=$fail
has "kb_layout = se"           "all four values"
has "kb_variant = nodeadkeys"  "all four values"
has "kb_model = pc105"         "all four values"
has "kb_options = caps:escape" "all four values"
(( fail == before )) && ok "layout, variant, model and options all survive the render"

# --- 2. an unset value is omitted rather than written empty -------------------
render 'XKBLAYOUT="se"
XKBVARIANT=""
XKBOPTIONS=""
'
before=$fail
has   "kb_layout = se" "empty values"
lacks "kb_variant ="   "empty values"
lacks "kb_options ="   "empty values"
(( fail == before )) && ok "an empty XKB value is omitted, not written as a blank setting"

# --- 3. multi-layout survives its comma ---------------------------------------
render 'XKBLAYOUT="se,us"
XKBOPTIONS="grp:alt_shift_toggle"
'
before=$fail
has "kb_layout = se,us" "multi-layout"
has "kb_options = grp:alt_shift_toggle" "multi-layout"
(( fail == before )) && ok "a two-layout setup keeps both layouts and its switch key"

# --- 4. the hyprlang hash trap ------------------------------------------------
render 'XKBLAYOUT="se"
XKBOPTIONS="weird#opt"
'
if grep -qF 'kb_options = weird##opt' "$out"; then
  ok "a '#' in a value is escaped to '##' so hyprlang cannot truncate the line"
else
  bad "hash trap: '#' in an XKB value was not escaped"
fi

# --- 5. a missing or empty source file still yields a parseable file -----------
render ''
if [[ -f $out ]]; then
  before=$fail
  grep -q '^input {' "$out" && bad "no keyboard file: must not emit an input block"
  (( fail == before )) && ok "with no /etc/default/keyboard the file still exists and sets nothing"
else
  bad "no keyboard file: keyboard.conf was not written at all (hyprlang errors on a missing source)"
fi

render 'XKBMODEL=""
XKBLAYOUT=""
'
before=$fail
[[ -f $out ]] || bad "empty XKB values: keyboard.conf was not written"
grep -q '^input {' "$out" && bad "empty XKB values: must not emit an empty input block"
(( fail == before )) && ok "a file that sets no XKB values is treated the same as no file"

# --- 5b. it must survive `set -e`, which is how the installer runs it ---------
#
# install.sh runs `set -euo pipefail`. Under that, `[[ -n $x ]] && y=...` with an
# EMPTY $x is a statement returning non-zero, and the whole installer dies. The
# first version of this renderer used exactly that for kb_variant and
# kb_options, and XKBVARIANT="" / XKBOPTIONS="" is the normal content of
# /etc/default/keyboard — so the common case was the fatal one. A real install
# died at 60-config having written nothing, and no test noticed, because every
# test ran the function WITHOUT set -e.
#
# Run in a SEPARATE shell, not `if ( set -e; ... )`. A command whose status is
# being tested — which is what the `if` makes it — has errexit suspended inside
# it, so that spelling passes even with the bug present. It was written that way
# first and duly reported the bug as fixed.
sete_runner=$tmpdir/run-under-errexit.sh
cat > "$sete_runner" <<'RUNNER'
#!/bin/bash
set -euo pipefail
cd "$1"
# Exactly what install.sh establishes before it sources a step: errexit,
# nounset, pipefail, and OMAKEB_PATH exported. The renderer names the checkout
# in its guidance, so under `set -u` an unset OMAKEB_PATH is itself fatal.
export OMAKEB_PATH="$1"
source lib/log.sh
source lib/guard.sh
config_home=$2
eval "$(sed -n '/^render_keyboard_conf() {/,/^}/p' install/60-config.sh)"
render_keyboard_conf
RUNNER
chmod +x "$sete_runner"

sete_case() {
  local label=$1 fixture=$2 kb=$tmpdir/keyboard-sete
  if [[ -n $fixture ]]; then printf '%s' "$fixture" > "$kb"; else kb=$tmpdir/absent-sete; fi
  rm -f "$out"
  if OMAKEB_KEYBOARD_FILE=$kb bash "$sete_runner" "$PWD" "$config_home" >/dev/null 2>&1; then
    ok "renders under 'set -euo pipefail': $label"
  else
    bad "render_keyboard_conf fails under set -e ($label) — this aborts install.sh"
  fi
}

# The ordinary machine: a layout and a model, with variant and options empty.
sete_case "empty variant and options (the usual /etc/default/keyboard)" 'XKBMODEL="pc105"
XKBLAYOUT="se"
XKBVARIANT=""
XKBOPTIONS=""
'
sete_case "every value populated" 'XKBMODEL="pc105"
XKBLAYOUT="se"
XKBVARIANT="nodeadkeys"
XKBOPTIONS="caps:escape"
'
sete_case "no keyboard file at all" ''

# --- 6. the guidance names BOTH halves of a system-wide layout change ---------
#
# dpkg-reconfigure alone changes the console and the greeter immediately, but
# this file is only rewritten by the installer — so Hyprland silently keeps the
# old layout until that runs too. Telling someone only the first half sends them
# to a half-changed machine, which is worse than saying nothing.
for fixture in 'XKBLAYOUT="se"
' ''; do
  render "$fixture"
  case $fixture in
    ?*) label="with a layout set" ;;
    *)  label="with no keyboard file" ;;
  esac
  before=$fail
  grep -q 'dpkg-reconfigure keyboard-configuration' "$out" ||
    bad "$label: guidance does not mention dpkg-reconfigure"
  grep -q 'install\.sh' "$out" ||
    bad "$label: guidance does not say to re-run the installer"
  (( fail == before )) && ok "$label: guidance covers dpkg-reconfigure AND the installer re-run"
done

# --- 7. the entry point actually sources what we render -----------------------
if grep -qF 'source = @CONFIG_HOME@/hypr/keyboard.conf' default/hypr/hyprland.conf.in; then
  ok "hyprland.conf.in sources the rendered keyboard.conf"
else
  bad "hyprland.conf.in does not source keyboard.conf; the render would be dead code"
fi

# Our block has to beat default/hypr/input.conf and lose to the user's own file.
# Anchored to real `source =` directives: the surrounding comments name these
# same files, and matching one of those compares the wrong line numbers.
line_of() { grep -n "^source = $1\$" default/hypr/hyprland.conf.in | cut -d: -f1; }
order="$(line_of '@OMAKEB_PATH@/default/hypr/input.conf') \
        $(line_of '@CONFIG_HOME@/hypr/keyboard.conf') \
        $(line_of '@OMAKEB_CONFIG@/hyprland.conf')"
set -- $order
if [[ $# -eq 3 ]] && (( $1 < $2 && $2 < $3 )); then
  ok "sourced after our input.conf and before the user's hyprland.conf"
else
  bad "source order is wrong (input.conf, keyboard.conf, user conf at lines: $order)"
fi

echo
if (( fail )); then
  echo "keyboard checks FAILED"
  exit 1
fi
echo "keyboard checks passed"
