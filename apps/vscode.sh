# shellcheck shell=bash
app_name="Visual Studio Code"
app_summary="Microsoft's editor, from the official Microsoft apt repository."
app_tier=2
# Verified against the repo indices, not the docs: both carry a `code` package.
app_archs="amd64 arm64 armhf"

app_installed() { pkg_installed code; }

app_install() {
  repo_add vscode \
    https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/code \
    stable main
  apt_install code
  # The code package ships its own source list in postinst; drop ours so apt
  # does not warn about the repo being configured twice.
  repo_yield_to_vendor vscode \
    /etc/apt/sources.list.d/vscode.list \
    /etc/apt/sources.list.d/vscode.sources
}

app_remove() {
  apt_purge code
  repo_remove vscode
}
