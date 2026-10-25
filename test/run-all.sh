#!/bin/bash
# Static checks. Safe to run on any host, including macOS — nothing here needs
# Debian, apt or a compositor.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
run() {
  local label=$1; shift
  echo
  echo "── $label ──"
  "$@" || fail=1
}

check_syntax() {
  shopt -s nullglob
  # macOS ships bash 3.2, where expanding an EMPTY array under `set -u` is an
  # error. With nullglob a glob that matches nothing yields exactly that, so
  # seed the array with a file that always exists.
  local files=(boot.sh install.sh lib/*.sh install/*.sh apps/*.sh test/*.sh test/vm/*.sh default/bash/*.sh bin/omakeb-*)
  local bad=0
  for f in "${files[@]}"; do
    [[ -f $f ]] || continue
    bash -n "$f" || { echo "  syntax error: $f"; bad=1; }
  done
  (( bad )) && return 1
  echo "${#files[@]} shell files parse"
}

run "shell syntax" check_syntax
run "hyprland bindings" python3 test/lint-bindings.py
run "architecture assumptions" ./test/lint-arch-assumptions.sh
run "debian release" ./test/lint-release.sh
run "binding references" ./test/check-binding-refs.sh
run "menu references" ./test/check-menu-refs.sh
run "menu icons" python3 test/lint-menu-icons.py
run "autostart daemons" python3 test/lint-autostart.py
run "session daemons" ./test/lint-session-daemons.sh
run "keyboard layout" ./test/lint-keyboard.sh
run "bashrc line" ./test/lint-shell.sh
run "monitor policy" ./test/lint-monitor.sh
run "session services" ./test/lint-services.sh
run "network handover" ./test/lint-network.sh
run "optional software" ./test/lint-apps.sh
run "migrations" ./test/lint-migrations.sh
run "fonts" python3 test/lint-fonts.py
run "audio" ./test/lint-audio.sh
run "nvidia support" ./test/lint-nvidia.sh
run "gl fallback cache" ./test/lint-gl-fallback.sh
run "screen recording" ./test/lint-screenrecording.sh
run "gtk stylesheet" python3 test/lint-gtk-css.py
run "theme pipeline" python3 test/lint-theme.py

echo
if (( fail )); then
  echo "FAILED"
  exit 1
fi
echo "all static checks passed"
