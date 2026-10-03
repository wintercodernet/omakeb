#!/bin/bash
# Tier-2 and tier-3 optional software.
#
# Each app is one file in apps/ declaring metadata and four functions. The
# runner (bin/omakeb-install-app) sources it, checks the architecture, and calls
# install or remove. See D4 and D10.
#
#   app_name="Visual Studio Code"    # shown in the menu
#   app_tier=2                       # 2 = upstream apt repo, 3 = download
#   app_archs="amd64 arm64"          # dpkg names the upstream ACTUALLY ships
#   app_summary="..."                # one line
#   app_installed() { ... }          # exit 0 if present
#   app_install()   { ... }
#   app_remove()    { ... }
#
# shellcheck shell=bash

# --- architecture gate --------------------------------------------------------
# D9 forbids allowlists for the base, but tier 2 is different: a third-party
# repo genuinely does not exist for some architectures, and apt cannot tell us
# that before we have added the source. Edge is the live example — its arm64
# index exists and contains zero packages, so a naive "add repo then install"
# leaves a broken source behind and fails with an unhelpful message.
app_supports_arch() {
  local arch
  arch=$(arch_dpkg)
  [[ " ${app_archs:-} " == *" $arch "* ]]
}

# --- upstream apt repositories ------------------------------------------------
# repo_add <name> <key-url> <uri> <suite> <components> [architectures]
#
# Architectures is pinned explicitly so apt never fetches an index that does not
# exist for this machine, which is what produces the "failed to fetch ... 404"
# noise on every subsequent apt update.
# Can apt actually use this source? Checked against THIS source alone, in a
# sourceparts directory containing nothing else, so the answer is about the
# repository we just added and not about the state of the rest of the machine.
#
# List-Cleanup=0 matters: without it apt treats every other repository as gone
# and deletes its lists.
repo_usable() {
  local source=$1 dir out rc
  dir=$(mktemp -d)
  cp "$source" "$dir/" 2>/dev/null || sudo cp "$source" "$dir/"
  chmod 0644 "$dir"/* 2>/dev/null || true

  out=$(sudo "${APT_ENV[@]}" apt-get update \
          -o Dir::Etc::sourcelist=/dev/null \
          -o Dir::Etc::sourceparts="$dir" \
          -o APT::Get::List-Cleanup=0 2>&1)
  rc=$?
  rm -rf "$dir"

  # Both, because apt is not consistent about which failures are fatal: a
  # signature it cannot verify is reported as an error and still exits 0 on some
  # versions.
  if (( rc != 0 )); then return 1; fi
  ! grep -qiE 'is not signed|NO_PUBKEY|GPG error|Failed to fetch|does not have a Release file' <<<"$out"
}

repo_add() {
  local name=$1 key_url=$2 uri=$3 suite=$4 components=$5
  local architectures=${6:-$(arch_dpkg)}
  local keyring=/usr/share/keyrings/omakeb-$name.gpg
  local source=/etc/apt/sources.list.d/omakeb-$name.sources
  local keyring_existed=

  apt_install curl ca-certificates gnupg

  if sudo test -s "$keyring"; then
    keyring_existed=1
    log_skip "signing key already present: $keyring"
  else
    local tmp
    tmp=$(mktemp)
    # Fail loudly on a captive portal or a 404: an HTML error page dearmors into
    # a keyring that silently verifies nothing.
    curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --max-time 60 "$key_url" -o "$tmp" ||
      { rm -f "$tmp"; die "could not download signing key for $name from $key_url"; }

    # Upstreams serve both forms and neither is wrong: Microsoft and Docker ship
    # ASCII armour, Spotify ships raw binary. Dearmouring armour is required;
    # dearmouring binary is not, so only do it when there is armour to remove.
    if grep -qa 'BEGIN PGP PUBLIC KEY BLOCK' "$tmp"; then
      gpg --dearmor < "$tmp" > "$tmp.gpg" 2>/dev/null ||
        { rm -f "$tmp" "$tmp.gpg"; die "signing key for $name is armoured but will not dearmor"; }
    else
      cp "$tmp" "$tmp.gpg"
    fi

    # Ask gpg whether the result is a key at all, rather than trusting the
    # transfer. This is what catches a captive portal or a moved URL, in either
    # format, before the bytes become a keyring that verifies nothing.
    if ! gpg --show-keys "$tmp.gpg" >/dev/null 2>&1; then
      rm -f "$tmp" "$tmp.gpg"
      die "signing key for $name is not a valid PGP key (captive portal or moved URL?)"
    fi

    sudo install -D -m 0644 "$tmp.gpg" "$keyring"
    rm -f "$tmp" "$tmp.gpg"
    log_ok "installed signing key: $keyring"
  fi

  write_file_sudo "$source" 0644 <<SOURCE
# Managed by omakeb ($name). Edits will be overwritten.
Types: deb
URIs: $uri
Suites: $suite
Components: $components
Architectures: $architectures
Signed-By: $keyring
SOURCE

  # Prove it works BEFORE it becomes everyone else's problem.
  #
  # A source apt cannot verify does not just fail this install: it fails every
  # apt operation on the machine afterwards, because `apt-get update` reports the
  # error for the broken repository no matter what is being installed. Leaving it
  # behind is how one failed optional app takes out the next two unrelated ones —
  # which is exactly what a stale Spotify key did.
  #
  # So on failure, put the machine back the way it was and say so.
  if ! repo_usable "$source"; then
    sudo rm -f "$source"
    # The keyring goes too, even if it was already here. A keyring that cannot
    # verify its own repository is worth nothing, and keeping it is actively
    # harmful: the download above is skipped when the file exists, so a stale key
    # left in place makes every retry skip the fetch and fail in exactly the same
    # way. Discarding it means running the command again actually re-fetches.
    sudo rm -f "$keyring"
    apt_updated=
    apt_refresh
    die "the $name repository could not be verified and has been removed again.

apt is back to the state it was in before this ran, so other software still
installs. The usual cause is a signing key that upstream has rotated:

    key: $key_url
    repo: $uri $suite $components

The signing key has been discarded as well, so running this again will fetch a
fresh one — worth trying once before anything else.

If it still fails, ask the repository which key signs it and update the app
definition to match:
    curl -fsSL $uri/dists/$suite/InRelease | gpg --verify"
  fi

  apt_updated=
  apt_refresh
}

# repo_remove <name> — drop the source, keep the keyring (cheap, and re-adding
# the app is the common case).
repo_remove() {
  local name=$1
  local source=/etc/apt/sources.list.d/omakeb-$name.sources
  if sudo test -f "$source"; then
    sudo rm -f "$source"
    apt_updated=
    log_ok "removed apt source: $source"
  fi
}

# Some upstream packages drop their own sources.list entry in postinst (VS Code
# does). Two files for one repo makes apt warn "configured multiple times" on
# every update, so stand ours down once theirs exists.
repo_yield_to_vendor() {
  local name=$1; shift
  local ours=/etc/apt/sources.list.d/omakeb-$name.sources
  local theirs
  for theirs in "$@"; do
    if sudo test -f "$theirs" && sudo test -f "$ours"; then
      sudo rm -f "$ours"
      log_info "$(basename "$theirs") is now managed by the vendor package; removed ours"
      return 0
    fi
  done
}

apt_purge() {
  local missing=()
  for p in "$@"; do
    pkg_installed "$p" && missing+=("$p")
  done
  (( ${#missing[@]} )) || { log_skip "not installed: $*"; return 0; }
  sudo "${APT_ENV[@]}" apt-get purge -y -qq "${missing[@]}" >/dev/null
  log_ok "removed: ${missing[*]}"
}

# --- Debian components (contrib, non-free) ------------------------------------
#
# Some optional software is in the Debian archive itself, just not in a
# component the base install enables — the netinst gives us `main
# non-free-firmware` and nothing else. Steam (contrib) is the live example.
#
# /etc/apt/sources.list is NOT edited. Instead we own one additive deb822 file
# carrying the SAME URIs and suites as the base install but only the EXTRA
# components, so enabling is a file write and disabling is a file delete, with
# the user's own sources untouched either way.
#
# The security suite is included deliberately. It is a separate host and a
# separate suite, and leaving it out is not a cosmetic omission: contrib
# packages would then receive no security updates at all, which for something
# with Steam's attack surface is the whole point of the exercise.
#
# The mirror is deb.debian.org for the same reason install/10-sources.sh uses
# it for backports — it is the official CDN and preflight already checks that it
# resolves. A machine whose base sources point at a country mirror ends up
# fetching these extra components from the CDN instead, which is correct, just
# not the same host.
OMAKEB_COMPONENTS_SOURCE=/etc/apt/sources.list.d/omakeb-components.sources

# Normalise a component list: deduplicated, sorted, space separated. Storing it
# sorted is what makes "did this change anything?" a string comparison.
_components_normalise() {
  printf '%s\n' "$@" | sed '/^[[:space:]]*$/d' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

_components_current() {
  sudo test -f "$OMAKEB_COMPONENTS_SOURCE" || return 0
  sudo sed -n 's/^Components:[[:space:]]*//p' "$OMAKEB_COMPONENTS_SOURCE" | head -1
}

