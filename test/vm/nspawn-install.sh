#!/bin/bash
# Fast install test: build a throwaway Debian 13 root filesystem and run the
# real install.sh inside it.
#
# Run this INSIDE a Debian machine (the VM), not on the macOS host.
#
# Why a container rather than the VM itself: every run starts from a genuinely
# clean Debian 13, takes about a minute, and cannot leave the VM in a half
# configured state. It exercises preflight, the backports pinning, package
# resolution for the running architecture, and config rendering — which is
# everything except the parts that need a GPU and a reboot.
#
# What it deliberately cannot test: greetd actually starting a session,
# Hyprland launching, and whether any binding works. Those need test/vm/session.md.

set -euo pipefail

ROOT=${ROOT:-/var/tmp/omakeb-test-root}
SUITE=${SUITE:-trixie}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
TESTUSER=${TESTUSER:-omakeb}
REPO_SRC=${REPO_SRC:-$(cd "$(dirname "$0")/../.." && pwd)}

# Reuse omakeb's own sudo keepalive: mmdebstrap plus a full package install can
# easily outlast sudo's 15-minute timestamp, especially on an emulated VM.
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/log.sh"
# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/sudo.sh"
sudo_keepalive_start

for tool in mmdebstrap systemd-nspawn; do
  command -v "$tool" >/dev/null || {
    echo "missing $tool — install with: sudo apt install mmdebstrap systemd-container" >&2
    exit 1
  }
done

echo "==> architecture: $(dpkg --print-architecture)"

# Rebuilding the rootfs costs about two minutes. KEEP_ROOT=1 reuses the existing
# one while iterating on install.sh itself. Never use it to judge a green run:
# only a fresh rootfs proves the install works from a clean Debian.
if [[ ${KEEP_ROOT:-0} == 1 && -d $ROOT ]]; then
  echo "==> reusing existing rootfs at $ROOT (KEEP_ROOT=1)"
else
echo "==> building $SUITE rootfs at $ROOT"
sudo rm -rf "$ROOT"
sudo mmdebstrap \
  --variant=important \
  --include=systemd,systemd-sysv,dbus,sudo,ca-certificates,locales \
  "$SUITE" "$ROOT" "$MIRROR"

fi

echo "==> preparing test user"
sudo systemd-nspawn -q -D "$ROOT" --pipe /bin/bash -euc "
  id '$TESTUSER' >/dev/null 2>&1 || useradd -m -s /bin/bash '$TESTUSER'
  usermod -aG sudo '$TESTUSER'
  # Passwordless sudo so the unattended run does not block on a prompt. This is
  # a throwaway container; do not copy this into the real install.
  echo '$TESTUSER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/omakeb-test
  chmod 0440 /etc/sudoers.d/omakeb-test
  # os-release must look like a real Debian 13 for preflight to accept it.
  grep -q VERSION_ID /etc/os-release || echo 'VERSION_ID=\"13\"' >> /etc/os-release
  # systemd-nspawn names the container after the directory, but nothing maps
  # that name to an address, so every sudo call prints an unable-to-resolve-host
  # warning that buries real output. The name is known host-side, so interpolate
  # it rather than fighting nested quoting.
  grep -q '$(basename "$ROOT")' /etc/hosts || printf '127.0.1.1\t%s\n' '$(basename "$ROOT")' >> /etc/hosts
"

echo "==> copying working tree into the container"
# Deliberately NOT ~/.local/share/omakeb. Installing from the canonical path is
# the easy case; copying there masked a real bug where install.sh assumed that
# location and failed for anyone running it out of a checkout — which is exactly
# what test/vm/README.md tells you to do. Everything must self-locate.
sudo cp -a "$REPO_SRC" "$ROOT/home/$TESTUSER/omakeb"
sudo rm -rf "$ROOT/home/$TESTUSER/omakeb/.git"
sudo systemd-nspawn -q -D "$ROOT" --pipe /bin/bash -euc \
  "chown -R '$TESTUSER:$TESTUSER' /home/$TESTUSER"

echo "==> running install.sh"
# --resolv-conf=copy-host so apt can reach the mirror; -u runs as the test user
# rather than root, which is what preflight requires.
sudo systemd-nspawn -q -D "$ROOT" \
  --resolv-conf=copy-host \
  -u "$TESTUSER" \
  --chdir="/home/$TESTUSER" \
  --pipe \
  /bin/bash -lc 'bash ~/omakeb/install.sh'

echo
echo "==> install finished; running assertions"
sudo ROOT="$ROOT" TESTUSER="$TESTUSER" "$(dirname "$0")/assert.sh"
