#!/usr/bin/env python3
"""Palette resolution and template rendering for omakeb themes.

Called by lib/theme.sh; never sourced directly. Nothing here touches the
filesystem outside the paths it is handed.

WHY PYTHON: envsubst mangles the braces in
CSS, and building a sed script from the palette (upstream's approach) is a code
shape we deliberately do not mirror. The cascade and the substituter also want
the same colour arithmetic, so splitting them across a bash/python boundary
would mean implementing mix() twice. lib/theme.sh keeps the shell-side API.

THE CASCADE IS THE LOAD-BEARING PART. It exists because the ecosystem this
format came from ships three incompatible generations at once:

  gen 1  no colors.toml at all — an alacritty.toml the palette is back-derived
         from (`from-alacritty` below)
  gen 2  transitional: colors.toml alongside the whole legacy per-app file set,
         with key sets mixing canonical, legacy-short (bg, dark_fg) and ANSI
  gen 3  colors.toml only — but in TWO shapes, an ANSI one (accent, cursor,
         foreground, background, selection_*, color0..15) and a canonical
         semantic one (background, lighter_background, muted, bright_red, ...)

An adapter that implements only the canonical keys renders every ANSI-shaped
theme black-on-black, because `background` is simply not declared in one.

Usage:
  theme.py resolve <theme-dir|colors.toml>
      -> KEY<TAB>VALUE on stdout, one per line, complete vocabulary
  theme.py render  <theme-dir|colors.toml> <outdir> <template.tpl>...
      -> writes outdir/<template without .tpl>
  theme.py from-alacritty <alacritty.toml>
      -> a colors.toml on stdout
"""

import os
import re
import sys

# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------

CANONICAL = [
    "accent", "selection", "muted",
    "background", "dark_background", "darker_background", "lighter_background",
    "foreground", "dark_foreground", "light_foreground", "bright_foreground",
    "red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown",
    "bright_red", "bright_yellow", "bright_green",
    "bright_cyan", "bright_blue", "bright_magenta",
]

ANSI = ["color%d" % i for i in range(16)]

# Legacy short aliases, resolved in BOTH directions; canonical wins when both
# are declared. `bg`/`dark_fg` are gen-2 spellings still in the wild.
SHORT = {
    "background": "bg",
    "dark_background": "dark_bg",
    "darker_background": "darker_bg",
    "lighter_background": "lighter_bg",
    "foreground": "fg",
    "dark_foreground": "dark_fg",
    "light_foreground": "light_fg",
    "bright_foreground": "bright_fg",
}

# Plain synonyms, also bidirectional.
EQUIV = {
    "magenta": "purple",
    "bright_magenta": "bright_purple",
    "mode": "theme_type",
}

# color0..15 <- semantic. The order of the bright ramp (9=red 10=green
# 11=yellow 12=blue 13=magenta 14=cyan) follows color1..6, not the ANSI names.
ANSI_FROM_SEMANTIC = {
    "color0": "background", "color1": "red", "color2": "green",
    "color3": "yellow", "color4": "blue", "color5": "magenta",
    "color6": "cyan", "color7": "foreground", "color8": "muted",
    "color9": "bright_red", "color10": "bright_green",
    "color11": "bright_yellow", "color12": "bright_blue",
    "color13": "bright_magenta", "color14": "bright_cyan",
    "color15": "bright_foreground",
}
SEMANTIC_FROM_ANSI = dict((v, k) for k, v in ANSI_FROM_SEMANTIC.items())

# Keys carrying something other than a single colour.
NON_COLOUR = set([
    "mode", "theme_type", "omakeb_icon_theme", "omakeb_color_scheme",
    "omakeb_gtk_theme", "omakeb_bar_alpha",
    "hyprland_active_border", "hyprland_inactive_border",
    "omakeb_border_active", "omakeb_border_inactive",
])

# Values are substituted straight into waybar's CSS and Hyprland's config, so an
# unfiltered one is an injection. Announce a rejection rather than dropping it
# silently — the user otherwise gets a literal {{ accent }} in their bar with no
# explanation.
KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")
VALUE_RE = re.compile(r"^[A-Za-z0-9#(),._+/% -]*$")

