#!/bin/bash
# shellcheck shell=bash

# Write a file only if its content would change, and report which.
# Keeps re-runs quiet and makes "what did the update actually do" answerable.
write_file() {
  local dest=$1 mode=${2:-0644} content
  content=$(cat)
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]] && [[ "$(cat "$dest")" == "$content" ]]; then
    log_skip "unchanged: $dest"
    return 0
  fi
  printf '%s\n' "$content" > "$dest"
  chmod "$mode" "$dest"
  log_ok "wrote: $dest"
}

# Same, for files owned by root.
write_file_sudo() {
  local dest=$1 mode=${2:-0644} content tmp
  content=$(cat)
  if sudo test -f "$dest" && [[ "$(sudo cat "$dest")" == "$content" ]]; then
    log_skip "unchanged: $dest"
    return 0
  fi
  tmp=$(mktemp)
  printf '%s\n' "$content" > "$tmp"
  sudo install -D -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  log_ok "wrote: $dest"
}
