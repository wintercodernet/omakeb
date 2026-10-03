#!/bin/bash
# The omakeb theme system: where a palette lives, how it is resolved, how a
# template is rendered from it, and what is allowed in from a third-party theme.
#
# omakeb defines its own theme format (D11). It is deliberately key-compatible
# with the `colors.toml` that Omarchy themes use, because a token is only a
# name and adopting their vocabulary makes an importer nearly free. It is not
# the same thing as "Omarchy theme support", and we never describe it that way:
# what we import is the palette. Their per-app files are ignored, and
# theme_import says so out loud with the reason.
#
#   $OMAKEB_PATH/themes/<name>/       ours, shipped
#   $OMAKEB_CONFIG/themes/<name>/     the user's, including anything imported
#       colors.toml                   the palette
#       origin                        "omakeb" | "omarchy:<url>" | "local:<path>"
#       icons.theme                   optional, one line, validated at set time
#       backgrounds/                  optional
#   $OMAKEB_PATH/templates/*.tpl      ours
#   $OMAKEB_CONFIG/templates/*.tpl    user overrides, processed first
#
# WHERE THE CASCADE LIVES. The alias/fallback cascade and the substituter are
# both in lib/theme.py, and the reason is in that file's header: they need the
# same colour arithmetic, and it is already settled that the
# substituter is python (envsubst mangles CSS braces). Everything shell-shaped
# — locating a theme, the import allowlist, talking to write_file — is here.
#
# shellcheck shell=bash

OMAKEB_THEME_PY="${OMAKEB_PATH:-$HOME/.local/share/omakeb}/lib/theme.py"

# The theme applied when nothing else is recorded and nothing is asked for.
OMAKEB_THEME_DEFAULT=tokyo-night

# A theme name reaches `rm -rf` (the re-import path) and is used as a path
# component, so it is checked before anything touches the filesystem. `..` as a
# name would otherwise take $OMAKEB_CONFIG/themes with it.
theme_name_ok() {
  local name=$1
  [[ -n $name ]] || return 1
  [[ $name != *..* ]] || return 1
  # grep rather than [[ =~ ]] so LC_ALL=C actually applies: a locale can widen
  # [a-z] to match accented and full-width letters, and the point of this check
  # is that the result is a safe path component in any locale.
  LC_ALL=C printf '%s' "$name" | LC_ALL=C grep -qE '^[a-z0-9_][a-z0-9._+-]*$'
}

