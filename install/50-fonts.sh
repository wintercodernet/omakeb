#!/bin/bash
# Nerd Font symbols — the single tier-3 item in the base install (D8).
#
# Waybar, starship, fuzzel and menu/menu.jsonc all draw icons from the Nerd
# Fonts private-use ranges. Debian packages that font as `fonts-nerd-symbols`,
# but only in sid/forky: it is not in trixie, so there is nothing to apt.
#
# This is the one place in the base install that downloads a file from outside
# the Debian archive, and the exception is deliberate: it is a TTF, so there is
# no executable surface and (D9) no architecture question — the same file is
# correct on every port.
#
# It is also the one step that must never fail the install. A missing icon font
# means tofu boxes in the bar; it does not mean a broken desktop. Every failure
# path here warns and returns.
# shellcheck shell=bash

# Pinned rather than "latest": tier 3 gets no security updates from anyone, so
# the version has to be a thing we chose and can report on, not whatever the
# release feed happened to say the day someone ran the installer. State records
# it so `omakeb update` can report staleness.
NERD_FONTS_VERSION="${OMAKEB_NERD_FONTS_VERSION:-v3.5.1}"
NERD_FONTS_ASSET=NerdFontsSymbolsOnly.tar.xz
NERD_FONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/${NERD_FONTS_ASSET}"

fonts_dir="$HOME/.local/share/fonts"
fontconfig_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"

# fc-cache lives in `fontconfig`, which is not in packages/desktop.list — the
# GUI stack only pulls in libfontconfig1. Without it the font lands on disk and
# is never indexed.
apt_install fontconfig

# The two faces the tarball ships: the proportional one and the fixed-width one
# terminals and bars want.
nerd_font_files=(SymbolsNerdFont-Regular.ttf SymbolsNerdFontMono-Regular.ttf)

nerd_symbols_present() {
  local f
  for f in "${nerd_font_files[@]}"; do
    [[ -f "$fonts_dir/$f" ]] || return 1
  done
  [[ "$(state_get nerd-symbols-version)" == "$NERD_FONTS_VERSION" ]]
}

# Returns non-zero on any failure; the caller turns that into a warning.
# Called from an `if`, which suspends `set -e` for the whole body, so every
# step checks its own exit status explicitly.
install_nerd_symbols() {
  local tmpdir f
  tmpdir=$(mktemp -d) || return 1

  # No published per-asset checksum to verify against, so TLS is the integrity
  # story; --proto and --tlsv1.2 stop a redirect downgrading it. The extract
  # below is the real sanity check: a captive-portal HTML page is not a tarball.
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --max-time 300 \
      -o "$tmpdir/$NERD_FONTS_ASSET" "$NERD_FONTS_URL" || { rm -rf "$tmpdir"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=60 --tries=3 \
      -O "$tmpdir/$NERD_FONTS_ASSET" "$NERD_FONTS_URL" || { rm -rf "$tmpdir"; return 1; }
  else
    rm -rf "$tmpdir"
    return 1
  fi

  # The archive has no top-level directory; it unpacks flat.
  tar -xJf "$tmpdir/$NERD_FONTS_ASSET" -C "$tmpdir" || { rm -rf "$tmpdir"; return 1; }

  for f in "${nerd_font_files[@]}"; do
    [[ -f "$tmpdir/$f" ]] || { rm -rf "$tmpdir"; return 1; }
  done

  for f in "${nerd_font_files[@]}"; do
    install -D -m 0644 "$tmpdir/$f" "$fonts_dir/$f" || { rm -rf "$tmpdir"; return 1; }
  done

  # Upstream ships a fontconfig snippet that makes the symbol face a fallback
  # for sans/serif/monospace. That is what lets waybar, kitty and fuzzel render
  # icon glyphs without any of them naming the font explicitly — so no config we
  # generate has to hardcode "Symbols Nerd Font Mono" in a font stack.
  if [[ -f "$tmpdir/10-nerd-font-symbols.conf" ]]; then
    install -D -m 0644 "$tmpdir/10-nerd-font-symbols.conf" \
      "$fontconfig_dir/10-nerd-font-symbols.conf" || { rm -rf "$tmpdir"; return 1; }
  fi

  rm -rf "$tmpdir"
  return 0
}

if nerd_symbols_present; then
  log_skip "Nerd Font symbols $NERD_FONTS_VERSION already installed"
elif install_nerd_symbols; then
  state_set nerd-symbols-version "$NERD_FONTS_VERSION"
  # Rebuild only this user's cache; the font is in $HOME and nothing system-wide
  # changed. -f forces a re-scan of the directory we just wrote into.
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$fonts_dir" >/dev/null 2>&1 || log_warn "fc-cache failed; icons may not appear until the next login"
  fi
  log_ok "Nerd Font symbols $NERD_FONTS_VERSION installed into $fonts_dir"
else
  log_warn "could not install Nerd Font symbols $NERD_FONTS_VERSION from"
  log_warn "  $NERD_FONTS_URL"
  log_warn "Icons in the bar, the menu and the prompt will render as empty boxes."
  log_warn "Re-run install.sh once networking is working; nothing else is affected."
fi

unset fonts_dir fontconfig_dir nerd_font_files
