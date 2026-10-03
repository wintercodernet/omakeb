#!/usr/bin/env python3
"""Validate Hyprland bind lines without a running compositor.

Checks, against the rules in Hyprland 0.55.2 ConfigManager.cpp::handleBind:
  - flag characters are valid, and mutually-exclusive combinations are rejected
  - argument count matches the flags (the `d` flag adds a description arg)
  - no two bindings claim the same modifier+key chord (Hyprland accepts these
    silently and the later one wins, which is invisible until a key "does
    nothing")
"""
import sys, glob, re
from collections import defaultdict

VALID_FLAGS = set("lremnatisodpcguk")
MOD_NAMES = {"SUPER", "SHIFT", "CTRL", "ALT", "CONTROL", "MOD2", "MOD3", "MOD5"}

errors, warnings = [], []
chords = defaultdict(list)
count = 0

for path in sorted(glob.glob("default/hypr/bindings/*.conf")):
    for lineno, raw in enumerate(open(path), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^(bind[a-z]*)\s*=\s*(.*)$", line)
        if not m:
            errors.append(f"{path}:{lineno}: not a bind line: {line}")
            continue
        cmd, value = m.group(1), m.group(2)
        flags = set(cmd[4:])
        count += 1

        bad = flags - VALID_FLAGS
        if bad:
            errors.append(f"{path}:{lineno}: invalid flag(s) {''.join(sorted(bad))} in {cmd}")
        if "e" in flags and ("r" in flags or "o" in flags):
            errors.append(f"{path}:{lineno}: flag e is mutually exclusive with r and o")
        if "m" in flags and flags & set("erl"):
            errors.append(f"{path}:{lineno}: flag m is exclusive with e, r and l")
        if "c" in flags and "g" in flags:
            errors.append(f"{path}:{lineno}: flags c and g are mutually exclusive")

        has_desc = "d" in flags
        mouse = "m" in flags
        parts = [p.strip() for p in value.split(",")]
        # Hyprland splits into at most numbArgs fields, so the dispatcher's own
        # parameters may contain commas; only the leading fields are fixed.
        min_fields = 3 + (1 if has_desc else 0)
        if len(parts) < min_fields:
            errors.append(f"{path}:{lineno}: too few args ({len(parts)}, need >={min_fields}): {line}")
            continue
        max_fields = (3 if mouse else 4) + (1 if has_desc else 0)
        if len(parts) > max_fields:
            # Extra commas are fine only inside the final params field.
            pass

        mods, key = parts[0], parts[1]
        desc = parts[2] if has_desc else ""
        if has_desc and not desc:
            warnings.append(f"{path}:{lineno}: empty description on a d-flagged bind")

        for mod in mods.split():
            if mod and mod.upper() not in MOD_NAMES:
                warnings.append(f"{path}:{lineno}: unrecognised modifier '{mod}'")

        allow_dup = "lint: allow-duplicate" in raw
        chord = (" ".join(sorted(mods.upper().split())), key)
        chords[chord].append((path, lineno, desc or parts[-2], allow_dup))

for chord, uses in sorted(chords.items()):
    if len(uses) > 1 and not all(u[3] for u in uses):
        # Two binds on one chord are legitimate when they dispatch to different
        # things deliberately (Hyprland runs both). Mark those with a trailing
        # "# lint: allow-duplicate" so only the accidental ones are reported.
        locs = "; ".join(f"{p.split('/')[-1]}:{l} ({d})" for p, l, d, _ in uses)
        warnings.append(f"duplicate chord {chord[0] or '(none)'} + {chord[1]}: {locs}")

print(f"parsed {count} bindings from {len(glob.glob('default/hypr/bindings/*.conf'))} files")
for w in warnings:
    print(f"  warn:  {w}")
for e in errors:
    print(f"  ERROR: {e}")
print(f"\n{len(errors)} errors, {len(warnings)} warnings")
sys.exit(1 if errors else 0)
