#!/bin/bash
# PATH, editor and pager. Sourced by rc.sh.
# shellcheck shell=bash

# Idempotent PATH prepend — this file is re-sourced by every nested interactive
# shell, and a naive prepend grows PATH without bound inside tmux.
_omakeb_path_prepend() {
  case ":${PATH}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

# ~/.local/bin is where install/40-shell.sh symlinks the omakeb-* commands.
# Debian's stock ~/.profile already puts it on PATH for login shells, which is
# how the Hyprland session finds them; this covers plain interactive shells.
_omakeb_path_prepend "$HOME/.local/bin"
_omakeb_path_prepend "${OMAKEB_PATH:-$HOME/.local/share/omakeb}/bin"
export PATH
unset -f _omakeb_path_prepend

if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
  export VISUAL=nvim
fi

# -R so `git log`, `bat` and friends keep their colours through the pager.
export LESS="${LESS:--R}"
