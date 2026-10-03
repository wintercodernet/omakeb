#!/bin/bash
# Static checks for the ~/.bashrc line install/40-shell.sh maintains.
#
# The step writes ONE marker plus ONE source line naming the absolute checkout
# path. What can go wrong, and what each group below pins down:
#
#   * a re-run must change nothing — not a byte. install.sh and omakeb-update
#     both re-run every step, forever.
#   * a moved checkout must be followed. The first version skipped whenever the
#     marker was present, so the line kept the first install's path, failed its
#     own -r guard, and the shell silently lost every omakeb default.
#   * following it must touch that one line only. Everything else in ~/.bashrc
#     belongs to the user, including odd bytes and a missing final newline.
#   * paths are arbitrary, so no sed delimiter is safe; a path full of them must
#     round-trip.
#
# Every call runs in a SEPARATE `bash -euo pipefail` process, because that is
# how install.sh runs the step, and because testing under `if ( set -e; ... )`
# suspends errexit and passes with the bug present.
#
# Runs anywhere, including macOS bash 3.2: the function is extracted from the
# step and pointed at temp files, so no Debian and no real $HOME are involved.

set -uo pipefail
cd "$(dirname "$0")/.."

# A counter, not a flag: see test/lint-keyboard.sh for why.
fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

STEP=install/40-shell.sh
[[ -r $STEP ]] || { echo "  FAIL: $STEP is missing"; exit 1; }

fn=$(sed -n '/^ensure_bashrc_line() {/,/^}/p' "$STEP")
[[ -n $fn ]] || { echo "  FAIL: ensure_bashrc_line not found in $STEP"; exit 1; }
export OMAKEB_TEST_FN=$fn

# The step must actually call it, against the real ~/.bashrc and checkout.
if grep -qxF 'ensure_bashrc_line "$HOME/.bashrc" "$OMAKEB_PATH"' "$STEP"; then
  ok "the step calls ensure_bashrc_line on \$HOME/.bashrc with \$OMAKEB_PATH"
else
  bad "$STEP no longer calls ensure_bashrc_line \"\$HOME/.bashrc\" \"\$OMAKEB_PATH\""
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ensure <bashrc> <checkout-path>: run the function in a fresh strict shell.
# Returns that shell's exit status; output goes to $tmpdir/out for inspection.
ensure() {
  bash -euo pipefail -c '
    source lib/log.sh
    eval "$OMAKEB_TEST_FN"
    ensure_bashrc_line "$1" "$2"
  ' _ "$1" "$2" > "$tmpdir/out" 2>&1
}

line_for() {
  printf '[ -r "%s/default/bash/rc.sh" ] && . "%s/default/bash/rc.sh"' "$1" "$1"
}

old=/home/me/.local/share/omakeb
new=/opt/omakeb

# --- 1. a missing ~/.bashrc is created with the marker and the line -----------
rc=$tmpdir/fresh/.bashrc
mkdir -p "$(dirname "$rc")"
before=$fail
ensure "$rc" "$old" || bad "fresh: exited non-zero under set -euo pipefail: $(cat "$tmpdir/out")"
if [[ -f $rc ]]; then
  expect=$(printf '\n# omakeb:bashrc\n%s\n' "$(line_for "$old")"; printf x)
  got=$(cat "$rc"; printf x)
  [[ $got == "$expect" ]] || bad "fresh: unexpected content: $(od -c "$rc" | head -5)"
else
  bad "fresh: ~/.bashrc was not created"
fi
(( fail == before )) && ok "a missing ~/.bashrc is created holding the marker and one source line"

# --- 2. a re-run changes nothing ----------------------------------------------
cp "$rc" "$tmpdir/snap"
before=$fail
ensure "$rc" "$old" || bad "re-run: exited non-zero: $(cat "$tmpdir/out")"
cmp -s "$rc" "$tmpdir/snap" || bad "re-run: ~/.bashrc changed on a second run"
(( fail == before )) && ok "a second run leaves ~/.bashrc byte-identical"