_components_write() {
  local components=$1

  if [[ -z $components ]]; then
    if sudo test -f "$OMAKEB_COMPONENTS_SOURCE"; then
      sudo rm -f "$OMAKEB_COMPONENTS_SOURCE"
      log_ok "removed apt source: $OMAKEB_COMPONENTS_SOURCE"
      apt_updated=
      apt_refresh
    fi
    return 0
  fi

  # The suites are the release omakeb targets (lib/release.sh), not whatever
  # this machine happens to run. On any other release they would be wrong in
  # both directions — trixie suites on forky are the previous release's
  # archive, and sid has no -updates or -security suite at all — so refuse
  # rather than write them. Removal above stays allowed: taking our own file
  # away is always safe. Same D13 line as bin/omakeb-update: report, don't
  # adapt apt sources to a release omakeb was not written for.
  local running
  running=$(release_codename)
  if [[ $running != "$OMAKEB_DEBIAN_CODENAME" ]]; then
    log_error "not enabling apt components ($components): this machine runs Debian '${running:-unknown}', and omakeb only knows the $OMAKEB_DEBIAN_CODENAME suites."
    log_info "Enable them by hand in your own apt sources if you need them."
    return 1
  fi

  write_file_sudo "$OMAKEB_COMPONENTS_SOURCE" 0644 <<SOURCE
# Managed by omakeb. Edits will be overwritten.
#
# Additive only: the same URIs and suites as the base install, carrying just the
# extra components. Delete this file to go back to exactly what Debian's
# installer configured.
Types: deb
URIs: http://deb.debian.org/debian
Suites: $OMAKEB_DEBIAN_CODENAME $OMAKEB_DEBIAN_CODENAME-updates
Components: $components
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $OMAKEB_DEBIAN_CODENAME-security
Components: $components
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCE

  apt_updated=
  apt_refresh
}

