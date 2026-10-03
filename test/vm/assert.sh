#!/bin/bash
# Assertions against a container that install.sh has just run in.
# Invoked by nspawn-install.sh; expects ROOT and TESTUSER in the environment.

set -uo pipefail

ROOT=${ROOT:?}
TESTUSER=${TESTUSER:?}
pass=0 fail=0

ok()   { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

file_exists() { [[ -e "$ROOT$1" ]] && ok "exists: $1" || bad "missing: $1"; }

file_contains() {
  if [[ -f "$ROOT$1" ]] && grep -q -- "$2" "$ROOT$1"; then
    ok "$1 contains '$2'"
  else
    bad "$1 does not contain '$2'"
  fi
}

pkg_installed() {
  if sudo systemd-nspawn -q -D "$ROOT" --pipe /bin/bash -c \
      "dpkg-query -W -f='\${db:Status-Status}' '$1' 2>/dev/null | grep -q '^installed$'"; then
    ok "package installed: $1"
  else
    bad "package not installed: $1"
  fi
}

echo "--- apt configuration ---"
file_exists /etc/apt/sources.list.d/omakeb-backports.sources
file_exists /etc/apt/preferences.d/omakeb-backports
file_contains /etc/apt/preferences.d/omakeb-backports "Pin-Priority: 100"
file_contains /etc/apt/preferences.d/omakeb-backports "Pin-Priority: 500"

echo "--- the pin resolves as intended ---"
# The whole point of the pinning: hyprland from backports, everything else from
# main. A candidate coming from the wrong suite is the failure this catches.
if sudo systemd-nspawn -q -D "$ROOT" --pipe /bin/bash -c \
    "apt-cache policy hyprland | grep -q trixie-backports"; then
  ok "hyprland candidate comes from trixie-backports"
else
  bad "hyprland candidate is not from trixie-backports"
fi

if sudo systemd-nspawn -q -D "$ROOT" --pipe /bin/bash -c \
    "apt-cache policy waybar | awk '/Candidate:/{print \$2}' | grep -qv bpo"; then
  ok "waybar candidate is not from backports (pin is not leaking)"
else
  bad "waybar is being pulled from backports; the global 100 pin is not working"
fi

echo "--- packages ---"
for p in hyprland waybar fuzzel mako-notifier kitty greetd uwsm; do pkg_installed "$p"; done

echo "--- portal configuration ---"
# /etc, which xdg-desktop-portal reads before XDG_DATA_DIRS. /usr/share is
# package-owned space; install/30-desktop.sh explains why it moved.
file_exists /etc/xdg-desktop-portal/hyprland-portals.conf
file_contains /etc/xdg-desktop-portal/hyprland-portals.conf "default=hyprland;gtk"

echo "--- hyprland config parses ---"
# `Hyprland --verify-config` parses the whole tree — every sourced file and all
# ~141 bindings — and exits non-zero on any error, with no GPU, no seat and no
# display. It is the only way to prove the bindings are real without booting a
# session, and it caught `togglesplit` (removed as a standalone dispatcher in
# 0.55, now a dwindle layoutmsg) that no amount of linting would have found.
verify_out=$(sudo systemd-nspawn -q -D "$ROOT" -u "$TESTUSER" --chdir="/home/$TESTUSER" --pipe \
  /bin/bash -c 'export XDG_RUNTIME_DIR=/tmp/xdgrt HOME=$HOME; mkdir -p "$XDG_RUNTIME_DIR"; Hyprland --verify-config 2>&1' || true)

if grep -q '^config ok' <<<"$verify_out"; then
  ok "Hyprland --verify-config: config ok"
else
  bad "Hyprland --verify-config reported errors:"
  sed -n '/Config parsing result/,$p' <<<"$verify_out" | sed 's/^/        /' | head -20
fi

echo "--- theme rendered ---"
# install/70-theme.sh renders templates/*.tpl from the active palette. These
# files are not written by 60-config.sh any more, so their absence here means
# the theme step did not run — and ~/.config/hypr/colors.conf missing is a hard
# Hyprland config error, not a cosmetic one.
for f in .config/hypr/colors.conf .config/hypr/hyprlock.conf \
         .config/waybar/style.css .config/mako/config \
         .config/fuzzel/fuzzel.ini .config/kitty/kitty.conf \
         .config/btop/themes/omakeb.theme .config/gtk-3.0/gtk.css \
         .config/starship.toml; do
  file_exists "/home/$TESTUSER/$f"
done

# C3 depends on this section existing: without it `makoctl mode -s
# do-not-disturb` sets a mode that does nothing.
file_contains "/home/$TESTUSER/.config/mako/config" "\[mode=do-not-disturb\]"

# hyprlang truncates every line at an unescaped '#', so a colour written the CSS
# way is silently dropped and the previous one stays. test/lint-theme.py asserts
# this on the rendered output; assert it again on the machine where the files
# are actually parsed, since a user template could reintroduce it.
hypr_hashes=$(cat "$ROOT/home/$TESTUSER/.config/hypr/colors.conf" \
                  "$ROOT/home/$TESTUSER/.config/hypr/hyprlock.conf" 2>/dev/null |
              grep -vE '^[[:space:]]*#[^#]*$' | grep -n '#' || true)
if [[ -z $hypr_hashes ]]; then
  ok "rendered Hyprland colours carry no line-truncating '#'"
else
  bad "a '#' outside a comment in a rendered hyprlang file:"
  printf '        %s\n' "$hypr_hashes"
fi

# A template that names a token the palette does not define aborts the render,
# so a placeholder reaching disk would mean the substituter let one through.
leftover=$(grep -rl '{{' "$ROOT/home/$TESTUSER/.config/hypr/colors.conf" \
             "$ROOT/home/$TESTUSER/.config/waybar/style.css" \
             "$ROOT/home/$TESTUSER/.config/fuzzel/fuzzel.ini" 2>/dev/null || true)
if [[ -z $leftover ]]; then
  ok "no unsubstituted placeholders in the rendered config"
else
  bad "unsubstituted placeholders in: $leftover"
fi

echo "--- every command is reachable ---"
# 40-shell.sh symlinks bin/omakeb-* into ~/.local/bin, and the session PATH
# contains only that directory. A command added to bin/ after the last install
# gets no link, and every exec-once or keybinding naming it silently does
# nothing — Hyprland does not report a failed exec. That is exactly how the
# GL fallback shipped broken, so assert the invariant.
unlinked=$(sudo systemd-nspawn -q -D "$ROOT" -u "$TESTUSER" --chdir="/home/$TESTUSER" --pipe \
  /bin/bash -c 'n=0; for f in ~/omakeb/bin/omakeb-*; do
      [ -e "$HOME/.local/bin/$(basename "$f")" ] || { echo "$(basename "$f")"; n=$((n+1)); }
    done; exit 0' 2>/dev/null || true)
if [[ -z $unlinked ]]; then
  ok "all bin/omakeb-* commands are linked into ~/.local/bin"
else
  bad "commands in bin/ with no link in ~/.local/bin (they will silently no-op):"
  printf '        %s\n' $unlinked
fi

echo "--- idempotency ---"
# The second run must change nothing. This is the property that makes
# install.sh safe as a repair tool, and it is easy to break.
second=$(sudo systemd-nspawn -q -D "$ROOT" --resolv-conf=copy-host -u "$TESTUSER" \
  --chdir="/home/$TESTUSER" --pipe /bin/bash -lc \
  'bash ~/omakeb/install.sh 2>&1' || echo "SECOND_RUN_FAILED")

if grep -q SECOND_RUN_FAILED <<<"$second"; then
  bad "second install.sh run failed"
elif grep -qE '^\s+wrote: ' <<<"$second"; then
  bad "second run rewrote files that should have been unchanged:"
  grep -E '^\s+wrote: ' <<<"$second" | sed 's/^/        /'
else
  ok "second run is a no-op (nothing rewritten)"
fi

echo
echo "$pass passed, $fail failed"
exit $(( fail > 0 ))
