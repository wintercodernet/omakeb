# shellcheck shell=bash
app_name="Docker Engine"
app_summary="Docker CE, containerd and the buildx/compose plugins, from Docker's own apt repository."
app_tier=2
# Verified against download.docker.com/linux/debian/dists/trixie/stable, not the
# docs: every architecture listed here carries the full set of packages below.
# The Release file also advertises s390x, which has no containerd.io-dbgsym but
# does have everything we install; it is included for the same reason D9 refuses
# to exclude working ports.
app_archs="amd64 arm64 armhf ppc64el s390x"

# Everything Docker's own "install from the repository" instructions install.
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

app_installed() { pkg_installed docker-ce; }

app_install() {
  repo_add docker \
    https://download.docker.com/linux/debian/gpg \
    https://download.docker.com/linux/debian \
    trixie stable

  apt_install "${DOCKER_PACKAGES[@]}"

  docker_service_enable
  docker_group_grant
}

# The docker-ce package enables and starts its unit in postinst, so this is
# normally a no-op. It matters on a machine where someone disabled the unit, and
# it makes "is the daemon actually running when this script finishes?" an
# answered question rather than an assumption. Neither step is fatal: there is
# no running systemd inside a build container.
docker_service_enable() {
  if [[ "$(systemctl is-enabled docker.service 2>/dev/null)" == "enabled" ]]; then
    log_skip "docker.service already enabled"
  elif sudo systemctl enable docker.service >/dev/null 2>&1; then
    log_ok "enabled docker.service"
  else
    log_warn "could not enable docker.service; check: systemctl status docker"
  fi

  if sudo systemctl start docker.service >/dev/null 2>&1; then
    log_ok "docker.service is running"
  else
    log_warn "could not start docker.service; check: systemctl status docker"
  fi
}

# SECURITY, and the reason this is a named function with a paragraph attached
# rather than a quiet line inside app_install:
#
# Membership of the `docker` group is EQUIVALENT TO ROOT. It grants write access
# to /run/docker.sock, and the daemon behind that socket runs as root and will
# bind-mount any path on the host into a container on request. Anyone in the
# group can therefore read or rewrite any file on the machine — /etc/shadow,
# /etc/sudoers, another user's ssh keys — without ever being asked for a
# password, and without any of it appearing in the sudo log. This is a
# documented property of the design, not a bug, and no amount of container
# configuration takes it away.
#
# We grant it because a Docker install where every command needs sudo is not
# what anyone asking for Docker wants. But we do not grant it silently: the
# warning below goes to the terminal AND to a notification, because the install
# can be launched from the menu where nobody is reading a terminal.
docker_group_grant() {
  local user
  user=$(id -un)

  if ! getent group docker >/dev/null 2>&1; then
    log_warn "the 'docker' group does not exist; skipping the group change"
    log_warn "docker commands will need sudo until you create it and re-run this"
    return 0
  fi

  if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    log_skip "$user is already in the docker group"
  else
    sudo usermod -aG docker "$user" ||
      { log_warn "could not add $user to the docker group"; return 0; }
    log_ok "added $user to the docker group"
  fi

  log_warn "SECURITY: the 'docker' group is equivalent to root on this machine."
  log_warn "The daemon runs as root and will bind-mount any host path into a"
  log_warn "container, so anyone in that group can read or replace any file —"
  log_warn "including /etc/shadow — with no password and no sudo log entry."
  log_warn "Give it only to accounts you would give root to."
  log_warn "The change takes effect at your NEXT LOGIN. Log out and back in, or"
  log_warn "run 'newgrp docker' for this shell only."

  notify-send -a omakeb -u critical \
    -h string:x-canonical-private-synchronous:omakeb-docker \
    "Docker installed" \
    "$user was added to the 'docker' group. That is root-equivalent access: the daemon runs as root and can mount any path on this machine. Log out and back in for it to take effect." \
    2>/dev/null || true
}

app_remove() {
  apt_purge "${DOCKER_PACKAGES[@]}"
  repo_remove docker

  # Revoke the group. Leaving a root-equivalent grant behind after removing the
  # thing that needed it is the one piece of state it would be wrong not to
  # clean up.
  local user
  user=$(id -un)
  if getent group docker >/dev/null 2>&1 &&
     id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    if sudo gpasswd -d "$user" docker >/dev/null 2>&1; then
      log_ok "removed $user from the docker group (effective at next login)"
    else
      log_warn "could not remove $user from the docker group; do it with: sudo gpasswd -d $user docker"
    fi
  fi

  # Images, volumes and containers are user data, so purging the packages
  # deliberately leaves them. Say where they are rather than deleting them.
  log_info "Images, containers and volumes are left in /var/lib/docker and"
  log_info "/var/lib/containerd. Remove them by hand if you want the space back."
}