# debian_component_enable <component>...
#
# Additive and idempotent: components already enabled by an earlier app are
# merged rather than replaced, so two apps asking for different components do
# not clobber each other.
debian_component_enable() {
  local current merged
  current=$(_components_current)
  merged=$(_components_normalise $current "$@")

  if [[ $merged == "$current" ]]; then
    log_skip "apt components already enabled: $*"
    return 0
  fi

  _components_write "$merged"
  log_ok "enabled apt components: $merged"
}

# debian_component_disable <component>...
#
# The remove path. Note that no app_remove calls this: by the time an app is
# removed, other packages may have been installed from the same component, and
# taking it away would strand them without updates. It exists so the mechanism
# is reversible by hand, and so enabling is not a one-way door.
debian_component_disable() {
  local current merged c drop keep=() skip
  current=$(_components_current)
  if [[ -z $current ]]; then
    log_skip "no omakeb-managed apt components are enabled"
    return 0
  fi

  for c in $current; do
    skip=
    for drop in "$@"; do
      [[ $c == "$drop" ]] && skip=1
    done
    [[ -n $skip ]] || keep+=("$c")
  done

  merged=$(_components_normalise ${keep[@]+"${keep[@]}"})
  if [[ $merged == "$current" ]]; then
    log_skip "apt components not enabled by omakeb: $*"
    return 0
  fi

  _components_write "$merged"
  [[ -n $merged ]] && log_ok "apt components now: $merged"
  return 0
}

