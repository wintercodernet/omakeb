# shellcheck shell=bash
app_name="OpenAI Codex"
app_summary="OpenAI's agentic coding CLI, from the npm registry."
app_tier=3
app_archs="amd64 arm64"

# An npm package, installed with a per-user prefix into ~/.local — never with
# `sudo npm`, which runs package install scripts as root and writes into
# /usr/local where dpkg cannot see them. See npm_tool_install in lib/apps.sh.
#
# Runs on Debian's own node 20, verified by installing it and running it rather
# than by reading the engines field: npm_tool_install refuses up front if the
# package declares a newer node than Debian has, which is what stops this
# becoming a tool that installs cleanly and fails the first time it is used.
# engines.node >= 16, so Debian's 20 is comfortably enough.
app_installed() { npm_tool_installed codex; }
app_install()   { npm_tool_install codex "@openai/codex" codex; }
app_remove()    { npm_tool_remove  codex "@openai/codex"; }
app_latest()    { npm_latest_version "@openai/codex"; }
