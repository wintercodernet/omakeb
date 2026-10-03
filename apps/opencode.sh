# shellcheck shell=bash
app_name="OpenCode"
app_summary="Open-source agentic coding CLI, from the npm registry."
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
# Upstream's package declares cpu=[arm64,x64], so no armhf or riscv64 build.
app_installed() { npm_tool_installed opencode; }
app_install()   { npm_tool_install opencode "opencode-ai" opencode; }
app_remove()    { npm_tool_remove  opencode "opencode-ai"; }
app_latest()    { npm_latest_version "opencode-ai"; }
