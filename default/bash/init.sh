#!/bin/bash
# Tool initialisation. Sourced LAST by rc.sh.
#
# starship and zoxide both install a PROMPT_COMMAND hook and both want to run
# after anything else that touches it, so this is the end of the chain: fzf,
# then starship, then zoxide.
# shellcheck shell=bash

# --- fzf ----------------------------------------------------------------------
# CTRL-R history search, CTRL-T file paste, ALT-C cd. trixie ships fzf 0.60,
# which can print its own bash integration; the sourced example files are the
# path for anything older or for a stripped-down package.
if command -v fzf >/dev/null 2>&1; then
  _omakeb_fzf_init=$(fzf --bash 2>/dev/null) || _omakeb_fzf_init=
  if [[ -n $_omakeb_fzf_init ]]; then
    eval "$_omakeb_fzf_init"
  else
    for _omakeb_fzf_file in \
      /usr/share/doc/fzf/examples/key-bindings.bash \
      /usr/share/doc/fzf/examples/completion.bash; do
      if [[ -r $_omakeb_fzf_file ]]; then
        # shellcheck source=/dev/null
        source "$_omakeb_fzf_file"
      fi
    done
    unset _omakeb_fzf_file
  fi
  unset _omakeb_fzf_init

  # fd respects .gitignore and skips dotfiles, which is the right default for
  # CTRL-T. Falls back to fzf's built-in find walk when fd-find is absent.
  if command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
  fi
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=40% --layout=reverse --border --info=inline}"
fi

# --- starship -----------------------------------------------------------------
# No starship.toml is shipped in the repo: ~/.config/starship.toml is rendered
# from templates/starship.toml.tpl by omakeb-theme-set, so the prompt's colours
# follow the desktop theme. If that has not run yet, starship falls back to its
# built-in preset, which is fine.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# --- zoxide -------------------------------------------------------------------
# Provides `z` (jump) and `zi` (interactive, via fzf). Must come after anything
# else that assigns PROMPT_COMMAND, hence its position at the bottom of the file.
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi
