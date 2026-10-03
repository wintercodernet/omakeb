# shellcheck shell=bash
app_name="Microsoft Edge"
app_summary="Microsoft's Chromium browser, from the official Microsoft apt repository."
app_tier=2
# amd64 ONLY, and this is not an oversight. Microsoft publishes an arm64 index
# for this repo, but it contains zero packages — there is no aarch64 Edge build
# at all, on apt or Flathub (see D10). Declaring arm64 here would add a source
# that 404s nothing and then fail at install with an unhelpful message.
app_archs="amd64"

app_installed() { pkg_installed microsoft-edge-stable; }

app_install() {
  repo_add edge \
    https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/edge \
    stable main
  apt_install microsoft-edge-stable
}

app_remove() {
  apt_purge microsoft-edge-stable
  repo_remove edge
}