# The built-in palette every unresolvable key falls back to, per key. An
# imported gen-1 theme that resolves 12 of 30 keys must still give a usable
# desktop rather than a refusal.
DEFAULT = {
    "mode": "dark",
    "accent": "#7aa2f7",
    "selection": "#2a2a37",
    "muted": "#6f6f86",
    "background": "#0b0b0f",
    "dark_background": "#08080b",
    "darker_background": "#050508",
    "lighter_background": "#1c1c26",
    "foreground": "#e6e6ec",
    "dark_foreground": "#6f6f86",
    "light_foreground": "#c0c0d0",
    "bright_foreground": "#ffffff",
    "red": "#f7768e", "yellow": "#e0af68", "orange": "#ff9e64",
    "green": "#9ece6a", "cyan": "#7dcfff", "blue": "#7aa2f7",
    "magenta": "#bb9af7", "brown": "#7f4f32",
    "bright_red": "#ff9eae", "bright_yellow": "#f0c98a",
    "bright_green": "#bddc8a", "bright_cyan": "#a5e2ff",
    "bright_blue": "#a3bdff", "bright_magenta": "#d3bcff",
}

# Not from the theme. Upstream keeps the equivalent in shell.toml, which is
# QML-shaped and useless to us; a theme designed around an opaque bar will look
# slightly wrong and there is no way to ask it.
BAR_ALPHA = "0.85"

warnings = []


def warn(msg):
    warnings.append(msg)
    sys.stderr.write("theme: %s\n" % msg)


def fail(msg):
    sys.stderr.write("theme: error: %s\n" % msg)
    raise SystemExit(1)


# ---------------------------------------------------------------------------
# Colour arithmetic
# ---------------------------------------------------------------------------

def parse_color(value):
    """-> (r, g, b) or None. Liberal about the forms found in the wild."""
    if value is None:
        return None
    s = value.strip()
    m = re.match(r"^rgba?\(\s*([0-9A-Fa-f]{6,8})\s*\)$", s)
    if m:
        s = m.group(1)[:6]
    else:
        m = re.match(r"^rgba?\(([^)]*)\)$", s)
        if m:
            parts = [p.strip() for p in m.group(1).split(",")]
            if len(parts) >= 3:
                try:
                    return tuple(int(round(float(p))) & 0xFF for p in parts[:3])
                except ValueError:
                    return None
            return None
    s = s.lstrip("#")
    if len(s) == 3 and re.match(r"^[0-9A-Fa-f]{3}$", s):
        s = "".join(c * 2 for c in s)
    if len(s) == 8 and re.match(r"^[0-9A-Fa-f]{8}$", s):
        s = s[:6]          # an alpha in the palette is dropped; we set our own
    if len(s) == 6 and re.match(r"^[0-9A-Fa-f]{6}$", s):
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    return None


def to_hex(rgb):
    return "#%02x%02x%02x" % rgb


def mix(a, b, ratio):
    """Straight linear interpolation in sRGB, no gamma correction.

    ratio is the fraction of `b`. mix(bg, #000000, 25%) is 25% of the way to
    black. This is what upstream does and matching it is the only way a theme
    that declares neither dark_background nor darker_background renders the same
    on both.
    """
    ra, rb = parse_color(a), parse_color(b)
    if ra is None or rb is None:
        return None
    return to_hex(tuple(
        int(round(ra[i] + (rb[i] - ra[i]) * ratio)) for i in range(3)
    ))


