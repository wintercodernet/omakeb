#!/bin/bash
# Orchestrator. Idempotent by design: this is the repair tool as much as the
# installer, so every step must be safe to re-run on an already-configured box.

set -euo pipefail

# Derive our location instead of assuming it. boot.sh clones to
# ~/.local/share/omakeb, but running install.sh straight out of a checkout
# anywhere else is a supported path (test/vm/README.md tells you to do exactly
# that), and hardcoding the canonical path made that fail with a confusing
# "lib/all.sh: No such file or directory".
export OMAKEB_PATH="${OMAKEB_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
source "$OMAKEB_PATH/lib/all.sh"

# Fresh install, or a re-run on a machine that already has omakeb?
#
# It decides whether install/05-migrations.sh RUNS the migrations or merely
# records them as applied. A machine built by the current omakeb is already in
# the state every migration produces, so replaying them over it is at best
# wasted work; a machine built by an older one needs every one of them.
#
# The signal is whether the state directory pre-existed, and it has to be read
# HERE — before preflight, before any step, before anything calls state_init and
# creates it. It errs in the safe direction: a half-failed first install leaves a
# state directory behind and would be treated as existing, so its migrations run
# where they were not needed, which migrations/README.md requires to be a no-op.
# The opposite mistake — deciding a real machine is fresh and skipping a fix it
# needs — cannot happen.
if [[ -d $OMAKEB_STATE ]]; then
  OMAKEB_FRESH_INSTALL=0
else
  OMAKEB_FRESH_INSTALL=1
fi
export OMAKEB_FRESH_INSTALL

trap 'log_error "Installation failed at step: ${OMAKEB_STEP:-preflight}. Re-run with: bash $OMAKEB_PATH/install.sh"' ERR

source "$OMAKEB_PATH/install/preflight.sh"

for step in "$OMAKEB_PATH"/install/[0-9][0-9]-*.sh; do
  OMAKEB_STEP="$(basename "$step" .sh)"
  log_step "$OMAKEB_STEP"
  source "$step"
done

unset OMAKEB_STEP
log_done "omakeb installed. Reboot to land in Hyprland."
