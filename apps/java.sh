# shellcheck shell=bash
app_name="Java (OpenJDK)"
app_summary="Debian's default JDK — OpenJDK 21 LTS — plus Maven."
app_tier=1
# Tier 1: this is Debian's own package on every architecture Debian builds for,
# so the list is "whatever apt has", which install/10-sources.sh already proves.
# Named explicitly anyway because the app runner requires the field.
app_archs="amd64 arm64 armhf armel i386 ppc64el riscv64 s390x"

# WHICH JDK, since the question comes up every time: `default-jdk`.
#
# It is a metapackage pointing at whatever OpenJDK Debian has decided is right
# for this release — openjdk-21-jdk in trixie, which is the current LTS. Naming
# `openjdk-21-jdk` directly would pin the machine to 21 forever and hand us the
# job of noticing when Debian moves; `default-jdk` makes the release's
# maintainers responsible for that, which is the whole reason to be on Debian.
#
# trixie also has openjdk-25-jdk if a project needs it. Install it alongside;
# `update-alternatives --config java` switches between them. We do not install
# it here because two JDKs by default is a surprising thing to do to someone.
#
# Not installed either: `gradle`, which trixie ships at 4.4.1 — six years old
# and unable to build most modern projects. Gradle's own wrapper (`./gradlew`)
# is how Gradle expects to be run and needs nothing from us.
app_installed() { pkg_installed default-jdk; }

app_install() {
  apt_install default-jdk maven
  log_info "java: $(java --version 2>/dev/null | head -1)"
  log_info "other JDKs:  sudo apt install openjdk-25-jdk"
  log_info "switch with: sudo update-alternatives --config java"
}

app_remove() { apt_purge default-jdk maven; }
