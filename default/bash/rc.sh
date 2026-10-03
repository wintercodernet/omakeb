#!/bin/bash
# omakeb — interactive bash defaults.
#
# ~/.bashrc gets exactly ONE line pointing here (added by install/40-shell.sh).
# Everything else lives in this directory, which omakeb owns and rewrites on
# update — so a re-run never has to touch ~/.bashrc again, and there is nothing
# to append twice.
#
# Your own settings go in ~/.config/omakeb/bashrc, sourced last so it wins.
# shellcheck shell=bash

# Debian's ~/.bashrc already returns early for non-interactive shells, but this
# file is also reachable directly (and from a login shell that skipped that
# guard), so repeat it. Nothing below is safe or useful in a script.
case $- in
  *i*) ;;
  *) return ;;
esac

# Resolve our own directory rather than hardcoding OMAKEB_PATH: the single line
# in ~/.bashrc already knows where we live, and this keeps a relocated checkout
# working without rewriting the fragments.
_omakeb_bash_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

if [[ -n $_omakeb_bash_dir ]]; then
  # $_omakeb_bash_dir is $OMAKEB_PATH/default/bash — export the root so env.sh
  # and every omakeb-* command agree with the checkout that installed them.
  export OMAKEB_PATH="${OMAKEB_PATH:-$(cd -- "$_omakeb_bash_dir/../.." && pwd)}"

  # Order matters. env sets PATH before anything looks for a binary; init runs
  # last because starship and zoxide both hook PROMPT_COMMAND and want to see
  # its final value.
  for _omakeb_frag in env options aliases init; do
    if [[ -r "$_omakeb_bash_dir/$_omakeb_frag.sh" ]]; then
      # shellcheck source=/dev/null
      source "$_omakeb_bash_dir/$_omakeb_frag.sh"
    fi
  done
  unset _omakeb_frag
fi
unset _omakeb_bash_dir

_omakeb_user_bashrc="${OMAKEB_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omakeb}/bashrc"
if [[ -r $_omakeb_user_bashrc ]]; then
  # shellcheck source=/dev/null
  source "$_omakeb_user_bashrc"
fi
unset _omakeb_user_bashrc

# Return success regardless: a missing optional fragment must not make ~/.bashrc
# look like it failed.
true