def luminance_is_light(value):
    rgb = parse_color(value)
    if rgb is None:
        return False
    return sum(rgb) > 382


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_toml_flat(path):
    """Flat key/value read of a colors.toml.

    Section-AWARE even though today's format is flat: "colors.toml
    gains sections" is a plausible upstream change, and a section-blind parser
    would then silently last-wins two different `background =` keys. We keep one
    flat namespace but reject a duplicate rather than letting the later one win.
    """
    values = {}
    section = ""
    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except IOError as exc:
        fail("cannot read %s: %s" % (path, exc))
    with fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("["):
                section = line.strip("[]").strip()
                continue
            if "=" not in line:
                continue
            key, _, rest = line.partition("=")
            key = key.strip().strip('"').strip("'")
            value = rest.strip()
            # Quoted value: take the string, ignore any trailing comment.
            if value[:1] in ('"', "'"):
                quote = value[0]
                end = value.find(quote, 1)
                value = value[1:end] if end > 0 else value[1:]
            else:
                # Unquoted. Strip a trailing comment, but only one introduced by
                # whitespace — a bare `#1a1b26` is a value, not a comment.
                value = re.split(r"\s#", value, 1)[0].strip()
            if not KEY_RE.match(key):
                warn("ignored key with unexpected characters: %r" % key)
                continue
            if not VALUE_RE.match(value):
                warn("ignored %s: value %r contains characters we will not "
                     "substitute into a config file" % (key, value))
                continue
            if key in values and values[key] != value:
                warn("duplicate key %s at line %d (section %r); keeping the "
                     "first value %r" % (key, lineno, section, values[key]))
                continue
            values.setdefault(key, value)
    return values


# ---------------------------------------------------------------------------
# The cascade
# ---------------------------------------------------------------------------

