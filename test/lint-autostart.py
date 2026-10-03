#!/usr/bin/env python3
"""The session-start contract: one daemon list, and nothing starting a daemon twice.

Three things are held down here, and only the first was checked before
default/session-daemons.tsv existed:

  * Every long-running daemon in autostart.conf must start via omakeb-daemon.
    Without it, a compositor restart or a double exec-once leaves two bars
    stacked on each other and two cliphist watchers duplicating every clipboard
    entry. The guard is easy to forget when adding a daemon, and the symptom only
    appears after a restart.

  * The five unit-backed daemons must not appear in autostart.conf at all, AND
    omakeb-session-daemons must be there to start them. Enforcing only the first
    half is what produced the bug this list was written to close: a session
    launched without uwsm reaches no graphical-session.target, so systemd starts
    none of the five, and a file that merely omits them leaves that session with
    no bar, no notifications and no hypridle — nothing locks the screen.

  * The list is the single source of truth. Anything in bin/ that calls
    lib/units.sh must name a unit and binary that appear in it, so the toggles
    and the session start cannot drift apart.

The set of unit-backed daemons is READ FROM THE LIST rather than repeated here.
Repeating it is how the two would disagree.
"""
import re
import sys

LIST = "default/session-daemons.tsv"
AUTOSTART = "default/hypr/autostart.conf"
STARTER = "omakeb-session-daemons"
BIN_GLOB = "bin/omakeb-*"

# Commands that legitimately run once and exit; everything else is treated as a
# daemon and must be wrapped.
ONESHOT = {
    "uwsm", "makoctl", "hyprctl", "sleep", "omakeb-toggle-enabled",
    "command", "true", ":", "omakeb-daemon", "systemctl",
    "omakeb-nightlight-apply", "omakeb-gl-fallback", "omakeb-monitor-apply",
    STARTER,
}

problems = []


def fail(where, what, hint):
    problems.append((where, what, hint))


# --- the list -----------------------------------------------------------------

rows = []
try:
    with open(LIST) as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) != 4:
                fail(f"{LIST}:{lineno}", f"{len(fields)} column(s), expected 4",
                     "name, unit, binary, off-toggle (use '-' for no toggle)")
                continue
            rows.append((lineno, *fields))
except FileNotFoundError:
    print(f"{LIST} is missing; it is the source of truth for session daemons.")
    sys.exit(1)

if not rows:
    fail(LIST, "no daemons listed",
         "if that is deliberate, delete the file and this check with it")

seen_names, seen_units = {}, {}
for lineno, name, unit, binary, off in rows:
    if name in seen_names:
        fail(f"{LIST}:{lineno}", f"duplicate name {name!r}",
             f"already listed on line {seen_names[name]}")
    seen_names[name] = lineno
    if unit in seen_units:
        fail(f"{LIST}:{lineno}", f"duplicate unit {unit!r}",
             f"already listed on line {seen_units[unit]}")
    seen_units[unit] = lineno
    if not unit.endswith(".service"):
        fail(f"{LIST}:{lineno}", f"unit {unit!r} is not a .service",
             "lib/units.sh passes this straight to systemctl --user")
    if off != "-" and not re.fullmatch(r"[a-z0-9-]+", off):
        fail(f"{LIST}:{lineno}", f"off-toggle {off!r} is not a toggle name",
             "C3 toggle names are lowercase and hyphenated, or '-' for none")

UNIT_BACKED = {binary for _, _, _, binary, _ in rows}
UNITS = {unit: binary for _, _, unit, binary, _ in rows}

# --- autostart.conf -----------------------------------------------------------

starter_present = False

for lineno, raw in enumerate(open(AUTOSTART), 1):
    line = raw.strip()
    if not line.startswith("exec-once"):
        continue

    cmd = line.split("=", 1)[1]
    # hyprlang truncates at an unescaped '#', so do the same before parsing.
    cmd = cmd.split("#", 1)[0]

    # Drop redirections first: splitting on '&' before this turns `2>&1` into a
    # bare `1` and reports it as an unguarded daemon.
    cmd = re.sub(r"\d?>\s*&?\s*\S+", " ", cmd)

    # Split on the logical operators only — never on single & or |, and never
    # on ';', which appears inside `hyprctl --batch "a ; b"` quoted arguments.
    for branch in re.split(r"\|\||&&", cmd):
        branch = branch.strip()
        if not branch:
            continue
        tokens = branch.split()
        first = tokens[0].strip('"\'').rsplit("/", 1)[-1]

        if first == STARTER:
            starter_present = True

        # Look through the wrapper: `omakeb-daemon waybar` still starts waybar,
        # so the unit-backed check has to see the wrapped command, not the
        # wrapper. Missing this made the guard useless for the exact line it
        # was written to catch.
        effective = first
        if first == "omakeb-daemon" and len(tokens) > 1:
            effective = tokens[1].strip('"\'').rsplit("/", 1)[-1]

        if effective in UNIT_BACKED:
            fail(f"{AUTOSTART}:{lineno}", branch,
                 f"{effective} is in {LIST}; {STARTER} starts it, and a second "
                 f"starter here is the stacked-bar bug. Remove this line.")
            continue
        if first in ONESHOT:
            continue
        fail(f"{AUTOSTART}:{lineno}", branch, f"omakeb-daemon {branch}")

if not starter_present:
    fail(AUTOSTART, f"no `exec-once = {STARTER}` line",
         f"without it nothing starts the {len(rows)} daemons in {LIST} on a "
         f"session that does not reach graphical-session.target — no bar, no "
         f"notifications, and no hypridle to lock the screen")

# --- bin/ agrees with the list ------------------------------------------------
#
# lib/units.sh takes (unit, binary) pairs from its callers. A caller naming a
# unit that is not in the list, or pairing a unit with the wrong binary, is the
# drift this file exists to prevent.

import glob

CALL = re.compile(
    r"\bservice_(?:up|down|restart|running)\s+(\S+)\s+(\S+)")

for path in sorted(glob.glob(BIN_GLOB)):
    try:
        with open(path) as fh:
            source = fh.read()
    except (OSError, UnicodeDecodeError):
        continue
    for lineno, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        m = CALL.search(line)
        if not m:
            continue
        unit, binary = m.group(1), m.group(2)
        if unit.startswith("$") or binary.startswith("$"):
            continue  # a variable; nothing static to check
        if unit not in UNITS:
            fail(f"{path}:{lineno}", f"service_* call names {unit!r}",
                 f"that unit is not in {LIST}; add it there so session start "
                 f"and the toggles agree")
        elif UNITS[unit] != binary:
            fail(f"{path}:{lineno}", f"{unit} paired with {binary!r}",
                 f"{LIST} says {unit} is {UNITS[unit]!r}")

# --- report -------------------------------------------------------------------

if problems:
    print(f"{len(problems)} session-start problem(s):")
    for where, what, hint in problems:
        print(f"  {where}: {what}")
        print(f"      -> {hint}")
    print("\nSee default/session-daemons.tsv and bin/omakeb-daemon for why.")
    sys.exit(1)

print(f"{len(rows)} session daemons declared in {LIST}; {STARTER} starts them; "
      f"every autostart daemon goes through omakeb-daemon")
