#!/bin/bash
# shellcheck shell=bash

state_init() { mkdir -p "$OMAKEB_STATE" "$OMAKEB_CONFIG" "$OMAKEB_CACHE"; }

state_get() { cat "$OMAKEB_STATE/$1" 2>/dev/null || true; }
# A key may contain a slash — "app-version/codex" is a real one — so create the
# parent, as run_once already does for its markers. Without this the redirect
# fails on the first nested key ever written, and it fails LATE: the thing the
# state was recording has already happened, so the caller aborts having done the
# work and reported nothing.
state_set() {
  state_init
  local dest="$OMAKEB_STATE/$1"
  case "$1" in */*) mkdir -p "$(dirname "$dest")" ;; esac
  printf '%s\n' "$2" > "$dest"
}

# Run a block exactly once, ever. Used for steps that are destructive to re-do,
# such as seeding a user config file the user may since have edited.
run_once() {
  local marker="$OMAKEB_STATE/once/$1"; shift
  if [[ -e $marker ]]; then
    log_skip "already done once: $(basename "$marker")"
    return 0
  fi
  "$@"
  mkdir -p "$(dirname "$marker")"
  : > "$marker"
}
