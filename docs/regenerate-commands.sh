#!/bin/bash
# Regenerate docs/commands.md from the metadata in bin/.
#
# Every command carries `# omakeb:summary=` (contract C1). Generating the
# reference from that is why the convention exists: a hand-written command list
# drifts the moment someone adds a script, and nothing notices.
#
# Run from the repo root after adding or renaming a command.

set -euo pipefail
cd "$(dirname "$0")/.."

group_of() {
  case "${1#omakeb-}" in
    launch-*|system-lock|system-lid) echo "Launching things" ;;
    menu*)                           echo "Menus and pickers" ;;
    theme-*|prompt-*)                echo "Themes" ;;
    install-app)                     echo "Optional software" ;;
    toggle-*|nightlight-apply)       echo "Toggles" ;;
    capture-*|clipboard)             echo "Capture and clipboard" ;;
    audio-*|brightness|hw-*)         echo "Hardware controls" ;;
    *)                               echo "Session internals" ;;
  esac
}

{
  cat <<'HEADER'
# Command reference

Every omakeb command lives in `bin/` and is on your `PATH`. This file is
generated from the `# omakeb:summary=` line in each script — run
`docs/regenerate-commands.sh` after adding one.

Commands marked *(internal)* are called by the session or the menu rather than
typed by hand.

HEADER

  for group in "Launching things" "Menus and pickers" "Themes" "Optional software" \
               "Toggles" "Capture and clipboard" "Hardware controls" "Session internals"; do
    first=1
    for f in bin/omakeb-*; do
      name=$(basename "$f")
      [[ "$(group_of "$name")" == "$group" ]] || continue
      if (( first )); then printf '## %s\n\n' "$group"; first=0; fi
      summary=$(sed -n 's/^# omakeb:summary=//p' "$f" | head -1)
      args=$(sed -n 's/^# omakeb:args=//p' "$f" | head -1)
      printf -- '- **`%s`**' "$name"
      [[ -n $args ]] && printf ' `%s`' "$args"
      printf ' — %s\n' "${summary:-(no summary)}"
    done
    (( first )) || printf '\n'
  done
} > docs/commands.md

echo "wrote docs/commands.md ($(grep -c '^- ' docs/commands.md) commands)"
