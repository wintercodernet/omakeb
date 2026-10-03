# shellcheck shell=bash
app_name=".NET SDK"
app_summary="Microsoft's .NET SDK 10, from the official Microsoft apt repository."
app_tier=2
# Verified by counting packages in the index, not by reading the Release file.
# That distinction matters here: the repository's InRelease advertises
# "Architectures: amd64 arm64 armhf all", but binary-armhf contains ZERO
# dotnet-sdk packages. Trusting the declaration would offer .NET on armhf and
# fail at install. Same shape as Edge's empty arm64 index (D10).
app_archs="amd64 arm64"

# .NET is not in Debian at all — not in trixie, not in backports — so unlike
# Java this cannot be tier 1. Microsoft's own repository is the only route, and
# it is the same host omakeb already uses for VS Code and Edge.
#
# Note the suite: `debian/13/prod`, keyed on the Debian release. That makes this
# one of the few things in the tree that will need attention at the next Debian
# release, alongside the backports pin (D13). omakeb-update's release check
# reports the pin; this one is on whoever does that upgrade.
app_installed() { pkg_installed dotnet-sdk-10.0; }

app_install() {
  # microsoft-2025.asc, NOT microsoft.asc. Microsoft signs this repository with
  # "Microsoft Corporation - General GPG Signer" (EE4D7792F748182B) and still
  # serves the older "Microsoft (Release signing)" key (EB3E94ADBE1229CF) at the
  # obvious URL, where it verifies nothing here. A known trap, met in the
  # wild: the key downloads fine, so nothing fails until apt refuses the repo.
  #
  # Checked, because the reflex is to assume the whole host rotated: the VS Code
  # and Edge repositories are still signed by the OLD key, so apps/vscode.sh and
  # apps/edge.sh are correct as they stand and must not be "fixed" to match this.
  repo_add dotnet \
    https://packages.microsoft.com/keys/microsoft-2025.asc \
    https://packages.microsoft.com/debian/13/prod \
    trixie main
  apt_install dotnet-sdk-10.0
  log_info "dotnet: $(dotnet --version 2>/dev/null)"
  # Telemetry is on by default and is opt-out only. Say so rather than deciding
  # for the user, and give them the line.
  log_info "telemetry is ON by default; disable with:"
  log_info "  echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >> ~/.bashrc"
}

app_remove() {
  apt_purge dotnet-sdk-10.0
  repo_remove dotnet
}