# --- foreign architectures (multiarch) ----------------------------------------
#
# WARNING, because this is not free: adding a foreign architecture roughly
# doubles the number of index files apt fetches on every `apt update` — a
# Packages index per component per architecture — and makes the local index
# cache correspondingly larger. Add one only when a package genuinely requires
# it, never speculatively.

# multiarch_enable <arch>
#
# Idempotent via dpkg's own record of which foreign architectures are enabled.
# The apt refresh afterwards is mandatory, not tidiness: dpkg only records the
# architecture, so until the indices are fetched every package for it looks
# uninstallable and the install that motivated this fails with "unable to
# locate package".
multiarch_enable() {
  local arch=$1
  [[ -n $arch ]] || { log_warn "multiarch_enable: no architecture given"; return 1; }

  if dpkg --print-foreign-architectures 2>/dev/null | grep -qx -- "$arch"; then
    log_skip "foreign architecture already enabled: $arch"
    return 0
  fi

  sudo dpkg --add-architecture "$arch"
  log_ok "enabled foreign architecture: $arch"
  apt_updated=
  apt_refresh
}

# multiarch_disable <arch>
#
# The remove path, again not called by any app_remove — see the note on
# debian_component_disable. dpkg refuses while packages built for the
# architecture are still installed, which is the correct behaviour and is
# reported rather than forced.
multiarch_disable() {
  local arch=$1
  [[ -n $arch ]] || { log_warn "multiarch_disable: no architecture given"; return 1; }

  if ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx -- "$arch"; then
    log_skip "foreign architecture not enabled: $arch"
    return 0
  fi

  if sudo dpkg --remove-architecture "$arch" 2>/dev/null; then
    log_ok "disabled foreign architecture: $arch"
    apt_updated=
    apt_refresh
  else
    log_warn "kept foreign architecture $arch: packages built for it are still installed"
  fi
}


# ==============================================================================
# Tier 3 — software that is not in any apt repository
# ==============================================================================
#
# D4 is explicit about the cost: tier 3 receives security updates from nobody.
# So the rules are keep it short, record what version is on the machine, and be
# able to report staleness. Everything below exists to make those three things
# automatic rather than a thing each app file remembers to do.
#
# Nothing here writes outside $HOME except through apt. A tier-3 app that needed
# root would be a tier-3 app we should not ship.

# Where a tier-3 app records what it installed. `omakeb-update` reads these.
tier3_version_set() { state_set "app-version/$1" "$2"; }
tier3_version_get() { state_get "app-version/$1"; }

