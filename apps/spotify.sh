# shellcheck shell=bash
app_name="Spotify"
app_summary="Spotify's desktop client, from Spotify's own apt repository."
app_tier=2
# Verified against repository.spotify.com/dists/stable/Release, which declares
# exactly two architectures and ships spotify-client for only one of them.
# There is no aarch64 Spotify build and no Flathub one either (D10), so the
# runner refusing here is the honest outcome rather than a gap in packaging.
app_archs="amd64"

app_installed() { pkg_installed spotify-client; }

app_install() {
  # The suite is literally called `stable` and the component `non-free`; this is
  # Spotify's own naming, not a Debian suite name that happens to match.
  #
  # THE KEY IS PINNED BY KEY ID AND SPOTIFY ROTATES IT. Every rotation publishes
  # a new pubkey_<keyid>.gpg and leaves the old ones served, still returning 200,
  # so a stale URL here fails no download and raises no error — apt simply
  # reports "the repository is not signed" and every later apt operation on the
  # machine fails with it. There is no generic pubkey.gpg to point at; that URL
  # is a 404.
  #
  # This key is the one that signs the current Release:
  #   5384CE82BA52C83A, fpr E1096BCBFF6D418796DE78515384CE82BA52C83A
  #   uid Spotify Public Repository Signing Key <tux@spotify.com>
  #
  # To re-derive it after the next rotation, ask the repository which key signed
  # it rather than guessing from the download page:
  #   curl -fsSL https://repository.spotify.com/dists/stable/InRelease | gpg --verify
  # and take the key id it names.
  #
  # Note this file is BINARY, not ASCII-armoured like the Microsoft and Docker
  # keys — repo_add handles both.
  repo_add spotify \
    https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg \
    https://repository.spotify.com \
    stable non-free
  apt_install spotify-client

  # spotify-client drops its own /etc/apt/sources.list.d/spotify.list in
  # postinst, and ships the matching key into /etc/apt/trusted.gpg.d/, so from
  # here on the vendor's own pair verifies the repository without us. Keeping
  # ours as well makes apt warn "configured multiple times" on every single
  # update — five lines of it, since it counts per target.
  #
  # Handing over is also what fixes this permanently: the key above is pinned by
  # id and Spotify rotates it, but the package updates its own key with itself.
  # That is only true once spotify-client is actually installed, which is why we
  # bring our own repository to get that far and then stand it down.
  repo_yield_to_vendor spotify \
    /etc/apt/sources.list.d/spotify.list \
    /etc/apt/sources.list.d/spotify.sources
}

app_remove() {
  apt_purge spotify-client
  repo_remove spotify
}
