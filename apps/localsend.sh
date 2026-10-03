# shellcheck shell=bash
app_name="LocalSend"
app_summary="Send files between devices on your own network, with no cloud account."
app_tier=3
# Upstream publishes linux-x86-64 and linux-arm-64 .deb assets. Verified against
# the release assets themselves; there is no armhf or riscv64 build.
app_archs="amd64 arm64"

app_installed() { pkg_installed localsend; }

app_install() {
  local tag version url vendor_arch
  tag=$(github_latest_tag localsend/localsend) || {
    log_error "could not ask GitHub for the latest LocalSend release"
    return 1
  }
  version=${tag#v}

  # Upstream's own arch words match neither dpkg's nor uname's: "x86-64" and
  # "arm-64", both hyphenated, a third convention again. The branch lives in
  # lib/arch.sh (D9); this line only states what this vendor calls things.
  vendor_arch=$(arch_vendor_named amd64=x86-64 arm64=arm-64) || {
    log_error "upstream publishes no LocalSend build for $(arch_dpkg)"
    return 1
  }

  url="https://github.com/localsend/localsend/releases/download/$tag/LocalSend-$version-linux-$vendor_arch.deb"
  deb_install_url localsend "$url" "$version" || return 1
  log_ok "LocalSend $version"
  log_info "it needs a firewall hole on port 53317 to be discovered by other devices"
}

# What omakeb-update compares the recorded version against. Same source and same
# `v` stripping as app_install, so the two strings are comparable.
app_latest() {
  local tag
  tag=$(github_latest_tag localsend/localsend) || return 1
  printf '%s\n' "${tag#v}"
}

app_remove() {
  apt_purge localsend
  rm -f "$OMAKEB_STATE/app-version/localsend"
}