# theme_dir <name> — the user's copy wins over ours, so an imported theme can
# shadow a shipped one of the same name.
theme_dir() {
  local name=$1 dir
  theme_name_ok "$name" || return 1
  for dir in "$OMAKEB_CONFIG/themes/$name" "$OMAKEB_PATH/themes/$name"; do
    [[ -f "$dir/colors.toml" ]] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

# theme_names — every installed theme, one per line, deduplicated with the
# user's copies shadowing ours. Sorted, because this feeds a picker.
theme_names() {
  local dir name
  {
    for dir in "$OMAKEB_CONFIG/themes"/*/ "$OMAKEB_PATH/themes"/*/; do
      [[ -f "$dir/colors.toml" ]] || continue
      name=$(basename "$dir")
      theme_name_ok "$name" || continue
      printf '%s\n' "$name"
    done
  } 2>/dev/null | sort -u
}

# The active theme's name, or nothing. Deliberately always exits 0: every
# caller assigns it in a command substitution under `set -e`, where a non-zero
# return would take the whole script down on the one machine that has not set a
# theme yet.
theme_current() {
  state_get theme
}

# theme_resolve <theme-dir> — the full palette as KEY<TAB>VALUE.
# Diagnostics go to stderr; a caller that wants them silent redirects.
theme_resolve() {
  python3 "$OMAKEB_THEME_PY" resolve "$1"
}

# theme_templates — every template to render, in the order the renderer must
# see them: user overrides first. lib/theme.py skips a built-in whose output
# name a user template already claimed, which is the rule users expect.
theme_templates() {
  local tpl
  for tpl in "$OMAKEB_CONFIG/templates"/*.tpl "$OMAKEB_PATH/templates"/*.tpl; do
    [[ -f $tpl ]] && printf '%s\n' "$tpl"
  done
  return 0
}

# theme_render <theme-dir> <outdir>
#
# All or nothing. If one template fails the whole render fails and the caller
# must not promote the staging directory: a half-themed desktop is worse than
# the theme we already had.
theme_render() {
  local dir=$1 outdir=$2
  local templates=()
  while IFS= read -r tpl; do templates+=("$tpl"); done < <(theme_templates)
  (( ${#templates[@]} )) || { log_error "no templates found in $OMAKEB_PATH/templates"; return 1; }
  mkdir -p "$outdir"
  python3 "$OMAKEB_THEME_PY" render "$dir" "$outdir" "${templates[@]}" >/dev/null
}

# --- import -------------------------------------------------------------------
#
# THE ALLOWLIST IS THE SECURITY MODEL, and it is the opposite of upstream's.
# They use a denylist because their themes are allowed to ship hand-written
# colour files that override generated ones; their own docs say a denylist is
# only right while it is maintained. We render everything ourselves, so we can
# take the strictly safer position: import these six names and nothing else.
# That removes the entire class of "upstream added a file, forgot to deny it".
THEME_IMPORT_ALLOW=(colors.toml icons.theme preview.png LICENSE README.md)

# Files whose presence is worth explaining rather than passing over in silence.
# They are the names of OUR files, which is exactly why they get imported by
# mistake if nobody says anything.
_theme_import_explain() {
  local src=$1 used=${2:-} f found=
  for f in waybar.css mako.ini fuzzel.ini hyprlock.conf gtk.css walker.css \
           swayosd.css; do
    [[ -e "$src/$f" ]] && found+=" $f"
  done
  if [[ -n $found ]]; then
    log_info "ignored (per-app stylesheets):${found}"
    log_info "  These are Omarchy v1 leftovers, not a current contract. The"
    log_info "  waybar.css files carry two colours where our bar needs eight"
    log_info "  roles, and a theme's mako.ini would replace our layout and drop"
    log_info "  the [mode=do-not-disturb] section the DND toggle depends on."
    log_info "  omakeb renders all of these from the palette instead."
  fi

  found=
  for f in neovim.lua hyprland.lua hyprland.conf gum_env.lua kitty.conf \
           alacritty.toml ghostty.conf foot.ini vscode.json; do
    # Not the file we just read the palette out of: a gen-1 theme's
    # alacritty.toml was the import, and listing it as ignored is a lie.
    [[ $f == "$used" ]] && continue
    [[ -e "$src/$f" ]] && found+=" $f"
  done
  if [[ -n $found ]]; then
    log_info "ignored (code, or config that can run code):${found}"
    log_info "  A theme's hyprland.conf is parsed by our compositor at login and"
    log_info "  a kitty.conf can set 'shell' and 'launch'. Upstream refuses these"
    log_info "  too. Never imported, at any tier of trust."
  fi
}

# _theme_copy_file <src> <dst> [max-bytes]
#
# Explicit, non-recursive, symlink-refusing. NOT `cp -r`: a cloned theme's
# backgrounds/foo.png can be a symlink to ~/.ssh/id_ed25519, and a later
# "share your theme" step would then leak it.
_theme_copy_file() {
  local src=$1 dst=$2 max=${3:-0} size
  if [[ -L $src ]]; then
    log_warn "skipped symlink: $src"
    return 1
  fi
  [[ -f $src ]] || return 1
  if (( max > 0 )); then
    size=$(wc -c < "$src" 2>/dev/null || echo 0)
    if (( size > max )); then
      log_warn "skipped $(basename "$src"): $size bytes is over the ${max}-byte cap"
      return 1
    fi
  fi
  mkdir -p "$(dirname "$dst")"
  cat < "$src" > "$dst"
  chmod 0644 "$dst"
}

# theme_import <src-dir> <dst-dir> <origin>
#
# Palette only. Everything not on the allowlist is named on stderr with the
# reason, because "why does this theme look different on omakeb" deserves an
# answer the user can read at import time rather than a support thread.
theme_import() {
  local src=$1 dst=$2 origin=$3 f name palette_source=

  [[ -d $src ]] || { log_error "not a directory: $src"; return 1; }
  if [[ -L $src ]]; then
    log_error "refusing a symlinked theme directory: $src"
    return 1
  fi

  mkdir -p "$dst"

  # --- the palette ---
  if [[ -f "$src/colors.toml" && ! -L "$src/colors.toml" ]]; then
    _theme_copy_file "$src/colors.toml" "$dst/colors.toml" 262144 ||
      { log_error "could not read $src/colors.toml"; return 1; }
    palette_source=colors.toml
    log_ok "imported colors.toml"
  elif [[ -f "$src/alacritty.toml" && ! -L "$src/alacritty.toml" ]]; then
    # ~29% of the ecosystem predates colors.toml entirely. Back-derive rather
    # than refuse — and say that the result is approximate, because it is: an
    # Alacritty config has 18 colours and no semantic roles at all.
    log_info "no colors.toml; deriving a palette from alacritty.toml"
    log_info "  Approximate by construction — accent, muted, selection and the"
    log_info "  background ramp are derived, not the author's choices."
    python3 "$OMAKEB_THEME_PY" from-alacritty "$src/alacritty.toml" > "$dst/colors.toml" ||
      { rm -f "$dst/colors.toml"; log_error "could not derive a palette"; return 1; }
    palette_source=alacritty.toml
    log_ok "derived colors.toml from alacritty.toml"
  else
    # Deliberately not scraping waybar.css or mako.ini: two colours is not a
    # theme, and guessing produces a desktop nobody chose.
    log_error "no palette found in $src (no colors.toml, no alacritty.toml)"
    return 1
  fi

  # --- icons.theme: one line, a name, validated again at set time ---
  if [[ -f "$src/icons.theme" && ! -L "$src/icons.theme" ]]; then
    name=$(head -1 "$src/icons.theme" 2>/dev/null | tr -d '[:space:]')
    if [[ $name =~ ^[A-Za-z0-9_-]+$ ]]; then
      printf '%s\n' "$name" > "$dst/icons.theme"
      log_ok "imported icons.theme ($name)"
    else
      log_warn "ignored icons.theme: not a plausible icon theme name"
    fi
  fi

  # --- preview and attribution ---
  for f in preview.png LICENSE LICENSE.md LICENCE COPYING README.md; do
    [[ -e "$src/$f" ]] || continue
    _theme_copy_file "$src/$f" "$dst/$f" 4194304 && log_ok "imported $f"
  done
  # Kept even though nothing reads them: half the community repos carry no
  # licence at all, and keeping the author's terms next to their work costs
  # nothing.

  # --- backgrounds: regular files, known extensions, size-capped ---
  if [[ -d "$src/backgrounds" && ! -L "$src/backgrounds" ]]; then
    local count=0
    for f in "$src/backgrounds"/*; do
      [[ -e $f ]] || continue
      case "${f##*.}" in
        png|jpg|jpeg|webp|PNG|JPG|JPEG|WEBP) ;;
        *) log_info "ignored background $(basename "$f"): not an image we recognise"; continue ;;
      esac
      _theme_copy_file "$f" "$dst/backgrounds/$(basename "$f")" 26214400 &&
        count=$((count + 1))
    done
    (( count )) && log_ok "imported $count background image(s)"
  fi

  printf '%s\n' "$origin" > "$dst/origin"

  _theme_import_explain "$src" "$palette_source"
  return 0
}
