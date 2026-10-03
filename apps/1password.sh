# shellcheck shell=bash
app_name="1Password"
app_summary="The 1Password desktop app, from AgileBits' own apt repository."
app_tier=2
# 1Password publishes one repository per architecture rather than one repository
# with several indices, and only one of them contains the desktop app. The other
# published repository exists and is signed by the same key, but its index holds
# a single package — the `1password-cli` binary — with no desktop app at all.
# Declaring the second architecture here would add a source that resolves fine
# and then fail at install, which is precisely the failure mode D10 was written
# about after Microsoft Edge.
app_archs="amd64"

app_installed() { pkg_installed 1password; }

app_install() {
  # The repository URI embeds the architecture, so it is built from arch_dpkg
  # rather than typed: app_archs above has already guaranteed which one this is,
  # and D9 wants the name derived, not repeated.
  repo_add 1password \
    https://downloads.1password.com/linux/keys/1password.asc \
    "https://downloads.1password.com/linux/debian/$(arch_dpkg)" \
    stable main

  apt_install 1password
}

# NOT INSTALLED: the debsig-verify policy from 1Password's published
# instructions (/etc/debsig/policies/AC2D62742012EA22/1password.pol plus a
# keyring under /usr/share/debsig/keyrings/). Checked, not assumed:
#
#   1. The .deb in this repository has no `_gpgorigin` member. Its ar archive is
#      debian-binary, control.tar.xz, data.tar — nothing else. debsig-verify
#      requires that member, so with a policy in place and debsig-verify present
#      the package could not verify at all; the policy would make installation
#      strictly less likely to work, not more.
#   2. dpkg does not consult debsig unless the debsig-verify binary is installed,
#      and it is not part of a Debian base system. Nothing on a stock trixie box
#      would ever read the policy we wrote.
#   3. Installing debsig-verify to make the policy meaningful would be actively
#      harmful: dpkg would then demand a matching policy for EVERY package, and
#      no other package in Debian or in any repository we add has one.
#   4. The signature that actually protects this download is apt's: repo_add
#      pins the repository to 1Password's key with Signed-By, and apt verifies
#      the Release signature and then the SHA256 of the .deb against it. debsig
#      would be a second check of the same bytes by the same key.
#
# The upstream instructions include the policy because they also cover manually
# downloaded .deb files, which arrive outside apt's chain of trust. We only ever
# install through apt, so it buys nothing here.

app_remove() {
  apt_purge 1password
  repo_remove 1password
}
