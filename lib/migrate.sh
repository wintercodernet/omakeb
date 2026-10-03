#!/bin/bash
# Migrations — one-off fixes for machines that already have omakeb on them.
#
# Almost nothing needs one. Every install step is idempotent and `install.sh` is
# the repair tool, so adding a package, changing a
# template or writing a new config is delivered simply by reconverging. A
# migration is for the cases reconverging cannot reach, because they are about
# *removing* or *renaming* something a previous version of omakeb created:
# a config file we no longer generate, a systemd unit we stopped shipping, a
# state key that changed meaning. install.sh writes the new state; only a
# migration can retire the old one.
#
# Naming is by unix epoch, `migrations/<epoch>.sh` — Omarchy's convention, and
# the reason is that it needs no coordination. Two people adding a migration on
# separate branches cannot collide, and the ordering across a merge is the
# ordering in which they were written.
#
# The high-water mark is $OMAKEB_STATE/migration. Only migrations newer than the
# mark run, and the mark advances after each one succeeds — so a failure at the
# third of five leaves the first two recorded and a re-run resumes at the third
# rather than replaying from the start.
#
# shellcheck shell=bash

OMAKEB_MIGRATIONS="${OMAKEB_MIGRATIONS:-$OMAKEB_PATH/migrations}"

# The epoch below which a name is certainly a mistake rather than a timestamp.
# The trap this exists for: `20260901.sh` looks like a date and is a perfectly
# valid integer, but as an epoch it is August 1970 — so it sorts before every
# real migration and is silently skipped forever on any machine whose mark is
# already set. Anything from 2025 onwards is a plausible omakeb migration.
OMAKEB_MIGRATION_MIN_EPOCH=1735689600   # 2025-01-01T00:00:00Z

migrate_mark_file() { printf '%s\n' "$OMAKEB_STATE/migration"; }

# The high-water mark, or 0 on a machine that has never recorded one. A machine
# installed before migrations existed reads 0 and runs everything, which is the
# safe direction: migrations must be no-ops on a machine that never had the
# problem, so running one spuriously costs nothing and skipping one costs a bug.
migrate_mark() {
  local m
  m=$(cat "$(migrate_mark_file)" 2>/dev/null || true)
  [[ $m =~ ^[0-9]+$ ]] || m=0
  printf '%s\n' "$m"
}

# Every migration, oldest first, one path per line.
#
# Sorted numerically, not lexicographically. Ten-digit epochs happen to sort the
# same either way, which is exactly what makes this worth being explicit about:
# it would keep working until it quietly did not.
migrate_all() {
  [[ -d $OMAKEB_MIGRATIONS ]] || return 0
  local f base
  for f in "$OMAKEB_MIGRATIONS"/*.sh; do
    [[ -f $f ]] || continue
    base=$(basename "$f" .sh)
    if [[ ! $base =~ ^[0-9]+$ ]]; then
      log_warn "ignoring migration with a non-epoch name: $(basename "$f")"
      continue
    fi
    printf '%s\t%s\n' "$base" "$f"
  done | sort -n | cut -f2
}

migrate_latest_epoch() {
  local last
  last=$(migrate_all | tail -1)
  if [[ -n $last ]]; then basename "$last" .sh; else printf '0\n'; fi
}

migrate_pending() {
  local mark f base
  mark=$(migrate_mark)
  migrate_all | while IFS= read -r f; do
    base=$(basename "$f" .sh)
    # Written as an `if` and not `(( ... )) && printf`, because an && list whose
    # left side is false returns non-zero, and as the last statement of a loop
    # body under `set -e` that ends the script.
    if (( base > mark )); then
      printf '%s\n' "$f"
    fi
  done
}

migrate_describe() {
  sed -n '/^# omakeb:migration=/{s/^# omakeb:migration=//;p;q;}' "$1"
}

# Record every existing migration as already applied, without running any.
#
# This is what a FRESH install does. A migration exists to correct a machine
# built by an older omakeb; a machine built five minutes ago by the current one
# is already in the state the migration would produce. Replaying history over it
# is at best wasted work and at worst a fix being applied to something that was
# never broken.
migrate_stamp_latest() {
  local latest count
  latest=$(migrate_latest_epoch)
  count=$(migrate_all | grep -c . || true)
  state_set migration "$latest"
  if (( count )); then
    log_ok "fresh install: $count migration(s) recorded as already applied (mark $latest)"
  else
    log_skip "no migrations to record (mark $latest)"
  fi
}

# Run every pending migration, oldest first. Non-zero if one failed.
#
# Each runs in its own subshell, so it cannot cd the caller somewhere, exit the
# update, or clobber a variable the runner is holding.
#
# The status is read on the LINE AFTER the subshell and never tested inline.
# A command whose exit status is being tested has errexit suspended inside it,
# so `if ( set -e; source "$f" ); then` would run a failing
# migration all the way to its last line and then report success — the exact
# shape of a check that passes with its bug present. `set +e`, run, read `$?`.
migrate_run_pending() {
  local pending count=0 failed=0 f base desc rc had_e

  pending=$(migrate_pending)
  if [[ -z $pending ]]; then
    log_skip "no pending migrations (mark $(migrate_mark))"
    return 0
  fi

  case $- in *e*) had_e=1 ;; *) had_e=0 ;; esac

  while IFS= read -r f; do
    [[ -n $f ]] || continue
    base=$(basename "$f" .sh)
    desc=$(migrate_describe "$f")
    log_info "migration $base — ${desc:-no description}"

    set +e
    ( set -euo pipefail; source "$f" )
    rc=$?
    if (( had_e )); then set -e; fi

    if (( rc != 0 )); then
      log_error "migration $base failed (exit $rc): $f"
      log_warn "The mark stays at $(migrate_mark); nothing after this one has run."
      log_warn "Fix the cause and re-run, or record it as applied with:"
      log_warn "  echo $base > $(migrate_mark_file)"
      failed=1
      break
    fi

    # After each success, not once at the end. A failure partway through must
    # not replay the migrations that already worked.
    state_set migration "$base"
    count=$((count + 1))
  done <<< "$pending"

  if (( failed )); then
    return 1
  fi
  log_ok "$count migration(s) applied (mark now $(migrate_mark))"
  return 0
}