def resolve(theme_dir, colors_path):
    """-> dict of the complete token vocabulary. Never returns a missing key."""
    p = parse_toml_flat(colors_path)

    # Normalise every colour-shaped value to #rrggbb up front, so downstream
    # comparisons (`lighter_background == background`) are string comparisons
    # and cannot be fooled by "#1A1B26" versus "1a1b26".
    for key in list(p.keys()):
        if key in NON_COLOUR:
            continue
        rgb = parse_color(p[key])
        if rgb is not None:
            p[key] = to_hex(rgb)

    # -- 1. aliases, both directions, canonical wins ------------------------
    for canonical, legacy in list(SHORT.items()) + list(EQUIV.items()):
        if canonical not in p and legacy in p:
            p[canonical] = p[legacy]

    # -- 2. mode ------------------------------------------------------------
    # mode -> theme_type -> a legacy light.mode marker file -> luminance -> dark
    if "mode" not in p:
        if theme_dir and os.path.exists(os.path.join(theme_dir, "light.mode")):
            p["mode"] = "light"
        elif "background" in p or "color0" in p:
            base = p.get("background") or p.get("color0")
            p["mode"] = "light" if luminance_is_light(base) else "dark"
        else:
            p["mode"] = "dark"
    if p["mode"] not in ("dark", "light"):
        warn("mode %r is not dark or light; treating as dark" % p["mode"])
        p["mode"] = "dark"

    # -- 3. ANSI -> semantic, then derived shades ---------------------------
    # Order is load-bearing: aliases, then ANSI fallbacks, then mixes. Running
    # the mixes first would give bright_red = mix(red, white, 20%) on a theme
    # that declares color9, which is a different colour.
    def first(dst, *sources):
        if dst in p:
            return
        for src in sources:
            if src in p:
                p[dst] = p[src]
                return

    first("background", "color0")
    first("foreground", "color7")
    first("red", "color1")
    first("green", "color2")
    first("yellow", "color3")
    first("blue", "color4")
    first("magenta", "color5")
    first("cyan", "color6")
    # `accent` has no fallback in the cascade because upstream's canonical themes all
    # declare it. An ANSI-shaped theme that does not would leave every border
    # and highlight unresolved, so blue is our extension to the cascade.
    first("accent", "blue", "color4")
    first("light_foreground", "color7", "foreground")
    first("bright_foreground", "color15", "foreground")
    first("lighter_background", "color0", "background")
    first("dark_foreground", "color8", "foreground")
    first("muted", "color8", "dark_foreground")
    first("selection", "selection_background", "color8", "color0", "background")
    first("orange", "yellow")
    first("bright_red", "color9")
    first("bright_green", "color10")
    first("bright_yellow", "color11")
    first("bright_blue", "color12")
    first("bright_magenta", "color13")
    first("bright_cyan", "color14")

    def derive(dst, fn):
        if dst in p:
            return
        value = fn()
        if value:
            p[dst] = value

    for c in ("red", "yellow", "green", "cyan", "blue", "magenta"):
        derive("bright_" + c,
               lambda c=c: mix(p[c], "#ffffff", 0.20) if c in p else None)
    derive("brown", lambda: mix(p["orange"], "#000000", 0.50)
           if "orange" in p else None)
    derive("dark_background", lambda: mix(p["background"], "#000000", 0.25)
           if "background" in p else None)
    derive("darker_background", lambda: mix(p["background"], "#000000", 0.50)
           if "background" in p else None)

    # -- 4. per-key fill from the built-in palette --------------------------
    # Warn once, naming the keys: a theme rendering with three borrowed colours
    # is a usable desktop, and silence here is what turns "this import looks
    # slightly off" into an unanswerable bug report.
    filled = []
    for key in CANONICAL + ["mode"]:
        if key not in p or p[key] == "":
            p[key] = DEFAULT[key]
            filled.append(key)
    if filled:
        warn("filled %d key(s) from the built-in palette: %s"
             % (len(filled), " ".join(sorted(filled))))

    # -- 5. produced keys ---------------------------------------------------
    for ansi, semantic in ANSI_FROM_SEMANTIC.items():
        p.setdefault(ansi, p[semantic])
    for canonical, legacy in list(SHORT.items()) + list(EQUIV.items()):
        p.setdefault(legacy, p[canonical])
    p.setdefault("cursor", p["bright_foreground"])
    p.setdefault("selection_background", p["selection"])
    p.setdefault("selection_foreground", p["bright_foreground"])

    # -- 6. omakeb-only derivations ----------------------------------------
    # Our stack asks for roles colors.toml does not express. Each needs a
    # defined derivation because a theme will never supply it.

    # THE single most likely visual bug: lighter_background falls back to
    # color0, which falls back to background, so an undeclared theme gets
    # lighter_background == background and the fuzzel selection bar becomes
    # invisible. Never emit the two as equal — derive a surface instead.
    if p["lighter_background"] != p["background"]:
        p["omakeb_surface"] = p["lighter_background"]
    else:
        p["omakeb_surface"] = mix(p["background"], p["foreground"], 0.08)

    # Same shape: light_foreground is frequently identical to foreground.
    if p["light_foreground"] != p["foreground"]:
        p["omakeb_dim"] = p["light_foreground"]
    else:
        p["omakeb_dim"] = mix(p["foreground"], p["background"], 0.20)

    # Beyond those, and for the same class of reason: `muted` falls back to
    # color8, which in every Solarized-shaped palette IS the background — so a
    # gen-1 theme gives inactive workspace numbers painted background-on-
    # background. Same guard, same fallback shape.
    if p["muted"] != p["background"]:
        p["omakeb_muted"] = p["muted"]
    else:
        p["omakeb_muted"] = mix(p["foreground"], p["background"], 0.45)

    p["omakeb_placeholder"] = mix(p["foreground"], p["background"], 0.34)
    p["omakeb_warning"] = p["orange"] if p["orange"] != p["yellow"] else p["yellow"]
    # There is no `urgent` key in the format, and one written into a colors.toml
    # is ignored — same as upstream.
    p["omakeb_urgent"] = p["red"]
    if "urgent" in p:
        warn("colors.toml declares `urgent`, which is not part of the palette "
             "format; ignoring it (red is used for urgency)")

    # hyprlang gradient strings pass through verbatim; their syntax is ours.
    p["omakeb_border_active"] = p.get(
        "hyprland_active_border", "rgb(%s)" % p["accent"].lstrip("#"))
    p["omakeb_border_inactive"] = p.get(
        "hyprland_inactive_border", "rgba(595959aa)")

    p["omakeb_bar_alpha"] = BAR_ALPHA
    p["omakeb_color_scheme"] = "prefer-light" if p["mode"] == "light" else "prefer-dark"
    p["omakeb_gtk_theme"] = "Adwaita" if p["mode"] == "light" else "Adwaita-dark"
    p["omakeb_icon_theme"] = resolve_icon_theme(theme_dir, p["mode"])

    return p


