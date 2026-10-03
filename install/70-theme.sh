#!/bin/bash
# Render the active theme.
#
# Must run after 60-config.sh, which writes the Hyprland entry point that
# `source =`s ~/.config/hypr/colors.conf — and hyprlang treats a missing source
# target as a config error, so that file has to exist before the session starts.
#
# Idempotent, like every step: omakeb-theme-set writes through write_file, so a
# second install run reports "unchanged" and touches nothing.
#
# --no-reload because there is no compositor here. install.sh runs on a TTY,
# possibly inside a container; the reload path would find nothing running and
# log a wall of skips. The files land on disk and the session picks them up.
# shellcheck shell=bash

theme=$(state_get theme)

if [[ -n $theme ]] && ! theme_dir "$theme" >/dev/null 2>&1; then
  log_warn "the recorded theme '$theme' is gone; falling back to $OMAKEB_THEME_DEFAULT"
  theme=
fi
[[ -n $theme ]] || theme=$OMAKEB_THEME_DEFAULT

"$OMAKEB_PATH/bin/omakeb-theme-set" --no-reload "$theme"
