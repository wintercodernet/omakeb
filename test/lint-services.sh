#!/bin/bash
# Static checks for the mako D-Bus reconciliation in install/80-services.sh.
#
# Two things to hold down, and the second one is why this file exists at all:
#
#   * the override must carry SystemdService= and copy Name/Exec from the
#     packaged file rather than hardcoding them. A shadow file pointing at a
#     path the binary has moved away from is worse than no shadow at all.
#
#   * it has to survive `set -euo pipefail`, because that is how install.sh runs
#     every step it sources. Two separate faults in this area got through code
#     review and a full static suite and were only caught by running the real
#     installer: a `sed -n 's///p' | head -1` whose SIGPIPE becomes a fatal 141
#     under pipefail, and a `sed -n 's/^Name=//{p;q;}'` that GNU sed rejects
#     outright. Neither is visible unless the function is actually executed
#     under errexit, so that is what this does.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

STEP=install/80-services.sh
[[ -r $STEP ]] || { echo "  FAIL: $STEP is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Run it the way install.sh does: a separate shell with errexit, nounset and
# pipefail, and OMAKEB_PATH exported. NOT `if ( set -e; ... )` — a command whose
# status is being tested has errexit suspended inside it, so that spelling would
# pass with the bugs present.
runner=$tmp/run.sh
cat > "$runner" <<'RUNNER'
#!/bin/bash
set -euo pipefail
cd "$1"
export OMAKEB_PATH="$1"
source lib/log.sh
source lib/guard.sh
eval "$(sed -n '/^reconcile_mako_activation() {/,/^}/p' install/80-services.sh)"
reconcile_mako_activation
RUNNER

ours=$tmp/data/dbus-1/services/fr.emersion.mako.service
run() {
  XDG_DATA_HOME=$tmp/data OMAKEB_MAKO_DBUS_SERVICE=$1 \
    bash "$runner" "$PWD" >/dev/null 2>&1
}

# --- 1. a packaged file with no SystemdService gets shadowed ------------------
cat > "$tmp/sys.service" <<'X'
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/bin/mako
X
rm -rf "$tmp/data"
before=$fail
if run "$tmp/sys.service"; then
  [[ -f $ours ]] || bad "no override written for a packaged file lacking SystemdService"
  grep -q '^SystemdService=mako.service$' "$ours" 2>/dev/null ||
    bad "the override does not set SystemdService=mako.service"
  grep -q '^Name=org.freedesktop.Notifications$' "$ours" 2>/dev/null ||
    bad "Name was not copied from the packaged file"
  grep -q '^Exec=/usr/bin/mako$' "$ours" 2>/dev/null ||
    bad "Exec was not copied from the packaged file"
else
  bad "reconcile_mako_activation failed under set -e with a normal packaged file"
fi
(( fail == before )) && ok "writes a shadow carrying SystemdService, with Name and Exec copied over"

# --- 2. Name and Exec are COPIED, not assumed ---------------------------------
cat > "$tmp/moved.service" <<'X'
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/opt/mako/bin/mako
X
rm -rf "$tmp/data"
before=$fail
run "$tmp/moved.service" || bad "failed under set -e when Exec is a non-standard path"
grep -q '^Exec=/opt/mako/bin/mako$' "$ours" 2>/dev/null ||
  bad "Exec is hardcoded; a moved binary would produce a shadow pointing nowhere"
(( fail == before )) && ok "a relocated mako binary is followed rather than assumed"

# --- 3. if Debian ships the line, stand down ----------------------------------
cat > "$tmp/fixed.service" <<'X'
[D-BUS Service]
Name=org.freedesktop.Notifications
Exec=/usr/bin/mako
SystemdService=mako.service
X
rm -rf "$tmp/data"
mkdir -p "$(dirname "$ours")"
printf 'stale\n' > "$ours"
before=$fail
run "$tmp/fixed.service" || bad "failed under set -e when the packaged file already sets SystemdService"
[[ -f $ours ]] && bad "our stale override was left shadowing a packaged file that no longer needs it"
(( fail == before )) && ok "removes its own override once the packaged file sets SystemdService"

# --- 4. no packaged file at all -----------------------------------------------
rm -rf "$tmp/data"
before=$fail
run "$tmp/absent.service" || bad "failed under set -e when mako is not D-Bus activatable"
[[ -f $ours ]] && bad "wrote an override for a mako that is not D-Bus activatable"
(( fail == before )) && ok "does nothing when there is no packaged activation file"

echo
if (( fail )); then
  echo "services checks FAILED"
  exit 1
fi
echo "services checks passed"