# --- npm-based command-line tools ---------------------------------------------
#
# Debian's nodejs (20.x in trixie) and npm, with a per-user prefix, and never
# `sudo npm`. Three reasons, in order of how much they matter:
#
#   1. `sudo npm install -g` runs arbitrary package install scripts as root.
#   2. It writes into /usr/local, which dpkg does not own, so the files survive
#      every uninstall path a user would think to try.
#   3. With --prefix "$HOME/.local" the binaries land in ~/.local/bin, which
#      install/40-shell.sh already put on PATH for both the shell and the
#      Hyprland session. Nothing extra has to be configured.
#
# The prefix is passed per command rather than written into ~/.npmrc: npm config
# is the user's, and an omakeb app has no business changing where THEIR
# `npm install -g` goes.
#
# npm_tool_install <app-id> <npm-package> <binary>
npm_tool_install() {
  local id=$1 pkg=$2 bin=$3 version

  apt_install nodejs npm

  # Refuse rather than half-install: a tool whose engines field excludes
  # Debian's node will install happily and then fail at run time, which is a
  # much worse thing to hand someone than a clear message now.
  #
  # Every `x=$(… | grep -o … | head -1)` below carries `|| true`, and that is not
  # decoration. The runner is `set -euo pipefail` and app_install is called from
  # an untested position, so a grep that matches nothing makes the assignment a
  # failing statement and ends the script with no message. A package with no
  # engines field is the ordinary case, not the odd one.
  local node_major required
  node_major=$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/') || true
  required=$(npm view "$pkg" engines.node 2>/dev/null | grep -oE '[0-9]+' | head -1) || true
  if [[ -n $required && -n $node_major ]] && (( node_major < required )); then
    log_error "$pkg needs node >= $required; Debian trixie has $(node --version)."
    log_warn "Not installing. This is the tier-1 ceiling (D13) showing up in practice:"
    log_warn "either the tool ships a self-contained binary, or it is not installable"
    log_warn "here without a second node from outside Debian."
    return 1
  fi

  log_info "installing $pkg into ~/.local (no sudo, no /usr/local)"
  # @latest explicitly, because `omakeb-install-app upgrade` comes through here
  # too and must move an installed package forward rather than leave it be.
  NPM_CONFIG_PREFIX="$HOME/.local" npm install -g --no-fund --no-audit "$pkg@latest" >/dev/null || {
    log_error "npm could not install $pkg"
    return 1
  }

  command -v "$bin" >/dev/null 2>&1 ||
    log_warn "$pkg installed but '$bin' is not on PATH; open a new shell"

  # Record what npm installed, read from the package itself, because that is the
  # string `npm view <pkg> version` will be compared against by the staleness
  # report. The binary's own --version is only the fallback: tools print it in
  # their own formats and some drop pre-release suffixes, which would make an
  # up-to-date tool look permanently stale.
  #
  # This runs AFTER the tool is on disk, so a failure here must never end the
  # script: that is the "work done, nothing recorded" ordering state_set was
  # fixed for. Hence `|| true` again, and "unknown" rather than nothing.
  version=$(npm_installed_version "$pkg") || true
  if [[ -z $version ]]; then
    local bin_path
    bin_path=$(command -v "$bin" 2>/dev/null) || bin_path="$HOME/.local/bin/$bin"
    version=$("$bin_path" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
  fi
  tier3_version_set "$id" "${version:-unknown}"
  log_ok "$bin ${version:-installed}"
}

# The version npm has installed under our per-user prefix, or non-zero.
npm_installed_version() {
  local manifest="$HOME/.local/lib/node_modules/$1/package.json" v
  [[ -f $manifest ]] || return 1
  v=$(node -p 'require(process.argv[1]).version' "$manifest" 2>/dev/null) || true
  [[ -n $v && $v != undefined ]] || return 1
  printf '%s\n' "$v"
}

# The newest version of an npm package, or non-zero. Used by app_latest, which
# omakeb-update calls on every run, so it is bounded: one attempt, a short
# timeout, never a retry loop that holds the update hostage to a dead network.
npm_latest_version() {
  command -v npm >/dev/null 2>&1 || return 1
  local v
  v=$(npm view "$1" version --fetch-retries=0 --fetch-timeout=15000 2>/dev/null | tail -1) || true
  [[ $v =~ ^[0-9]+\.[0-9]+ ]] || return 1
  printf '%s\n' "$v"
}

npm_tool_remove() {
  local id=$1 pkg=$2
  NPM_CONFIG_PREFIX="$HOME/.local" npm uninstall -g "$pkg" >/dev/null 2>&1 ||
    log_warn "npm reported a problem removing $pkg"
  rm -f "$OMAKEB_STATE/app-version/$id"
  log_ok "removed $pkg"
}

npm_tool_installed() { command -v "$1" >/dev/null 2>&1; }

# --- a .deb published outside Debian ------------------------------------------
#
# Installed with `apt install ./file.deb` rather than `dpkg -i`, so apt resolves
# the dependencies instead of leaving the package half-configured and the next
# unrelated apt run broken.
#
# deb_install_url <app-id> <url> <version>
deb_install_url() {
  local id=$1 url=$2 version=$3 tmp file
  tmp=$(mktemp -d) || return 1
  file="$tmp/${url##*/}"

  log_info "downloading ${url##*/}"
  if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --max-time 300 -o "$file" "$url"; then
    rm -rf "$tmp"
    log_error "could not download $url"
    return 1
  fi
  # A captive portal or a 404 page saved to disk is not a .deb, and dpkg's
  # error for that is unhelpful. Check before handing it to apt.
  if ! dpkg-deb --info "$file" >/dev/null 2>&1; then
    rm -rf "$tmp"
    log_error "what was downloaded is not a Debian package; upstream may have moved the file"
    return 1
  fi

  sudo "${APT_ENV[@]}" apt-get install -y -qq "$file" >/dev/null || {
    rm -rf "$tmp"
    log_error "apt could not install ${url##*/}"
    return 1
  }
  rm -rf "$tmp"
  tier3_version_set "$id" "$version"
}

# The newest release tag of a GitHub repository, without a token.
#
# Returns non-zero rather than an empty string on failure, so a caller cannot
# accidentally build a download URL containing the word "null".
github_latest_tag() {
  local repo=$1 tag
  # `|| true` so that a failed fetch is this function's non-zero return, not a
  # pipefail abort of whoever called it from an untested position.
  tag=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null |
        jq -r '.tag_name // empty' 2>/dev/null) || true
  [[ -n $tag ]] || return 1
  printf '%s\n' "$tag"
}

