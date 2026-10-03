#!/bin/bash
# Every omakeb-* command the menu references must exist in bin/.
#
# Same failure mode as check-binding-refs.sh: nothing validates a menu action
# until someone selects that row and it silently does nothing. The menu is
# larger than the binding set and easier to let drift, so it gets its own check.
#
# Like the binding check, this is a ratchet — it fails only when the number of
# missing commands GROWS.

set -uo pipefail
cd "$(dirname "$0")/.."

BASELINE_FILE=test/menu-refs.baseline
baseline=$(cat "$BASELINE_FILE" 2>/dev/null || echo 0)

# --- duplicate keys ------------------------------------------------------------
#
# menu/menu.jsonc is JSON, so a repeated key is not an error: the last one wins
# and the earlier row vanishes with nothing said. That is not hypothetical —
# adding the audio-troubleshooting rows introduced a second "setup.audio.mixer"
# that would have silently replaced the pavucontrol row with alsamixer, and
# every other check here passed.
dups=$(grep -oE '^[[:space:]]*"[a-z0-9.]+":' menu/menu.jsonc |
       tr -d ' "	:' | sort | uniq -d)
if [[ -n $dups ]]; then
  echo "duplicate keys in menu/menu.jsonc — the later row silently replaces the earlier:"
  printf '%s\n' "$dups" | sed 's/^/  /'
  exit 1
fi
echo "no duplicate menu keys"

missing=$(python3 - <<'PY'
import re, subprocess, json, sys, os
src = open('bin/omakeb-menu').read()
m = re.search(r"STRIP_PY='\n(.*?)\n'\n", src, re.S)
if not m:
    sys.exit("could not extract the JSONC stripper from bin/omakeb-menu")
open('/tmp/omakeb-strip.py', 'w').write(m.group(1))
r = subprocess.run([sys.executable, '/tmp/omakeb-strip.py', 'menu/menu.jsonc'],
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("menu/menu.jsonc does not parse: " + r.stderr.strip())
data = json.loads(r.stdout)
missing = set()
for row in data.values():
    if not isinstance(row, dict):
        continue
    for field in ('action', 'when', 'checked', 'disabled'):
        for cmd in re.findall(r'\bomakeb-[a-z0-9-]+', row.get(field) or ''):
            if not os.path.isfile('bin/' + cmd):
                missing.add(cmd)
for c in sorted(missing):
    print(c)
PY
) || { echo "$missing"; exit 1; }

count=$(printf '%s' "$missing" | grep -c . || true)

if (( count > baseline )); then
  echo "menu references to missing commands grew from $baseline to $count:"
  printf '%s\n' "$missing" | sed 's/^/  /'
  exit 1
fi
if (( count < baseline )); then
  echo "$count menu commands still unwritten (baseline was $baseline — progress)."
  echo "Lower the baseline:  echo $count > $BASELINE_FILE"
  [[ -n $missing ]] && printf '%s\n' "$missing" | sed 's/^/  /'
  exit 0
fi
if (( count == 0 )); then
  echo "all menu-referenced commands present"
else
  echo "$count menu commands not yet written (at baseline, not a regression):"
  printf '%s\n' "$missing" | sed 's/^/  /'
fi
