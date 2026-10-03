#!/bin/bash
# The Debian release omakeb targets.
#
# One name, in one place. The backports source, its pin, the explicit -t on the
# compositor install and the extra-components source all name a suite, and
# every one of them has to change together when omakeb moves to the next
# release. Spelled out separately they would not: the first forky machine would
# get forky-backports and trixie-security, and nothing would say so.
#
# This is deliberately a constant and NOT derived from /etc/os-release. A
# machine running some other release is not one omakeb should quietly adapt its
# apt sources to — that is D13's "report, don't repair". Callers compare the
# running release against this and decide what to do about a mismatch;
# install/10-sources.sh skips backports, bin/omakeb-update refuses to converge.
#
# test/lint-release.sh fails on the codename appearing literally anywhere else
# in lib/ install/ bin/ outside a comment.
# shellcheck shell=bash

OMAKEB_DEBIAN_CODENAME=trixie
OMAKEB_BACKPORTS_SUITE="${OMAKEB_DEBIAN_CODENAME}-backports"

# release_codename — the running system's VERSION_CODENAME, or empty.
#
# Read in a subshell so that sourcing os-release does not leave ID, VERSION_ID
# and friends in the caller's shell. Always returns 0: an unreadable or
# codename-less os-release is an answer ("unknown"), not an error, and a
# non-zero status here would end an installer running under `set -e` from
# inside a `$(...)` assignment. OMAKEB_OS_RELEASE exists for the static test.
release_codename() {
  local f=${OMAKEB_OS_RELEASE:-/etc/os-release}
  [[ -r $f ]] || return 0
  # shellcheck disable=SC1090
  ( . "$f" 2>/dev/null; printf '%s\n' "${VERSION_CODENAME:-}" ) || true
}

# release_stale_suites <sources-file>...
#
# Prints "<file>: <suite>" for every suite named in these deb822 files whose
# release is not the one this machine runs — trixie-backports on a forky box,
# say. Prints nothing when everything matches or none of the files exist.
#
# It compares against the RUNNING release, not the target. The question it
# answers is "are omakeb's own apt files now wrong for this machine?", and a
# sid machine installed on purpose, which 10-sources.sh gave no backports file,
# must come out clean rather than be told on every update that it is not
# trixie. The -backports/-updates/-security suffixes are stripped to get the
# release name. Files are world-readable (0644), so no sudo.
#
# Always returns 0, for the same `set -e` reason as release_codename.
release_stale_suites() {
  local running f suite base
  running=$(release_codename)
  # No readable os-release means no answer, not "everything is stale": skipping
  # converge on every suite would turn a missing file into a refusal to update.
  [[ -n $running ]] || return 0
  for f in "$@"; do
    [[ -r $f ]] || continue
    for suite in $(sed -n 's/^Suites:[[:space:]]*//p' "$f"); do
      base=${suite%-backports}
      base=${base%-updates}
      base=${base%-security}
      if [[ $base != "$running" ]]; then
        printf '%s: %s\n' "$f" "$suite"
      fi
    done
  done
  return 0
}
