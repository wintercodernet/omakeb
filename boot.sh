#!/bin/bash
# Bootstrap entry point.
#   curl -fsSL https://raw.githubusercontent.com/wintercodernet/omakeb/main/boot.sh | bash
#   wget -qO- https://raw.githubusercontent.com/wintercodernet/omakeb/main/boot.sh | bash
#
# A standard Debian netinst has neither curl nor git, so this script assumes
# nothing beyond bash, apt and a working network.

set -euo pipefail

OMAKEB_REPO="${OMAKEB_REPO:-https://github.com/wintercodernet/omakeb.git}"
OMAKEB_REF="${OMAKEB_REF:-main}"
OMAKEB_PATH="${OMAKEB_PATH:-$HOME/.local/share/omakeb}"

echo "=> omakeb — Hyprland desktop for Debian 13"
echo

if [[ $EUID -eq 0 ]]; then
  echo "Do not run this as root. It writes into \$HOME and uses sudo where needed." >&2
  exit 1
fi

# The sudo trap: Debian only adds the first user to the sudo group when the root
# password is left blank at install time. Catch it here, before anything else,
# because we cannot repair it ourselves — there is no sudo to install sudo with.
#
# Ask sudo what it will actually do rather than testing for the sudo group: a
# user with only a NOPASSWD rule in /etc/sudoers.d (cloud and provisioned
# images) can sudo without being in the group, and lib/sudo.sh supports that.
# `sudo -n true` first, because `sudo -v` demands a password even from a user
# whose NOPASSWD rule would let every real command through.
sudo_fix_hint() {
  cat >&2 <<MSG
$USER cannot use sudo, so omakeb cannot install anything.

This is normal on Debian when a root password was set during installation.
Fix it by running, as root:

    su -
    apt install -y sudo
    /sbin/adduser $USER sudo
    exit

Then log out and back in (group changes need a fresh session) and re-run this.
MSG
}

# Under `curl ... | bash` stdin is the pipe, not the terminal, so `-t 0` is
# false even when a person is sitting there. sudo prompts on /dev/tty, not on
# stdin, so what matters is whether there is a controlling terminal to open.
have_tty() { [[ -t 0 ]] || { : </dev/tty; } 2>/dev/null; }

if ! command -v sudo >/dev/null 2>&1; then
  sudo_fix_hint
  exit 1
fi
if ! sudo -n true 2>/dev/null; then
  if ! have_tty; then
    echo "sudo needs a password but there is no terminal to ask on." >&2
    echo "Run this from an interactive shell, or give $USER a NOPASSWD sudo rule." >&2
    echo >&2
    sudo_fix_hint
    exit 1
  fi
  # Prompting here is fine: boot.sh is run by a person, and asking once, up
  # front, beats asking in the middle of apt. It also warms the timestamp, so
  # install.sh's own check (lib/sudo.sh) passes without asking again.
  echo "omakeb needs sudo; enter your password if asked."
  if ! sudo -v; then
    echo >&2
    sudo_fix_hint
    exit 1
  fi
fi

echo "Installing bootstrap dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq git ca-certificates >/dev/null

# Two ways this used to lose someone's data, both now refusals:
#   * an existing directory that is not a checkout was `rm -rf`ed and recloned.
#     OMAKEB_PATH is overridable, so that could be any directory at all.
#   * an existing checkout was `reset --hard` onto origin, silently discarding
#     uncommitted edits and local commits. omakeb-update refuses to pull over a
#     dirty tree, and so does this.
# A refusal says what to do; boot.sh never decides that a person's files are
# disposable.
if [[ -e $OMAKEB_PATH/.git ]]; then
  echo "Updating existing checkout at $OMAKEB_PATH..."

  if [[ -n "$(git -C "$OMAKEB_PATH" status --porcelain)" ]]; then
    cat >&2 <<MSG
$OMAKEB_PATH has uncommitted changes, so it was not updated:

$(git -C "$OMAKEB_PATH" status --short | sed 's/^/    /')

Commit or stash them (git -C $OMAKEB_PATH stash), then re-run this.
Or, to use the checkout exactly as it is on disk:

    bash $OMAKEB_PATH/install.sh
MSG
    exit 1
  fi

  git -C "$OMAKEB_PATH" fetch --quiet origin "$OMAKEB_REF"

  # A detached HEAD with commits no remote has would be orphaned by the
  # checkout below. On a branch, switching away loses nothing.
  if ! git -C "$OMAKEB_PATH" symbolic-ref -q HEAD >/dev/null &&
     [[ -n "$(git -C "$OMAKEB_PATH" rev-list -n 1 HEAD --not --remotes)" ]]; then
    cat >&2 <<MSG
$OMAKEB_PATH is on a detached HEAD with commits that are on no remote branch.
Switching to $OMAKEB_REF would leave them unreachable. Put them on a branch
first (git -C $OMAKEB_PATH switch -c my-work), then re-run this.
MSG
    exit 1
  fi

  git -C "$OMAKEB_PATH" checkout --quiet "$OMAKEB_REF"

  # Local commits on the branch are someone's work. A fast-forward cannot lose
  # them, but it cannot apply either once the branch has diverged, so say so
  # rather than letting a bare git error end the bootstrap.
  if [[ -n "$(git -C "$OMAKEB_PATH" rev-list -n 1 "origin/$OMAKEB_REF..HEAD")" ]]; then
    cat >&2 <<MSG
$OMAKEB_PATH has local commits on $OMAKEB_REF that are not on origin/$OMAKEB_REF:

$(git -C "$OMAKEB_PATH" log --oneline "origin/$OMAKEB_REF..HEAD" | sed 's/^/    /')

Push them, or move them to another branch, then re-run this. Or, to use the
checkout exactly as it is on disk:

    bash $OMAKEB_PATH/install.sh
MSG
    exit 1
  fi

  # --ff-only, never reset: with the two checks above this always succeeds, and
  # if it somehow cannot, set -e stops us with the tree untouched.
  git -C "$OMAKEB_PATH" merge --ff-only --quiet "origin/$OMAKEB_REF"
elif [[ -e $OMAKEB_PATH && ! -d $OMAKEB_PATH ]]; then
  echo "$OMAKEB_PATH exists and is not a directory. Move it aside, or set" >&2
  echo "OMAKEB_PATH to somewhere else, and re-run this." >&2
  exit 1
elif [[ -d $OMAKEB_PATH && -n "$(ls -A "$OMAKEB_PATH")" ]]; then
  cat >&2 <<MSG
$OMAKEB_PATH already exists and is not a git checkout, so omakeb will not
touch it: it may be a half-finished copy, or someone's unrelated directory.

If it is a leftover omakeb copy you no longer need, remove it and re-run:

    rm -rf $OMAKEB_PATH

Or install somewhere else by setting OMAKEB_PATH for bash, e.g.

    curl -fsSL <boot.sh URL> | OMAKEB_PATH=/some/other/path bash
MSG
  exit 1
else
  # Missing, or an empty directory: git clones into an empty directory happily,
  # so there is nothing to remove.
  echo "Cloning omakeb to $OMAKEB_PATH..."
  mkdir -p "$(dirname "$OMAKEB_PATH")"
  git clone --quiet --branch "$OMAKEB_REF" "$OMAKEB_REPO" "$OMAKEB_PATH"
fi

exec bash "$OMAKEB_PATH/install.sh"
