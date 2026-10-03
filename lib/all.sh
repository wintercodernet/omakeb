#!/bin/bash
# Sourced by install.sh and by every bin/omakeb-* script.
# shellcheck shell=bash

# lib/all.sh lives at $OMAKEB_PATH/lib/, so derive the root from ourselves
# rather than assuming the canonical install location.
: "${OMAKEB_PATH:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

OMAKEB_STATE="${OMAKEB_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/omakeb}"
OMAKEB_CONFIG="${OMAKEB_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omakeb}"
OMAKEB_CACHE="${OMAKEB_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/omakeb}"
export OMAKEB_PATH OMAKEB_STATE OMAKEB_CONFIG OMAKEB_CACHE

for _lib in "$OMAKEB_PATH"/lib/*.sh; do
  [[ $(basename "$_lib") == all.sh ]] && continue
  source "$_lib"
done
unset _lib
