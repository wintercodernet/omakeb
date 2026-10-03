#!/bin/bash
# Aliases. Sourced by rc.sh.
#
# Debian renames two binaries to avoid clashes with unrelated packages:
#   bat     -> batcat   (the `bacula-console-qt` family already owns `bat`)
#   fd-find -> fdfind   (`fd` belongs to fdclone)
# Upstream documentation, muscle memory and half the internet say `bat` and
# `fd`, so aliasing them back is not a nicety — it is what makes those packages
# usable. Every alias is guarded, so an uninstalled tool leaves the real command
# (or the plain "command not found") alone.
# shellcheck shell=bash

if command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
fi

if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi

if command -v eza >/dev/null 2>&1; then
  # --icons=auto only draws icons on a terminal, and needs the Nerd Font
  # symbols installed by install/50-fonts.sh.
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l --group-directories-first --icons=auto --git'
  alias la='eza -la --group-directories-first --icons=auto --git'
  alias lt='eza --tree --level=2 --icons=auto'
fi

# Deliberately not aliased: `cat`, `grep`, `find`. Shadowing a POSIX command
# with something that formats differently breaks pipelines and surprises people
# reading a shared shell script over your shoulder.

alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -p'
