#!/usr/bin/env python3
"""Every menu row has an icon, distinct within its level, that actually exists.

Three failures, all of which look fine in a diff:

MISSING. A row with an empty icon field is not merely plain. fuzzel renders the
menu as text, so that row starts one glyph to the left of every other one and
the whole level stops lining up. Forty-three rows were like this before anyone
mentioned it; the four at the top level are just the ones seen first.

AMBIGUOUS. Two rows at the SAME level sharing a glyph makes the icon stop
distinguishing anything exactly where it is being read. Across levels sharing is
fine and often right — "Reload Hyprland" should look the same wherever it is.

TOFU. An icon that is not in the installed font renders as an empty box. Nothing
reports it, and it is entirely invisible to anyone reading the JSON, where it is
just a character. This is the check that needs the font, so it runs only where
the font is present — which is why tier 0 is worth running on Debian and not
only on the development host.

The glyph names come out of the font's own `post` table, so a name here is
ground truth rather than someone's memory of a Nerd Font cheat sheet. That
distinction is not academic: picking these icons by remembered codepoint put
`md-power_sleep` on the System menu, `md-chevron_left_circle` on the hardware
mixer and `md-music_note_bluetooth_off` on two window rows, all of which
verified as "present in the font" and were completely wrong.
"""

import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONTS = [
    Path.home() / ".local/share/fonts/SymbolsNerdFontMono-Regular.ttf",
    Path.home() / ".local/share/fonts/SymbolsNerdFont-Regular.ttf",
]


def menu_rows():
    """Rows as (key, icon, label), via the menu's own JSONC stripper."""
    src = (ROOT / "bin/omakeb-menu").read_text()
    m = re.search(r"STRIP_PY='\n(.*?)\n'\n", src, re.S)
    if not m:
        sys.exit("could not extract the JSONC stripper from bin/omakeb-menu")
    strip = ROOT / "test/.strip-menu.py"
    strip.write_text(m.group(1))
    try:
        r = subprocess.run([sys.executable, str(strip), str(ROOT / "menu/menu.jsonc")],
                           capture_output=True, text=True)
    finally:
        strip.unlink(missing_ok=True)
    if r.returncode != 0:
        sys.exit("menu/menu.jsonc does not parse: " + r.stderr.strip())
    data = json.loads(r.stdout)
    return [(k, v.get("icon", ""), v.get("label", ""))
            for k, v in data.items() if isinstance(v, dict)]


def font_glyph_names(path):
    """codepoint -> glyph name, from the font's cmap (format 12) and post 2.0."""
    d = path.read_bytes()
    tabs = {}
    for i in range(struct.unpack(">H", d[4:6])[0]):
        o = 12 + i * 16
        tabs[d[o:o + 4].decode("latin1")] = struct.unpack(">II", d[o + 8:o + 16])
    if "cmap" not in tabs or "post" not in tabs:
        return None

    co, _ = tabs["cmap"]
    sub = None
    for i in range(struct.unpack(">H", d[co + 2:co + 4])[0]):
        _, _, off = struct.unpack(">HHI", d[co + 4 + i * 8:co + 12 + i * 8])
        if struct.unpack(">H", d[co + off:co + off + 2])[0] == 12:
            sub = co + off
            break
    if sub is None:
        return None

    cmap = {}
    for g in range(struct.unpack(">I", d[sub + 12:sub + 16])[0]):
        s, e, sg = struct.unpack(">III", d[sub + 16 + g * 12:sub + 28 + g * 12])
        for c in range(s, e + 1):
            cmap[c] = sg + (c - s)

    po, pl = tabs["post"]
    if struct.unpack(">I", d[po:po + 4])[0] != 0x20000:
        return {c: "" for c in cmap}
    ng = struct.unpack(">H", d[po + 32:po + 34])[0]
    idx = struct.unpack(">%dH" % ng, d[po + 34:po + 34 + ng * 2])
    p, extra = po + 34 + ng * 2, []
    while p < po + pl:
        ln = d[p]
        extra.append(d[p + 1:p + 1 + ln].decode("latin1"))
        p += 1 + ln
    names = {gid: extra[ix - 258] for gid, ix in enumerate(idx) if ix >= 258}
    return {c: names.get(g, "") for c, g in cmap.items()}


def main():
    rows = menu_rows()
    problems = []

    for key, icon, label in rows:
        if not icon:
            problems.append(f"no icon: {key} ({label})")

    seen = {}
    for key, icon, label in rows:
        if not icon:
            continue
        parent = key.rsplit(".", 1)[0] if "." in key else "<top level>"
        seen.setdefault((parent, icon), []).append(key)
    for (parent, _), keys in sorted(seen.items()):
        if len(keys) > 1:
            problems.append(f"same glyph twice under {parent}: {', '.join(keys)}")

    font = next((f for f in FONTS if f.is_file()), None)
    if font is None:
        print(f"  ok: {len(rows)} rows checked for missing and duplicate icons")
        print("  SKIP: no Nerd Font installed here, so glyph coverage is unchecked.")
        print("        Run this on a machine with the font to catch tofu.")
    else:
        glyphs = font_glyph_names(font)
        if glyphs is None:
            print(f"  SKIP: could not read glyph tables from {font.name}")
        else:
            for key, icon, label in rows:
                for ch in icon:
                    if ord(ch) not in glyphs:
                        problems.append(
                            f"U+{ord(ch):05X} on {key} ({label}) is not in {font.name} "
                            f"— it renders as an empty box")
            named = sum(1 for _, i, _ in rows if i and glyphs.get(ord(i[0])))
            print(f"  ok: {len(rows)} rows, every icon present in {font.name} "
                  f"({named} with names)")

    if problems:
        for p in problems:
            print(f"  FAIL: {p}")
        return 1
    print("  ok: every row has an icon, distinct within its level")
    return 0


if __name__ == "__main__":
    sys.exit(main())
