#!/bin/bash
# Shell behaviour. Sourced by rc.sh.
# shellcheck shell=bash

# History: keep a lot of it, keep it clean, and do not let the last shell to
# exit clobber what every other shell recorded.
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=50000
HISTFILESIZE=50000
HISTTIMEFORMAT='%F %T '
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history:reset'
shopt -s histappend
shopt -s cmdhist

# Set one at a time and swallow the complaint: globstar, autocd and dirspell
# need bash 4, and Debian 13 has 5.2 — but this file is also read by whatever
# bash a user drops into, and an error on every login is worse than a missing
# convenience.
#   checkwinsize            keep $LINES/$COLUMNS right after a terminal resize
#   globstar                ** matches across directories
#   autocd                  `..` instead of `cd ..`
#   cdspell / dirspell      fix small typos in directory names
#   no_empty_cmd_completion do not scan $PATH when TAB is hit on an empty line
for _omakeb_shopt in checkwinsize globstar autocd cdspell dirspell no_empty_cmd_completion; do
  shopt -s "$_omakeb_shopt" 2>/dev/null
done
unset _omakeb_shopt

# bash-completion is enabled system-wide by Debian's /etc/bash.bashrc, so there
# is deliberately nothing to do here.
