#!/bin/bash
# Every omakeb-* command a binding references must eventually exist in bin/.
# Hyprland does not validate exec targets, so a renamed script silently turns a
# key into a no-op.
#
# Most of these are not written yet, so this is a ratchet rather than a pass/fail
# gate: it fails if the number of missing commands GROWS. That keeps the suite
# green as a baseline — so a real regression is visible — while making it
# impossible to add a binding pointing at a script nobody ever writes.
#
# When you implement a command, run this and commit the lowered baseline.

set -uo pipefail
cd "$(dirname "$0")/.."

BASELINE_FILE=test/binding-refs.baseline
baseline=$(cat "$BASELINE_FILE" 2>/dev/null || echo 0)

missing=()
while read -r cmd; do
  case "$cmd" in
    omakeb-*) [[ -f "bin/$cmd" ]] || missing+=("$cmd") ;;
  esac
done < <(grep -ho 'exec, *[a-z0-9-]*' default/hypr/bindings/*.conf | sed 's/exec, *//' | sort -u)

count=${#missing[@]}

if (( count > baseline )); then
  echo "missing commands grew from $baseline to $count:"
  printf '  %s\n' "${missing[@]}"
  echo
  echo "A binding references a command that does not exist. Write it, or fix the binding."
  exit 1
fi

if (( count < baseline )); then
  echo "$count commands still unwritten (baseline was $baseline — progress)."
  echo "Lower the baseline:  echo $count > $BASELINE_FILE"
  printf '  %s\n' "${missing[@]}"
  exit 0
fi

if (( count == 0 )); then
  echo "all referenced commands present"
else
  echo "$count referenced commands not yet written (at baseline, not a regression):"
  printf '  %s\n' "${missing[@]}"
fi
