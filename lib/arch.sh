#!/bin/bash
# Architecture handling.
#
# omakeb does not carry a list of "supported" architectures. Debian builds the
# Hyprland stack on eight of its nine release architectures — everything except
# mips64el — and an allowlist would both exclude working ports (riscv64, ppc64el,
# s390x) and wrongly promise mips64el. So nothing here gates on the architecture
# name. We ask apt what is actually installable and fail with the specific list
# of what is missing.
#
# shellcheck shell=bash

# Debian 13 release architectures. Used only to decide whether trixie-backports
# can exist at all — debian-ports architectures have no backports suite.
OMAKEB_RELEASE_ARCHES="amd64 arm64 armel armhf i386 mips64el ppc64el riscv64 s390x"

arch_dpkg() { dpkg --print-architecture; }

# Upstream release tarballs name architectures with uname -m conventions rather
# than dpkg's. Tier-3 installers use this to build a download URL.
# Returns empty for architectures upstreams do not usually publish binaries for,
# which the caller must treat as "no prebuilt binary available".
arch_vendor() {
  case "$(arch_dpkg)" in
    amd64)    echo x86_64 ;;
    arm64)    echo aarch64 ;;
    armhf)    echo armv7 ;;
    armel)    echo armv6 ;;
    i386)     echo i686 ;;
    ppc64el)  echo ppc64le ;;
    riscv64)  echo riscv64 ;;
    s390x)    echo s390x ;;
    *)        echo "" ;;
  esac
}

arch_is_release_arch() {
  grep -qw -- "$(arch_dpkg)" <<<"$OMAKEB_RELEASE_ARCHES"
}

# Does this package have an installation candidate for the running architecture?
pkg_has_candidate() {
  local candidate
  candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')
  [[ -n $candidate && $candidate != "(none)" ]]
}

# require_packages <label> <pkg>...
#
# Reports every unavailable package rather than dying on the first. On an
# unusual architecture the complete list is the useful diagnostic — knowing that
# one package is missing tells you nothing about whether the port is viable.
require_packages() {
  local label=$1; shift
  local missing=()
  for p in "$@"; do
    pkg_has_candidate "$p" || missing+=("$p")
  done

  if (( ${#missing[@]} )); then
    log_error "$label: ${#missing[@]} of $# packages are not available for $(arch_dpkg)."
    for p in "${missing[@]}"; do
      log_info "  - $p"
    done
    log_info ""
    log_info "Debian does not build every package on every architecture. If this is"
    log_info "a port such as mips64el, the Hyprland stack is genuinely unavailable"
    log_info "and omakeb cannot run here."
    exit 1
  fi
  log_ok "$label: all $# packages available for $(arch_dpkg)"
}

# tier3_fetch_url <template>
#
# Expands @VENDOR_ARCH@ in a download URL template, or fails if the running
# architecture has no vendor equivalent. Tier-3 installers call this so that an
# unsupported architecture produces "no prebuilt binary for riscv64" rather than
# a 404 halfway through an install.
tier3_fetch_url() {
  local template=$1 vendor
  vendor=$(arch_vendor)
  if [[ -z $vendor ]]; then
    log_warn "no upstream binary naming known for $(arch_dpkg); skipping"
    return 1
  fi
  echo "${template//@VENDOR_ARCH@/$vendor}"
}

# arch_vendor_named <dpkg>=<vendor> ...   e.g. amd64=x86-64 arm64=arm-64
#
# This machine's architecture, spelled the way one particular upstream spells
# it. arch_vendor() covers the common uname dialect (x86_64, aarch64); this
# covers everyone else, and there are a lot of everyone elses — LocalSend ships
# "linux-x86-64" and "linux-arm-64", which is a third convention again.
#
# The point is where the branch lives. D9 forbids a script deciding what it can
# do by looking at an architecture name; it does not forbid recording that a
# vendor calls amd64 something else. So the caller supplies the vocabulary and
# the decision happens here, once, in the file whose job that is.
#
# Returns non-zero when this architecture is not in the list, so a caller cannot
# build a download URL with an empty component in it and get a 404 halfway
# through an install instead of a clear refusal.
arch_vendor_named() {
  local want pair
  want=$(arch_dpkg)
  for pair in "$@"; do
    if [[ ${pair%%=*} == "$want" ]]; then
      printf '%s\n' "${pair#*=}"
      return 0
    fi
  done
  return 1
}