def resolve_icon_theme(theme_dir, mode):
    """icons.theme if that theme is actually installed, else Papirus.

    Every value seen in the wild is a Yaru-* name; packages/desktop.list ships
    papirus-icon-theme. Naming an absent icon theme in gtk or fuzzel gives
    missing icons with no error, so validate before adopting.
    """
    fallback = "Papirus-Light" if mode == "light" else "Papirus-Dark"
    if not theme_dir:
        return fallback
    path = os.path.join(theme_dir, "icons.theme")
    if not os.path.isfile(path):
        return fallback
    try:
        name = open(path, encoding="utf-8").read().strip().splitlines()[0].strip()
    except (IOError, IndexError):
        return fallback
    if not re.match(r"^[A-Za-z0-9_-]+$", name):
        warn("ignored icons.theme: %r is not a plausible icon theme name" % name)
        return fallback
    for root in ("/usr/share/icons", os.path.expanduser("~/.local/share/icons"),
                 os.path.expanduser("~/.icons")):
        if os.path.isfile(os.path.join(root, name, "index.theme")):
            return name
    warn("icons.theme names %s, which is not installed; using %s"
         % (name, fallback))
    return fallback


# ---------------------------------------------------------------------------
# Back-derivation from alacritty.toml (generation 1)
# ---------------------------------------------------------------------------

ALACRITTY_NORMAL = ["black", "red", "green", "yellow",
                    "blue", "magenta", "cyan", "white"]


def from_alacritty(path):
    """Emit a colors.toml for the ~29% of the ecosystem that predates one.

    Fidelity is approximate by construction — an Alacritty config carries 18
    colours and no semantic roles at all, so accent, muted, selection and the
    background ramp are left for the cascade to derive. Upstream's own
    back-derivation is approximate for the same reason.
    """
    section = ""
    got = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("["):
                section = line.strip("[]").strip()
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip().strip('"').strip("'")
            value = value.strip().strip(",").strip()
            if value[:1] in ('"', "'"):
                quote = value[0]
                end = value.find(quote, 1)
                value = value[1:end] if end > 0 else value[1:]
            rgb = parse_color(value)
            if rgb is None:
                continue
            # Both the sectioned and the flattened dotted-key spelling.
            full = ("%s.%s" % (section, key)) if section else key
            full = re.sub(r"^colors\.", "", full)
            got[full] = to_hex(rgb)

    out = {}
    if "primary.background" in got:
        out["background"] = got["primary.background"]
    if "primary.foreground" in got:
        out["foreground"] = got["primary.foreground"]
    if "cursor.cursor" in got:
        out["cursor"] = got["cursor.cursor"]
    if "selection.background" in got:
        out["selection"] = got["selection.background"]
    for i, name in enumerate(ALACRITTY_NORMAL):
        if "normal." + name in got:
            out["color%d" % i] = got["normal." + name]
        if "bright." + name in got:
            out["color%d" % (i + 8)] = got["bright." + name]

    if "background" not in out and "color0" not in out:
        fail("%s has no usable palette (no [colors.primary] and no "
             "[colors.normal])" % path)

    lines = ["# Derived by omakeb from %s." % os.path.basename(path),
             "# The theme predates colors.toml; semantic roles are filled in by",
             "# the cascade in lib/theme.py, so this is approximate.", ""]
    for key in ("background", "foreground", "cursor", "selection"):
        if key in out:
            lines.append('%s = "%s"' % (key, out[key]))
    lines.append("")
    for i in range(16):
        key = "color%d" % i
        if key in out:
            lines.append('%s = "%s"' % (key, out[key]))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Substitution
# ---------------------------------------------------------------------------

PLACEHOLDER = re.compile(r"\{\{\s*([^{}]*?)\s*\}\}")


