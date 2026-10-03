#!/usr/bin/env python3
"""The theme pipeline: does every palette we might meet render every template?

Three things are checked, and each one exists because of a specific failure
that produces NO error message when it happens:

1. THE CASCADE. There are three generations of the
   palette format in simultaneous use, and an adapter implementing only the
   canonical keys renders roughly a third of them black on black. So every
   fixture in test/fixtures/palettes — one per generation, plus the floor
   cases — must resolve the complete vocabulary to a non-empty value, and must
   render every template with nothing left unsubstituted.

2. THE HYPRLANG '#' TRAP. hyprlang truncates every line at an unescaped '#'
   (config.cpp:688-716). A raw #7aa2f7 in a Hyprland or hyprlock config does
   not error — the line is silently cut short and the old value stays. So the
   rendered hypr files must contain no '#' outside a whole-line comment, while
   waybar.css and gtk.css, which are NOT hyprlang, must still contain them.

3. THE INVISIBLE-WIDGET CLASS. lighter_background falls back through color0 to
   background, so an undeclared theme gets a fuzzel selection bar the same
   colour as the backdrop; muted falls back to color8, which in every
   Solarized-shaped palette IS the background. Both are legible-looking bugs
   with no error. The resolver derives a distinct value instead, and this
   asserts it did.

Nothing here needs Debian, a compositor or a network. It runs on macOS.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME_PY = os.path.join(ROOT, "lib", "theme.py")
TEMPLATES = os.path.join(ROOT, "templates")
THEMES = os.path.join(ROOT, "themes")
FIXTURES = os.path.join(ROOT, "test", "fixtures", "palettes")

# No __pycache__ next to lib/theme.py: this is a checkout, not a build tree,
# and a stray directory there shows up in every `git status` from now on.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(ROOT, "lib"))
import theme as theme_mod  # noqa: E402  (lib/theme.py)

problems = []
checked = 0


def bad(msg):
    problems.append(msg)


def run(args):
    return subprocess.run([sys.executable, THEME_PY] + args,
                          capture_output=True, text=True)


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

def template_files():
    return sorted(os.path.join(TEMPLATES, f) for f in os.listdir(TEMPLATES)
                  if f.endswith(".tpl"))


def shipped_themes():
    return sorted(os.path.join(THEMES, d) for d in os.listdir(THEMES)
                  if os.path.isfile(os.path.join(THEMES, d, "colors.toml")))


def fixture_palettes():
    """Every fixture, as a (label, theme-dir) pair.

    The generation-1 fixture has no colors.toml at all — that IS its generation
    — so it goes through the alacritty back-derivation first, which is the only
    thing that exercises that path.
    """
    import tempfile
    out = []
    for name in sorted(os.listdir(FIXTURES)):
        path = os.path.join(FIXTURES, name)
        if not name.endswith(".toml"):
            continue
        if name.startswith("gen1-"):
            result = run(["from-alacritty", path])
            if result.returncode != 0:
                bad("%s: back-derivation failed: %s" % (name, result.stderr.strip()))
                continue
            tmp = tempfile.mkdtemp(prefix="omakeb-fixture-")
            with open(os.path.join(tmp, "colors.toml"), "w") as fh:
                fh.write(result.stdout)
            out.append((name, tmp))
        else:
            tmp = tempfile.mkdtemp(prefix="omakeb-fixture-")
            with open(path) as src, open(os.path.join(tmp, "colors.toml"), "w") as fh:
                fh.write(src.read())
            out.append((name, tmp))
    return out


# ---------------------------------------------------------------------------
# 1. Vocabulary
# ---------------------------------------------------------------------------

# Every token a template asks for, harvested from the templates themselves.
# Deriving the list rather than maintaining it is the point: adding a token to a
# template automatically adds it to what every fixture must resolve.
def tokens_used():
    used = set()
    for tpl in template_files():
        with open(tpl, encoding="utf-8") as fh:
            text = fh.read()
        for body in theme_mod.PLACEHOLDER.findall(text):
            parts = body.split()
            if not parts:
                bad("%s: empty placeholder {{ }}" % os.path.basename(tpl))
                continue
            if parts[0] in ("mix", "mix_strip", "mix_rgb"):
                used.update(p for p in parts[1:3] if not p.startswith("#"))
                continue
            if len(parts) != 1:
                bad("%s: {{ %s }} is not a placeholder form we support"
                    % (os.path.basename(tpl), body))
                continue
            name = parts[0]
            for suffix in ("_strip", "_rgb"):
                if name.endswith(suffix):
                    name = name[: -len(suffix)]
                    break
            used.add(name)
    return used


REQUIRED = (theme_mod.CANONICAL + theme_mod.ANSI
            + ["mode", "cursor", "selection_background", "selection_foreground",
               "purple", "bright_purple", "bg", "fg",
               "omakeb_surface", "omakeb_dim", "omakeb_muted",
               "omakeb_placeholder", "omakeb_warning", "omakeb_urgent",
               "omakeb_border_active", "omakeb_border_inactive",
               "omakeb_icon_theme", "omakeb_color_scheme", "omakeb_gtk_theme",
               "omakeb_bar_alpha"])


def check_vocabulary(label, theme_dir, needed):
    global checked
    result = run(["resolve", theme_dir])
    if result.returncode != 0:
        bad("%s: resolve failed: %s" % (label, result.stderr.strip()))
        return None
    palette = {}
    for line in result.stdout.splitlines():
        if "\t" in line:
            key, value = line.split("\t", 1)
            palette[key] = value
    missing = [k for k in sorted(set(REQUIRED) | needed)
               if not palette.get(k, "").strip()]
    if missing:
        bad("%s: the cascade left %d token(s) unresolved: %s"
            % (label, len(missing), " ".join(missing)))
    checked += 1
    return palette


# ---------------------------------------------------------------------------
# 2 and 3. Rendered output
# ---------------------------------------------------------------------------

HEX = re.compile(r"#[0-9a-fA-F]{6}")


def check_render(label, theme_dir, palette):
    import tempfile
    outdir = tempfile.mkdtemp(prefix="omakeb-render-")
    result = run(["render", theme_dir, outdir] + template_files())
    if result.returncode != 0:
        bad("%s: render failed: %s" % (label, result.stderr.strip()))
        return

    rendered = sorted(os.listdir(outdir))
    expected = sorted(os.path.basename(t)[:-4] for t in template_files())
    if rendered != expected:
        bad("%s: rendered %s, expected %s" % (label, rendered, expected))

    for name in rendered:
        path = os.path.join(outdir, name)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()

        # No template may survive rendering with a placeholder in it. The
        # substituter aborts on an unknown token, so reaching here with one
        # left would mean a placeholder form it does not even recognise.
        if "{{" in text or "}}" in text:
            leftovers = re.findall(r"\{\{[^\n]*?\}\}|\{\{|\}\}", text)
            bad("%s/%s: unsubstituted placeholder(s): %s"
                % (label, name, " ".join(sorted(set(leftovers))[:5])))

        if name.startswith("hypr"):
            # The strict reading: a hyprlang file may carry a '#' only as the
            # first non-space character of a comment line, and only one of them.
            # Anything else is either a truncated value or a comment that will
            # be cut short in a way that misleads the next reader.
            for lineno, line in enumerate(text.splitlines(), 1):
                if "#" not in line:
                    continue
                stripped = line.lstrip()
                if stripped.startswith("#") and stripped.count("#") == 1:
                    continue
                bad("%s/%s:%d: a '#' outside the start of a comment truncates "
                    "the line silently in hyprlang: %s"
                    % (label, name, lineno, line.strip()))
        elif name.endswith((".css",)):
            if not HEX.search(text):
                bad("%s/%s: GTK CSS with no #rrggbb colour in it — the hyprlang "
                    "rule has leaked into a file that is not hyprlang"
                    % (label, name))

        if name == "btop.theme":
            # Comment lines are skipped: the template explains this trap in its
            # own header, and the header naming the wrong spelling is not the
            # same thing as the file using it.
            body = [l for l in text.splitlines() if not l.lstrip().startswith("#")]
            if any("theme_color[" in l for l in body):
                bad("%s/%s: btop reads theme[...], not theme_color[...]; a file "
                    "using the latter renders colourless with no error"
                    % (label, name))
            if "theme[main_bg]" not in text:
                bad("%s/%s: no theme[main_bg]" % (label, name))

        if name == "mako.ini":
            # Without this section `makoctl mode -s do-not-disturb` sets a mode
            # that does nothing, and C3's DND toggle is a silent no-op.
            if "[mode=do-not-disturb]" not in text:
                bad("%s/%s: the [mode=do-not-disturb] section is gone; the DND "
                    "toggle would become a no-op" % (label, name))

        if name == "fuzzel.ini":
            colours = dict(re.findall(r"^([a-z-]+)=([0-9a-fA-F]{8})$",
                                      text, re.M))
            if colours.get("background", "")[:6] == colours.get("selection", "")[:6]:
                bad("%s/%s: the selection bar is the same colour as the "
                    "background — an invisible highlight with no error"
                    % (label, name))

    # The two guarded derivations, asserted on the palette rather than on a
    # rendered file so the failure names the cause.
    if palette:
        if palette["omakeb_surface"] == palette["background"]:
            bad("%s: omakeb_surface == background; the fuzzel selection bar "
                "and mako's progress fill would be invisible" % label)
        if palette["omakeb_muted"] == palette["background"]:
            bad("%s: omakeb_muted == background; inactive workspace numbers "
                "would be painted on their own colour" % label)


# ---------------------------------------------------------------------------
# 4. The two-sources-of-truth guard
# ---------------------------------------------------------------------------

def check_no_stray_colours():
    """install/60-config.sh must not carry colours any more.

    It used to write waybar's stylesheet, mako's config, fuzzel.ini, kitty.conf
    and hyprlock.conf with the palette baked in. Those files are rendered from
    templates now; a colour reappearing here means the same value lives in two
    places, and the copy the theme does not know about is the one that wins.
    """
    path = os.path.join(ROOT, "install", "60-config.sh")
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            if line.lstrip().startswith("#"):
                continue
            for match in HEX.finditer(line):
                bad("install/60-config.sh:%d: a colour (%s) is back in a file "
                    "the theme system owns" % (lineno, match.group(0)))


# ---------------------------------------------------------------------------

def main():
    needed = tokens_used()
    if not needed:
        bad("no placeholders found in templates/ — did the templates move?")

    subjects = [(os.path.basename(d), d) for d in shipped_themes()]
    if len(subjects) < 2:
        bad("fewer than two shipped themes; the pipeline is not proven by one")
    subjects += fixture_palettes()

    for label, theme_dir in subjects:
        palette = check_vocabulary(label, theme_dir, needed)
        check_render(label, theme_dir, palette)

    check_no_stray_colours()

    if problems:
        print("theme pipeline: %d problem(s)" % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1
    print("%d palette(s) x %d template(s): every token resolves, nothing "
          "unsubstituted, no '#' in hyprlang output"
          % (checked, len(template_files())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
