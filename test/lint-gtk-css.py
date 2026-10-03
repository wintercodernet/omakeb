#!/usr/bin/env python3
"""GTK CSS is not web CSS.

GTK's parser has no `::`-prefixed pseudo-elements. A selector like `::selection`
— which is valid and idiomatic in a browser — makes GTK log
"Invalid name of pseudo-class" and drop the rule. Nothing crashes loudly; the
styling just silently does not apply, and the error appears in the journal of
every GTK application that re-reads the stylesheet on a theme change.

We cannot run GTK's parser on every platform, so reject the construct statically.
"""
import glob
import re
import sys

problems = []
for path in sorted(glob.glob("templates/gtk*.tpl")):
    for lineno, raw in enumerate(open(path), 1):
        line = raw.split("/*")[0]
        for match in re.finditer(r"::[a-zA-Z-]+", line):
            problems.append((path, lineno, match.group(0), raw.strip()))

if problems:
    print(f"{len(problems)} web-CSS pseudo-element(s) in GTK stylesheet templates:")
    for path, lineno, sel, raw in problems:
        print(f"  {path}:{lineno}: {sel}   in: {raw}")
    print("\nGTK has no ::pseudo-elements. Use the node name (e.g. `selection`).")
    sys.exit(1)

print(f"gtk templates use no web-only ::pseudo-elements")
