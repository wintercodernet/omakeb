#!/usr/bin/env python3
"""Every font a config names must be one a package we install provides.

Two failures, both silent, both of which this stack degrades into rather than
reports:

NAMED FACE MISSING. A template says `font_family JetBrains Mono` and nothing
installs it. Every renderer here — kitty, waybar's GTK stack, fuzzel, mako,
hyprlock — falls back to whatever fontconfig picks and draws something. Nothing
logs, nothing fails, the desktop just looks wrong in a way that is hard to
attribute. Adding a font to a template and forgetting packages/desktop.list is
one edit away at all times.

GENERIC ALIAS UNRESOLVED. `sans-serif` and `monospace` are fontconfig aliases,
not fonts. On a netinst with no desktop task they can resolve to nothing useful,
which is why fonts-dejavu-core is in the list — GTK asks for sans-serif by
default and nobody names a proportional face anywhere in this repo.

Coverage of scripts (CJK, Arabic, Devanagari) cannot be checked from here; it is
a property of the packages, not of our configs. It is asserted structurally
instead: the packages that provide it must stay in the list.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Which package provides which family. Hand-maintained, and short on purpose:
# omakeb names exactly one family anywhere (font family is an omakeb
# constant, never a theme token). A new entry here should make
# someone ask whether a second font is really wanted.
FAMILY_PACKAGES = {
    "jetbrains mono": "fonts-jetbrains-mono",
    "jetbrainsmono nerd font": "fonts-jetbrains-mono",
    "dejavu sans": "fonts-dejavu-core",
    "dejavu sans mono": "fonts-dejavu-core",
    "noto sans": "fonts-noto-core",
    "noto color emoji": "fonts-noto-color-emoji",
}

# fontconfig aliases, not faces. Each needs *some* package able to satisfy it.
GENERIC = {
    "monospace": ["fonts-jetbrains-mono", "fonts-dejavu-core"],
    "sans-serif": ["fonts-dejavu-core", "fonts-noto-core"],
    "sans": ["fonts-dejavu-core", "fonts-noto-core"],
    "serif": ["fonts-dejavu-core", "fonts-noto-core"],
    "emoji": ["fonts-noto-color-emoji"],
    "cursive": [],
    "fantasy": [],
    "auto": [],          # kitty's bold_font/italic_font = auto
    "inherit": [],
}

# Coverage packages that must not quietly disappear from the list. Each entry is
# (package, what stops working). These are not named by any config — fontconfig
# reaches them as fallback — so nothing else in the tree references them and
# nothing else would notice their removal.
COVERAGE = [
    ("fonts-noto-core", "Greek, Cyrillic, Arabic, Hebrew, Devanagari and Thai render as tofu"),
    ("fonts-noto-cjk", "Chinese, Japanese and Korean render as tofu"),
    ("fonts-dejavu-core", "fontconfig's sans-serif alias may resolve to nothing; GTK defaults to it"),
    ("fonts-noto-color-emoji", "emoji in the menu and notifications render as tofu"),
]

# The syntaxes in play. Every app named its font option differently and none of
# them agreed, which is the whole reason this needs a parser rather than a grep.
PATTERNS = [
    # kitty: `font_family      JetBrains Mono`  (no separator)
    (r"^\s*(?:font_family|bold_font|italic_font|bold_italic_font)\s+(?!=)(.+?)\s*$", "kitty"),
    # hyprlang: `font_family = JetBrains Mono`
    (r"^\s*font_family\s*=\s*(.+?)\s*$", "hyprlang"),
    # fuzzel: `font=JetBrains Mono:size=12`
    (r"^\s*font\s*=\s*([^:\n]+?)(?::[^=]*=.*)?\s*$", "fuzzel/mako"),
    # CSS: `font-family: "JetBrains Mono", monospace;`
    (r"^\s*font-family\s*:\s*(.+?)\s*;\s*$", "css"),
]

SCAN = sorted(
    list((ROOT / "templates").glob("*.tpl"))
    + list((ROOT / "default").rglob("*.conf"))
)


def package_list():
    names = set()
    for f in (ROOT / "packages").glob("*.list"):
        for line in f.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                names.add(line)
    return names


def families_in(line, style):
    """Split one declaration into the families it names."""
    value = line.strip().strip("'\"")
    if style == "css":
        parts = [p.strip().strip("'\"") for p in value.split(",")]
    elif style == "fuzzel/mako":
        # mako is `font=JetBrains Mono 10` — a trailing size with no separator.
        value = re.sub(r"\s+\d+(\.\d+)?$", "", value)
        parts = [p.strip() for p in value.split(",")]
    else:
        parts = [value]
    return [p for p in parts if p]


def main():
    installed = package_list()
    problems = []
    checked = 0
    seen_families = {}
    generics_used = set()

    for path in SCAN:
        rel = path.relative_to(ROOT)
        for n, raw in enumerate(path.read_text().splitlines(), 1):
            # hyprlang truncates a line at the first unescaped '#', so
            # a commented-out font line is not a declaration.
            line = raw.split("#", 1)[0]
            if not line.strip():
                continue
            for pattern, style in PATTERNS:
                m = re.match(pattern, line)
                if not m:
                    continue
                for fam in families_in(m.group(1), style):
                    key = fam.lower()
                    # A template token is resolved at render time; not our call.
                    if "{{" in fam:
                        continue
                    checked += 1
                    if key in GENERIC:
                        generics_used.add(key)
                        continue
                    seen_families.setdefault(key, []).append(f"{rel}:{n}")
                    pkg = FAMILY_PACKAGES.get(key)
                    if pkg is None:
                        problems.append(
                            f"{rel}:{n}: font '{fam}' is not in FAMILY_PACKAGES; "
                            f"add it there and to packages/*.list, or use one already installed"
                        )
                    elif pkg not in installed:
                        problems.append(
                            f"{rel}:{n}: font '{fam}' needs {pkg}, which is in no packages/*.list"
                        )
                break

    for generic in sorted(generics_used):
        options = GENERIC[generic]
        if options and not any(p in installed for p in options):
            problems.append(
                f"generic family '{generic}' is used but none of {options} is installed; "
                f"fontconfig has nothing to resolve it to"
            )

    for pkg, consequence in COVERAGE:
        if pkg not in installed:
            problems.append(f"{pkg} is not installed: {consequence}")

    if problems:
        for p in problems:
            print(f"  FAIL: {p}")
        return 1

    print(f"  ok: {checked} font declaration(s) across {len(SCAN)} files")
    for fam in sorted(seen_families):
        print(f"  ok: {FAMILY_PACKAGES[fam]} provides '{fam}' "
              f"({len(seen_families[fam])} declaration(s))")
    if generics_used:
        print(f"  ok: generic families resolve: {', '.join(sorted(generics_used))}")
    for pkg, _ in COVERAGE:
        print(f"  ok: {pkg} installed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
