#!/bin/bash
# Shell environment: put the omakeb commands on PATH and hook our bash defaults
# into ~/.bashrc.
#
# Everything of substance lives in default/bash/*.sh, which omakeb owns. This
# step only has to do two things, both of which must be safe to repeat forever:
#   1. link bin/omakeb-* into ~/.local/bin
#   2. add ONE guarded source line to ~/.bashrc
#
# The one-line rule matters. Appending a block of settings to ~/.bashrc means
# every re-run either duplicates it or needs a fragile delete-and-rewrite; a
# single line to a file we own means updates change nothing in $HOME at all.
# shellcheck shell=bash

# The packages themselves (bash-completion, fzf, zoxide, eza, bat, fd-find,
# starship) are tier 1 and already installed by install/20-base.sh from
# packages/base.list. Nothing to install here.

# --- omakeb commands on PATH --------------------------------------------------
#
# The Hyprland keybindings call `omakeb-menu`, `omakeb-launch-terminal` and
# friends by bare name, so they have to resolve in the *session* PATH, not just
# in an interactive shell. greetd runs the session through a login shell, which
# sources Debian's stock ~/.profile, which prepends ~/.local/bin when it exists.
# Symlinking there is therefore the mechanism that actually works for both the
# compositor and the terminal; default/bash/env.sh is only belt and braces.
bindir="$HOME/.local/bin"
mkdir -p "$bindir"

linked=0
for src in "$OMAKEB_PATH"/bin/omakeb-*; do
  [[ -f $src ]] || continue
  dest="$bindir/$(basename "$src")"
  [[ -L $dest && "$(readlink "$dest")" == "$src" ]] && continue
  ln -sfn "$src" "$dest"
  linked=$((linked + 1))
done

# A renamed or deleted command leaves a dangling link that shadows nothing but
# looks alarming in `ls`. Only ever touch links that point back into our own
# checkout, so a user's hand-made symlinks are left alone.
pruned=0
for dest in "$bindir"/omakeb-*; do
  [[ -L $dest ]] || continue
  target=$(readlink "$dest")
  [[ $target == "$OMAKEB_PATH"/bin/* ]] || continue
  [[ -e $target ]] && continue
  rm -f "$dest"
  pruned=$((pruned + 1))
done

if (( linked || pruned )); then
  log_ok "omakeb commands in $bindir: $linked linked, $pruned stale removed"
else
  log_skip "omakeb commands already linked into $bindir"
fi

# --- one guarded line in ~/.bashrc --------------------------------------------
#
# A function taking the file and the checkout path, rather than bare code using
# $HOME and $OMAKEB_PATH, only so test/lint-shell.sh can run it against a temp
# file in a separate `bash -euo pipefail` process. The step calls it once below.
#
# The line carries the ABSOLUTE checkout path, because ~/.bashrc has no other
# way to find us. That path is only right until the checkout moves (README says
# any path is supported), and a stale line fails its own -r guard silently: the
# shell just loses every omakeb default and nothing says why. So a present
# marker is not enough to skip; the line after it must also name THIS checkout,
# and if it names another one, that one line is rewritten.
ensure_bashrc_line() {
  local bashrc=$1 path=$2
  local marker='# omakeb:bashrc'
  local want n cur tmp
  want=$(printf '[ -r "%s/default/bash/rc.sh" ] && . "%s/default/bash/rc.sh"' "$path" "$path")

  if [[ ! -f $bashrc ]]; then
    # A netinst user always has one from /etc/skel, but a system account or a
    # hand-made $HOME may not. Create an empty one rather than failing.
    : > "$bashrc"
    log_ok "created $bashrc"
  fi

  if ! grep -qF "$marker" "$bashrc"; then
    # Appended, not prepended: Debian's ~/.bashrc sets PS1 and enables
    # completion, and we want the last word on the prompt. Guarded with -r so an
    # uninstalled omakeb degrades to a plain Debian shell instead of an error on
    # every login.
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$want"
    } >> "$bashrc"
    log_ok "added the omakeb line to $bashrc"
    return 0
  fi

  # Line number of the first line that IS the marker. awk compares strings, so
  # nothing in a user's file is treated as a pattern. awk exits 0 whether or not
  # it finds one, so this is safe under `set -e`; an empty $n is handled below.
  n=$(awk -v m="$marker" '$0 == m { print NR; exit }' "$bashrc")
  cur=
  if [[ -n $n ]]; then
    cur=$(awk -v n="$((n + 1))" 'NR == n { print; exit }' "$bashrc")
  fi

  if [[ $cur == "$want" ]]; then
    log_skip "~/.bashrc already sources omakeb defaults"
    return 0
  fi

  # Only ever rewrite a line that has the exact shape we write. If the marker is
  # there but the line after it is something else, a person has edited it, and
  # guessing what they meant is worse than leaving it and saying so.
  if [[ -z $n || $cur != '[ -r "'*'/default/bash/rc.sh" ] && . "'*'/default/bash/rc.sh"' ]]; then
    log_warn "~/.bashrc has the omakeb marker but not the line omakeb writes after it;"
    log_warn "leaving it alone. The line should read: $want"
    return 0
  fi

  # Rewritten with head/tail around the one line, not `sed -i`: the paths are
  # arbitrary, so any sed delimiter can appear in them, and head/tail copy every
  # other byte of the user's file untouched (including a missing final newline).
  # Written back with `cat >` rather than `mv`, so a ~/.bashrc that is a symlink
  # into someone's dotfiles repo stays a symlink and keeps its permissions.
  tmp=$(mktemp "${TMPDIR:-/tmp}/omakeb-bashrc.XXXXXX")
  {
    head -n "$n" "$bashrc"
    printf '%s\n' "$want"
    tail -n +"$((n + 2))" "$bashrc"
  } > "$tmp"
  cat "$tmp" > "$bashrc"
  rm -f "$tmp"
  log_ok "pointed the omakeb line in $bashrc at $path"
}

ensure_bashrc_line "$HOME/.bashrc" "$OMAKEB_PATH"

unset bindir linked pruned src dest target
