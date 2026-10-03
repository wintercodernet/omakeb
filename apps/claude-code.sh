# shellcheck shell=bash
app_name="Claude Code"
app_summary="Anthropic's agentic coding CLI. Self-contained binary; needs no Node."
app_tier=3
# Upstream's installer resolves the build itself. Restricted to the two it
# actually publishes rather than letting it 404 mid-install on a port (D9).
app_archs="amd64 arm64"

# NOT the npm package, and this is the interesting part.
#
# @anthropic-ai/claude-code declares engines.node >= 22. Debian trixie ships
# node 20.19.2. So `npm install -g @anthropic-ai/claude-code` cannot work here
# without a second Node from outside Debian, which would be a much bigger
# imposition than this app is worth — D13's ceiling, met in practice.
#
# Upstream's native installer sidesteps it entirely: a self-contained binary
# into ~/.local/share/claude/versions/, symlinked to ~/.local/bin/claude, which
# install/40-shell.sh has already put on PATH. No Node, no root, no apt.
# Verified end to end on the test machine.
CLAUDE_INSTALLER=https://claude.ai/install.sh

# Upstream's installer puts the binary where it updates it, and it does update
# it, in the background, on its own schedule. So there is no app_latest: a
# comparison would report every self-update as drift, and an "upgrade" from
# omakeb would fight the tool's own mechanism.
app_self_updating=1

# ~/.local/bin as well as PATH: a terminal opened before install/40-shell.sh
# took effect, or one launched from the menu, may not have it on PATH yet.
app_installed() {
  command -v claude >/dev/null 2>&1 || [[ -x $HOME/.local/bin/claude ]]
}

app_install() {
  apt_install curl ca-certificates

  # Piping a downloaded script into a shell is what upstream documents, and it
  # is what this does — but fetch it first so a failed download or a captive
  # portal cannot become "run half a script". TLS is the integrity story; there
  # is no published checksum to check against.
  local tmp
  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --max-time 120 \
        -o "$tmp/install.sh" "$CLAUDE_INSTALLER"; then
    rm -rf "$tmp"
    log_error "could not download the Claude Code installer from $CLAUDE_INSTALLER"
    return 1
  fi
  if ! head -1 "$tmp/install.sh" | grep -q '^#!'; then
    rm -rf "$tmp"
    log_error "what was downloaded is not a shell script; upstream may have moved it"
    return 1
  fi

  bash "$tmp/install.sh" || { rm -rf "$tmp"; log_error "the Claude Code installer failed"; return 1; }
  rm -rf "$tmp"

  # The installer has just created ~/.local/bin/claude, and this shell's PATH
  # was fixed before it did — so ask for it by where it was put if PATH does not
  # know it. `|| true` because the tool is already installed at this point, and
  # a grep that finds nothing must not end the script before it is recorded
  # (set -euo pipefail in the runner).
  local version claude_bin
  claude_bin=$(command -v claude 2>/dev/null) || claude_bin="$HOME/.local/bin/claude"
  version=$("$claude_bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
  tier3_version_set claude-code "${version:-unknown}"
  log_ok "claude ${version:-installed}"
  log_info "it updates itself; omakeb does not manage its version after this"
}

app_remove() {
  rm -f "$HOME/.local/bin/claude"
  rm -rf "$HOME/.local/share/claude"
  rm -f "$OMAKEB_STATE/app-version/claude-code"
  log_ok "removed the Claude Code binary and its versions directory"
  log_info "your settings in ~/.claude and ~/.claude.json were left alone"
}