# --- 3. a moved checkout rewrites that line and nothing else ------------------
#
# User content on both sides of our block, including a line that mentions the
# old path (it is theirs, and must not be "helpfully" rewritten), a line with
# sed metacharacters, and no final newline.
rc=$tmpdir/moved/.bashrc
mkdir -p "$(dirname "$rc")"
{
  printf '# stock Debian stuff\nexport PS1="\\u@\\h:\\w\\$ "\n'
  printf 'alias o="cd %s"\n' "$old"
  printf '\n# omakeb:bashrc\n%s\n' "$(line_for "$old")"
  printf 's/a|b/&\\1/g # not a command\n'
  printf 'export AFTER=1'
} > "$rc"
{
  printf '# stock Debian stuff\nexport PS1="\\u@\\h:\\w\\$ "\n'
  printf 'alias o="cd %s"\n' "$old"
  printf '\n# omakeb:bashrc\n%s\n' "$(line_for "$new")"
  printf 's/a|b/&\\1/g # not a command\n'
  printf 'export AFTER=1'
} > "$tmpdir/expect"
before=$fail
ensure "$rc" "$new" || bad "moved: exited non-zero: $(cat "$tmpdir/out")"
cmp -s "$rc" "$tmpdir/expect" || bad "moved: result differs from the expected file:
$(diff "$tmpdir/expect" "$rc")"
(( fail == before )) && ok "a moved checkout rewrites only the source line; user content is byte-for-byte intact"

cp "$rc" "$tmpdir/snap"
before=$fail
ensure "$rc" "$new" || bad "moved re-run: exited non-zero: $(cat "$tmpdir/out")"
cmp -s "$rc" "$tmpdir/snap" || bad "moved re-run: ~/.bashrc changed again"
(( fail == before )) && ok "after the rewrite, a further run changes nothing"

# --- 4. a path full of sed delimiters round-trips -----------------------------
weird='/srv/a|b#c&d\e/f g'
before=$fail
ensure "$rc" "$weird" || bad "weird path: exited non-zero: $(cat "$tmpdir/out")"
{
  printf '# stock Debian stuff\nexport PS1="\\u@\\h:\\w\\$ "\n'
  printf 'alias o="cd %s"\n' "$old"
  printf '\n# omakeb:bashrc\n%s\n' "$(line_for "$weird")"
  printf 's/a|b/&\\1/g # not a command\n'
  printf 'export AFTER=1'
} > "$tmpdir/expect"
cmp -s "$rc" "$tmpdir/expect" || bad "weird path: result differs:
$(diff "$tmpdir/expect" "$rc")"
cp "$rc" "$tmpdir/snap"
ensure "$rc" "$weird" || bad "weird path re-run: exited non-zero"
cmp -s "$rc" "$tmpdir/snap" || bad "weird path re-run: ~/.bashrc changed again"
(( fail == before )) && ok "a checkout path containing | # & \\ and a space is written and recognised"

# --- 5. a hand-edited line after the marker is left alone ---------------------
rc=$tmpdir/edited/.bashrc
mkdir -p "$(dirname "$rc")"
printf 'x=1\n# omakeb:bashrc\n# [ -r "%s/default/bash/rc.sh" ] && . "%s/default/bash/rc.sh"\ny=2\n' \
  "$old" "$old" > "$rc"
cp "$rc" "$tmpdir/snap"
before=$fail
ensure "$rc" "$new" || bad "hand-edited: exited non-zero: $(cat "$tmpdir/out")"
cmp -s "$rc" "$tmpdir/snap" || bad "hand-edited: a line the user changed was rewritten"
grep -q 'leaving it alone' "$tmpdir/out" || bad "hand-edited: no warning explaining why nothing changed"
(( fail == before )) && ok "a marker followed by a line the user edited is left alone, with a warning"

# The marker as the very last line (the user deleted our line) is the same case.
printf 'x=1\n# omakeb:bashrc' > "$rc"
cp "$rc" "$tmpdir/snap"
before=$fail
ensure "$rc" "$new" || bad "marker last: exited non-zero: $(cat "$tmpdir/out")"
cmp -s "$rc" "$tmpdir/snap" || bad "marker last: ~/.bashrc was changed"
(( fail == before )) && ok "a marker with no line after it is left alone rather than failing"

# --- 6. a symlinked ~/.bashrc stays a symlink ---------------------------------
rc=$tmpdir/linked/.bashrc
mkdir -p "$tmpdir/linked/dotfiles"
printf 'mine=1\n\n# omakeb:bashrc\n%s\n' "$(line_for "$old")" > "$tmpdir/linked/dotfiles/bashrc"
ln -s dotfiles/bashrc "$rc"
before=$fail
ensure "$rc" "$new" || bad "symlink: exited non-zero: $(cat "$tmpdir/out")"
[[ -L $rc ]] || bad "symlink: ~/.bashrc was replaced by a regular file"
grep -qxF "$(line_for "$new")" "$tmpdir/linked/dotfiles/bashrc" \
  || bad "symlink: the link target was not updated"
(( fail == before )) && ok "a ~/.bashrc that is a symlink is edited through the link, not replaced"

echo
if (( fail )); then
  echo "  $fail check(s) failed"
  exit 1
fi
