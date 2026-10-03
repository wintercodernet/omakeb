#!/bin/bash
# Ask a real Debian machine whether every package name we ship resolves.
#
# This exists because of a hard-won rule: **never verify a package name over
# HTTP.** `packages.debian.org/trixie/<pkg>` returns 200 with a "no such
# package" page, which is how `greetd-tuigreet` — a package that does not exist
# — got into packages/desktop.list and stayed there. Only apt knows, and apt
# lives on Debian, not on the machine this repo is usually edited from.
#
# install/10-sources.sh already runs require_packages over all three lists, so a
# bad name cannot reach a working install. But it finds out during the install,
# on someone's machine, at the point where the install stops. This finds out
# now, from here, in about a second.
#
#   ./test/vm/verify-packages.sh user@testbox
#
# Availability is per-architecture (D9), so the report names the architecture it
# asked about. A package present on amd64 and absent on riscv64 is not a
# mistake; a package absent everywhere is.
#
# It reads apt's existing indexes and never writes anything, so it needs no
# sudo and cannot disturb the machine. If a package was added to Debian very
# recently and the target has not run `apt-get update` in a while, a false
# MISSING is possible — the script says so when it reports one.

set -euo pipefail
cd "$(dirname "$0")/../.."

target=${1:-}
if [[ -z $target || $target == -h || $target == --help ]]; then
  cat <<'USAGE'
usage: ./test/vm/verify-packages.sh <user@host> [ssh options...]

Asks that machine's apt whether every name in packages/*.list resolves for its
architecture. Reads only; needs no sudo on the target.

  ./test/vm/verify-packages.sh user@testbox
  ./test/vm/verify-packages.sh user@localhost -p 2222
USAGE
  exit "${target:+1}"
fi
shift

pkgs=()
for list in packages/*.list; do
  while IFS= read -r name; do
    [[ -n $name ]] && pkgs+=("$name")
  done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$list" | tr -d ' \t')
done

# The names that are ALLOWED to come from backports — everything else arriving
# from there means install/10-sources.sh's pin is leaking, which is the one
# thing about this setup that would quietly turn a stable box into a mixed one.
# 10-sources.sh asserts it for `hyprland` alone; this asserts it for all 80.
bp_allowed=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' packages/backports.list |
             tr -d ' \t' | paste -sd, -)

if [[ ${#pkgs[@]} -eq 0 ]]; then
  echo "no package names found in packages/*.list" >&2
  exit 1
fi

echo "asking $target about ${#pkgs[@]} package names from packages/*.list"
echo

# Names go as positional parameters and the script goes on stdin, which is what
# `bash -s --` is for. ssh reads the password from the terminal directly, not
# from stdin, so the heredoc does not interfere with a password prompt.
# shellcheck disable=SC2029
ssh "$target" "$@" "bash -s -- $(printf '%q ' "$bp_allowed" "${pkgs[@]}")" <<'REMOTE'
set -u
bp_allowed=,$1,; shift

arch=$(dpkg --print-architecture)
. /etc/os-release 2>/dev/null || true
printf '%s / %s\n\n' "${PRETTY_NAME:-unknown Debian}" "$arch"

# Which suite apt would actually take the candidate from.
#
# Not "the first line mentioning a suite": for a package whose candidate is
# NEWER than what is installed, the candidate's line carries no `***` and the
# installed version's sources come later — so a naive scan reports the wrong
# suite, and reports it most often for the packages a person would look at
# hardest. Find the candidate's own version line, then the first source under it.
suite_of() {
  awk '
    /^  Candidate:/ { cand = $2; next }
    cand == "" { next }
    {
      v = ($1 == "***") ? $2 : $1
      if (v == cand && !seen) { seen = 1; next }
      if (seen) {
        if ($1 ~ /^[0-9]+$/ && $2 ~ /^(https?|ftp|file|cdrom|mirror)/) {
          split($3, a, "/"); print a[1]; exit
        }
        if ($1 ~ /^[0-9]+$/ && $2 ~ /dpkg\/status$/) { print "local-only"; exit }
        if ($1 ~ /^[0-9]+$/ || $1 == "***") { exit }
      }
    }
  '
}

missing=0
leaked=0
for p in "$@"; do
  policy=$(apt-cache policy "$p" 2>/dev/null)
  # `apt-cache policy` on a name apt has never heard of prints nothing at all,
  # so an empty candidate and the literal "(none)" both mean unavailable.
  cand=$(printf '%s\n' "$policy" | awk '/^  Candidate:/{print $2; exit}')
  if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
    printf 'MISSING   %s\n' "$p"
    missing=$((missing + 1))
    continue
  fi

  suite=$(printf '%s\n' "$policy" | suite_of)
  flag=ok
  case "$suite" in
    *-backports)
      case "$bp_allowed" in
        *",$p,"*) ;;
        *) flag=LEAK; leaked=$((leaked + 1)) ;;
      esac
      ;;
  esac
  printf '%-9s %-26s %-24s %s\n' "$flag" "$p" "$cand" "${suite:-?}"
done

echo
if [ "$leaked" -gt 0 ]; then
  printf '%d package(s) marked LEAK: apt would take them from backports and they are\n' "$leaked"
  echo "not in packages/backports.list. The pin in install/10-sources.sh is too wide."
fi
if [ "$missing" -gt 0 ]; then
  printf '%d of %d names do not resolve on %s.\n' "$missing" "$#" "$arch"
  echo "If any were added to Debian recently, run 'sudo apt-get update' here and retry"
  echo "before concluding the name is wrong."
fi
[ "$missing" -eq 0 ] && [ "$leaked" -eq 0 ] || exit 1
printf 'all %d package names resolve on %s, and only the backports.list ones come\n' "$#" "$arch"
echo "from trixie-backports."
REMOTE
