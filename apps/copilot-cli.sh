# shellcheck shell=bash
app_name="GitHub Copilot CLI"
app_summary="GitHub's agentic coding CLI. Not the 'gh' extension — the standalone agent."
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
# The npm package declares no cpu or engines constraint at all, so the arch
# list here is the two upstream actually tests rather than a claim from
# metadata. 'gh copilot' is a different, older thing and is not this.
app_installed() { npm_tool_installed copilot; }
app_install()   { npm_tool_install copilot-cli "@github/copilot" copilot; }
app_remove()    { npm_tool_remove  copilot-cli "@github/copilot"; }
app_latest()    { npm_latest_version "@github/copilot"; }