# ==============================================================================
# Loading an app definition, and the tier-3 staleness report
# ==============================================================================
#
# app_load <id> — source apps/<id>.sh into THIS shell. Callers that look at more
# than one app do it in a subshell each, so one file's declarations can never
# leak into the next. Returns non-zero if there is no such app, and leaves the
# message to the caller: the runner dies, the report just says so.
#
# Optional hooks beyond the four in the header of this file:
#
#   app_latest()          # tier 3: print the newest upstream version, non-zero
#                         # on failure. Called on every omakeb-update, so it
#                         # must be cheap, bounded and never need sudo.
#   app_self_updating=1   # tier 3: upstream updates itself; there is nothing
#                         # for omakeb to compare or upgrade.
#
# test/lint-apps.sh insists every tier-3 app has one or the other.
app_load() {
  local file="${OMAKEB_APPS_DIR:-$OMAKEB_PATH/apps}/$1.sh"
  [[ -f $file ]] || return 1
  app_name= app_summary= app_tier= app_archs= app_self_updating=
  unset -f app_installed app_install app_remove app_latest
  # shellcheck source=/dev/null
  source "$file"
}

# tier3_report — one line per recorded app-version/<id>: installed vs latest.
#
# This is D4's mitigation, so it has to survive the conditions it runs in: it
# is called from omakeb-update under `set -euo pipefail`, often offline, against
# state an older omakeb may have written for an app that no longer exists. Every
# one of those is a line of output, never a failed update. Each app is looked at
# in its own subshell, so a broken app file costs its own line and no more.
tier3_report() {
  local f id found=
  for f in "$OMAKEB_STATE"/app-version/*; do
    [[ -f $f ]] || continue
    found=1
    id=${f##*/}
    ( _tier3_report_one "$id" "$(tier3_version_get "$id")" ) </dev/null ||
      log_warn "$id: could not be checked"
  done
  [[ -n $found ]] || log_skip "no tier-3 apps installed"
  return 0
}

_tier3_report_one() {
  local id=$1 recorded=${2:-unknown} name latest
  if ! app_load "$id"; then
    log_info "$id: $recorded recorded, but omakeb no longer defines this app"
    return 0
  fi
  name=${app_name:-$id}
  if ! app_installed >/dev/null 2>&1; then
    log_info "$name: $recorded recorded, but it is no longer installed"
  elif [[ -n ${app_self_updating:-} ]]; then
    log_info "$name: $recorded when installed; it updates itself"
  elif ! declare -F app_latest >/dev/null; then
    log_info "$name: $recorded (no way to check upstream is defined)"
  elif ! latest=$(app_latest 2>/dev/null) || [[ -z $latest ]]; then
    log_info "$name: $recorded (could not reach upstream to check)"
  elif [[ $latest == "$recorded" ]]; then
    log_ok "$name: $recorded (current)"
  else
    log_warn "$name: $recorded installed, $latest available — omakeb-install-app upgrade $id"
  fi
  return 0
}