def substitute(text, palette, origin):
    """Expand {{ key }}, {{ key_strip }}, {{ key_rgb }} and {{ mix a b N% }}.

    An unresolvable placeholder aborts. A template must never see one, and a
    half-substituted config file is worse than the theme we already had.
    """
    problems = []

    def value_of(name):
        if name in palette:
            return palette[name]
        return None

    def as_color(name_or_literal):
        value = value_of(name_or_literal)
        if value is None:
            value = name_or_literal
        rgb = parse_color(value)
        return rgb

    def expand(match):
        body = match.group(1)
        parts = body.split()

        if parts and parts[0] in ("mix", "mix_strip", "mix_rgb"):
            if len(parts) != 4:
                problems.append("%s: {{ %s }} needs `mix <a> <b> <n>%%`"
                                % (origin, body))
                return match.group(0)
            a, b, ratio = as_color(parts[1]), as_color(parts[2]), parts[3]
            try:
                fraction = float(ratio.rstrip("%")) / 100.0
            except ValueError:
                problems.append("%s: {{ %s }} has a bad ratio" % (origin, body))
                return match.group(0)
            if a is None or b is None:
                problems.append("%s: {{ %s }} names something that is not a "
                                "colour" % (origin, body))
                return match.group(0)
            mixed = mix(to_hex(a), to_hex(b), fraction)
            return _format(mixed, parts[0][3:].lstrip("_"), body, origin, problems)

        if len(parts) != 1:
            problems.append("%s: {{ %s }} is not a placeholder we understand"
                            % (origin, body))
            return match.group(0)

        name = parts[0]
        for suffix in ("_strip", "_rgb"):
            if name.endswith(suffix) and value_of(name) is None:
                base = value_of(name[: -len(suffix)])
                if base is None:
                    break
                return _format(base, suffix.lstrip("_"), body, origin, problems)
        value = value_of(name)
        if value is None:
            problems.append("%s: {{ %s }} is not a token this palette defines"
                            % (origin, body))
            return match.group(0)
        return value

    out = PLACEHOLDER.sub(expand, text)
    if problems:
        for problem in problems:
            sys.stderr.write("theme: error: %s\n" % problem)
        raise SystemExit(1)
    return out


def _format(value, form, body, origin, problems):
    if form == "":
        return value
    rgb = parse_color(value)
    if rgb is None:
        problems.append("%s: {{ %s }} asks for a %s form of a value that is "
                        "not a colour (%r)" % (origin, body, form, value))
        return value
    if form == "strip":
        return to_hex(rgb).lstrip("#")
    if form == "rgb":
        return "%d,%d,%d" % rgb
    problems.append("%s: {{ %s }}: unknown form %r" % (origin, body, form))
    return value


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def locate(arg):
    if os.path.isdir(arg):
        return arg, os.path.join(arg, "colors.toml")
    return os.path.dirname(os.path.abspath(arg)), arg


def main(argv):
    if len(argv) < 2:
        fail("usage: theme.py resolve|render|from-alacritty ...")
    command = argv[1]

    if command == "from-alacritty":
        if len(argv) != 3:
            fail("usage: theme.py from-alacritty <alacritty.toml>")
        sys.stdout.write(from_alacritty(argv[2]))
        return 0

    if command == "resolve":
        if len(argv) != 3:
            fail("usage: theme.py resolve <theme-dir|colors.toml>")
        theme_dir, colors = locate(argv[2])
        palette = resolve(theme_dir, colors)
        for key in sorted(palette):
            sys.stdout.write("%s\t%s\n" % (key, palette[key]))
        return 0

    if command == "render":
        if len(argv) < 5:
            fail("usage: theme.py render <theme-dir|colors.toml> <outdir> "
                 "<template.tpl>...")
        theme_dir, colors = locate(argv[2])
        outdir = argv[3]
        palette = resolve(theme_dir, colors)
        written = []
        for tpl in argv[4:]:
            name = os.path.basename(tpl)
            if name.endswith(".tpl"):
                name = name[:-4]
            # A user template in $OMAKEB_CONFIG/templates comes first on the
            # command line and wins; a built-in of the same output name is then
            # skipped, which is upstream's rule and the one users expect.
            if name in [os.path.basename(w) for w in written]:
                continue
            with open(tpl, "r", encoding="utf-8") as fh:
                text = fh.read()
            rendered = substitute(text, palette, tpl)
            dest = os.path.join(outdir, name)
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            with open(dest, "w", encoding="utf-8") as fh:
                fh.write(rendered)
            written.append(dest)
        for path in written:
            sys.stdout.write("%s\n" % path)
        return 0

    fail("unknown command: %s" % command)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
