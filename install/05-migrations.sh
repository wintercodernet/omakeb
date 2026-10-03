#!/bin/bash
# Apply pending migrations, or record them as already applied on a fresh box.
#
# First of the numbered steps, so a migration that retires something an older
# omakeb created runs BEFORE the steps that write the new state. The other order
# has a migration deleting a file 60-config.sh has just regenerated.
#
# Reached by install.sh and by omakeb-update alike — one code path, so the two
# cannot drift on what "applied" means. See migrations/README.md for the
# contract a migration has to meet.
# shellcheck shell=bash

# Set by install.sh when $OMAKEB_STATE did not exist before it started.
# omakeb-update never sets it: an update by definition runs on a machine that
# already has omakeb on it, so its migrations are always pending, never stamped.
if (( ${OMAKEB_FRESH_INSTALL:-0} )); then
  migrate_stamp_latest
else
  migrate_run_pending
fi
