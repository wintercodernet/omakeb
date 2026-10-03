# shellcheck shell=bash
app_name="Steam"
app_summary="Valve's game client (steam-installer), from Debian's own contrib component."
# Tier 1, not 2: steam-installer is a Debian package, built and signed by Debian
# and carried in trixie contrib. There is no third-party repository here and no
# third-party key. It lives in apps/ rather than in packages/ because installing
# it needs two system-wide changes that the base install deliberately does not
# make, and neither should happen to someone who never asked for Steam.
app_tier=1
# The package Debian builds is amd64-only. contrib carries no build of it for
# any other architecture, which is a Valve limitation rather than a Debian one:
# the client itself is a 32-bit x86 binary and the package is a wrapper around
# Valve's own bootstrapper.
app_archs="amd64"

app_installed() { pkg_installed steam-installer; }

app_install() {
  # 1. The contrib component. A netinst enables `main non-free-firmware` and
  #    nothing more, so steam-installer is not merely uninstalled — apt has
  #    never seen it. This is additive and includes the security suite, so
  #    contrib gets security updates like everything else.
  debian_component_enable contrib

  # 2. The 32-bit runtime. steam-installer depends on steam-libs-i386, and dpkg
  #    refuses to consider it until i386 is enabled as a foreign architecture.
  #    Named directly rather than derived: this is a stable fact about Steam (a
  #    32-bit x86 client), and enabling a foreign architecture is a system-wide
  #    change that should follow from a literal in a reviewed file, not from
  #    string-matching a Depends field at run time.
  multiarch_enable i386

  # steam-installer pulls in the rest (steam-libs, its 32-bit counterpart,
  # zenity, lsof) through its dependencies, so naming them here would only
  # duplicate the packaging.
  apt_install steam-installer

  log_info "Steam downloads the rest of itself on first launch; expect a wait."
}

app_remove() {
  apt_purge steam-installer

  # DELIBERATELY NOT UNDONE, and this is the interesting half of the function:
  #
  #   - the contrib component stays enabled. It is a system-wide apt setting,
  #     and by now the user may well have installed something else from contrib
  #     — nvidia drivers and firmware live there. Removing it would not uninstall
  #     those, it would just quietly stop them receiving updates, which is a
  #     worse outcome than a component nobody is using.
  #
  #   - the foreign architecture stays enabled, for the same reason plus a
  #     sharper one: other 32-bit packages may be installed by now, and dpkg
  #     would refuse to drop the architecture anyway while they are.
  #
  # Both are reversible by hand: debian_component_disable and multiarch_disable
  # in lib/apps.sh exist precisely so that enabling them is not a one-way door.
  log_info "The contrib component and the 32-bit architecture are left enabled;"
  log_info "other packages may depend on them by now."
  log_info "Steam's 32-bit runtime is now unused: 'sudo apt autoremove' clears it."
  log_info "Your games and Steam login live in ~/.steam and ~/.local/share/Steam"
  log_info "and are left untouched."
}
