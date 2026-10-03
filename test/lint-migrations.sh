#!/bin/bash
# Migrations: the names, and the runner's semantics.
#
# Two failures this is about, both silent.
#
# NAMING. A migration named `20260901.sh` is a valid integer and a plausible
# date, and as a unix epoch it is 23 August 1970. It therefore sorts before
# every real migration and is skipped forever on any machine whose high-water
# mark is already set. Nothing reports it; the fix simply never runs.
#
# ERREXIT. A migration that fails at its third line must stop there, must not
# be recorded as applied, and must not let the migrations after it run. Getting
# that right depends on two easy-to-drop lines in lib/migrate.sh — the `set +e`
# in the runner and the `set -euo pipefail` inside the subshell — and dropping
# either fails silently, in the direction of reporting success. Cases 4 and 5
# below are mutation-tested against exactly those two edits.
#
# Note on errexit suspension, because the boundary is narrower than it reads and
# it cost time here: errexit suspension inside a tested command does NOT reach
# through `source`. Measured on bash 3.2:
#
#   if ( set -e; false; echo LATER ); then ...          -> LATER runs, rc=0
#   if ( set -e; source file-whose-first-line-is-false ) -> stops, rc=1
#
# So the runner would survive being written in the tested form, since a
# migration always arrives via `source`. It is not written that way regardless:
# the `set +e` / read-`$?` form does not depend on that distinction at all, and
# the distinction has only been measured on bash 3.2, not on Debian's 5.2.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

MIN_EPOCH=1735689600   # 2025-01-01, mirroring OMAKEB_MIGRATION_MIN_EPOCH
MAX_EPOCH=4102444800   # 2100-01-01

# --- the migrations actually in the repo --------------------------------------

shopt -s nullglob
found=0
seen=""
for f in migrations/*.sh; do
  found=$((found + 1))
  base=$(basename "$f" .sh)

  if [[ ! $base =~ ^[0-9]+$ ]]; then
    bad "$f: name is not a unix epoch (digits only, no suffix)"
    continue
  fi
  if (( base < MIN_EPOCH )); then
    bad "$f: $base is before 2025 — a YYYYMMDD name read as an epoch. Use: date +%s"
    continue
  fi
  if (( base > MAX_EPOCH )); then
    bad "$f: $base is beyond 2100; that is not a timestamp"
    continue
  fi
  case " $seen " in
    *" $base "*) bad "$f: duplicate epoch $base" ; continue ;;
  esac
  seen="$seen $base"

  bash -n "$f" || { bad "$f: syntax error"; continue; }

  if ! grep -q '^# omakeb:migration=' "$f"; then
    bad "$f: no '# omakeb:migration=' description line"
    continue
  fi
  ok "$(basename "$f") — $(sed -n '/^# omakeb:migration=/{s/^# omakeb:migration=//;p;q;}' "$f")"
done
(( found )) || ok "no migrations in the repo yet"

# --- the runner, against fixtures ---------------------------------------------
#
# Driven through a SEPARATE BASH PROCESS that sets `set -euo pipefail`, because
# that is how install.sh and omakeb-update run it and the difference is the
# whole point. errexit suspension inside a tested command is only inherited when
# the CALLER already had errexit on; a test harness running under `set -uo
# pipefail` (as every check in this directory does, so one failure does not
# abort the suite) never has it, so the broken form of the runner passes when
# called from here and fails on a real machine.
#
# That is not a hypothetical: this check was first written calling the runner
# in-process, and the mutation test passed with the bug present.

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OMAKEB_PATH="$PWD"
export OMAKEB_MIGRATIONS="$tmp/migrations"
export OMAKEB_STATE="$tmp/state"
export OMAKEB_CONFIG="$tmp/config"
export OMAKEB_CACHE="$tmp/cache"

# The driver. One line of it matters: `set -euo pipefail`, matching install.sh.
cat > "$tmp/driver.sh" <<'DRIVER'
#!/bin/bash
set -euo pipefail
source "$OMAKEB_PATH/lib/all.sh"
"$@"
DRIVER

drive() { bash "$tmp/driver.sh" "$@" 2>&1; }

reset_fixtures() {
  rm -rf "$OMAKEB_MIGRATIONS" "$OMAKEB_STATE" "$tmp/out"
  mkdir -p "$OMAKEB_MIGRATIONS" "$OMAKEB_STATE" "$tmp/out"
}

# Three well-formed migrations, each leaving a trace so we can see what ran.
write_ok_fixtures() {
  local e
  for e in 1750000000 1750000001 1750000002; do
    cat > "$OMAKEB_MIGRATIONS/$e.sh" <<FIX
# omakeb:migration=fixture $e
printf '%s\n' "$e" >> "$tmp/out/ran"
FIX
  done
}

trace() { [[ -f "$tmp/out/ran" ]] || return 0; tr '\n' ' ' < "$tmp/out/ran" | sed 's/ $//'; }
mark()  { cat "$OMAKEB_STATE/migration" 2>/dev/null || echo 0; }

# 0. The harness itself must be running the code the way production does.
if grep -q 'set -euo pipefail' "$tmp/driver.sh"; then
  ok "the runner is driven from a shell with errexit on, as install.sh does"
else
  bad "the driver does not set errexit; these cases would not reproduce production"
fi

# 1. Pending run in order, and the mark ends at the newest.
reset_fixtures; write_ok_fixtures
out=$(drive migrate_run_pending); rc=$?
if (( rc == 0 )) && [[ "$(trace)" == "1750000000 1750000001 1750000002" ]] \
   && [[ "$(mark)" == 1750000002 ]]; then
  ok "pending migrations run oldest-first and advance the mark"
else
  bad "pending run: rc=$rc trace='$(trace)' mark='$(mark)'"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# 2. A second run is a no-op. This is the property that makes update re-runnable.
rm -f "$tmp/out/ran"
drive migrate_run_pending >/dev/null 2>&1
if [[ -z "$(trace)" ]] && [[ "$(mark)" == 1750000002 ]]; then
  ok "an applied migration does not run again"
else
  bad "re-run was not a no-op: trace='$(trace)' mark='$(mark)'"
fi

# 3. A fresh install stamps the mark and runs nothing.
reset_fixtures; write_ok_fixtures
drive migrate_stamp_latest >/dev/null 2>&1
if [[ -z "$(trace)" ]] && [[ "$(mark)" == 1750000002 ]]; then
  ok "a fresh install records migrations as applied without running them"
else
  bad "stamp ran something or set the wrong mark: trace='$(trace)' mark='$(mark)'"
fi

# 4. The middle migration fails at its first statement. Four things must hold.
#    Dropping `set -euo pipefail` from inside the runner's subshell breaks the
#    second and third; dropping the `set +e` around it breaks the fourth, because
#    the subshell's failure then aborts the runner before it can read `$?` and
#    the user is left with a bare trap message instead of the resume
#    instructions. Both are mutation-tested.
reset_fixtures; write_ok_fixtures
cat > "$OMAKEB_MIGRATIONS/1750000001.sh" <<FIX
# omakeb:migration=fixture that fails
false
printf 'REACHED_LINE_AFTER_FAILURE\n' >> "$tmp/out/ran"
FIX
out=$(drive migrate_run_pending); rc=$?
if (( rc != 0 )); then
  ok "a failing migration makes the runner return non-zero"
else
  bad "a failing migration was reported as success; the subshell is not running under errexit"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
case "$(trace)" in
  *REACHED_LINE_AFTER_FAILURE*)
    bad "the migration kept running past a failed command; the subshell's set -e is not in force" ;;
  *) ok "a failing migration stops at the failing command" ;;
esac
case "$(trace)" in
  *1750000002*) bad "a migration after the failing one still ran" ;;
  *)            ok "nothing after a failed migration runs" ;;
esac

# The failure has to explain how to get out of it. A user meeting this is on a
# half-updated machine and needs to know the mark did not advance and what to do
# about it — a bare "update failed" from the ERR trap is not that.
if grep -q 'record it as applied with' <<<"$out" && grep -q 'The mark stays at' <<<"$out"; then
  ok "a failed migration explains the mark and how to resume"
else
  bad "the runner aborted without printing resume instructions (was the 'set +e' dropped?)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# 5. The mark stays at the last SUCCESS, so a re-run resumes at the failure.
if [[ "$(mark)" == 1750000000 ]]; then
  ok "the mark stops at the last successful migration ($(mark))"
else
  bad "mark should be 1750000000 after failing at 1750000001, got '$(mark)'"
fi

# 6. A migration cannot cd, exit or clobber the runner.
reset_fixtures
cat > "$OMAKEB_MIGRATIONS/1750000000.sh" <<'FIX'
# omakeb:migration=fixture that misbehaves
cd /
pending=CLOBBERED
f=CLOBBERED
FIX
cat > "$OMAKEB_MIGRATIONS/1750000001.sh" <<FIX
# omakeb:migration=fixture proving the runner survived
printf 'survived\n' >> "$tmp/out/ran"
FIX
out=$(drive migrate_run_pending); rc=$?
if (( rc == 0 )) && [[ "$(trace)" == survived ]] && [[ "$(mark)" == 1750000001 ]]; then
  ok "a migration cannot cd or clobber the runner's loop variables"
else
  bad "runner was affected by the migration: rc=$rc trace='$(trace)' mark='$(mark)'"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# 7. A non-epoch filename is ignored loudly, not run silently.
reset_fixtures
cat > "$OMAKEB_MIGRATIONS/fix-the-thing.sh" <<FIX
# omakeb:migration=badly named
printf 'BADNAME_RAN\n' >> "$tmp/out/ran"
FIX
out=$(drive migrate_run_pending)
if [[ "$(trace)" != *BADNAME_RAN* ]] && grep -q "non-epoch name" <<<"$out"; then
  ok "a non-epoch filename is skipped with a warning"
else
  bad "non-epoch filename handling: trace='$(trace)'"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# 8. A corrupt mark file reads as 0 rather than crashing the update.
reset_fixtures; write_ok_fixtures
printf 'not-a-number\n' > "$OMAKEB_STATE/migration"
got=$(drive migrate_mark)
if [[ "$got" == 0 ]]; then
  ok "a corrupt high-water mark reads as 0 (runs everything, the safe direction)"
else
  bad "corrupt mark read as '$got', expected 0"
fi

# --- state keys with a slash in them ------------------------------------------
#
# tier3_version_set writes "app-version/<id>", and state_set could not create
# the parent directory. It failed late — after the app was installed — so the
# caller aborted having done the work and recorded none of it.
reset_fixtures
out=$(drive state_set "app-version/fixture" "1.2.3"); rc=$?
if (( rc == 0 )) && [[ "$(cat "$OMAKEB_STATE/app-version/fixture" 2>/dev/null)" == "1.2.3" ]]; then
  ok "state_set creates the parent directory for a nested key"
else
  bad "state_set cannot write a nested key (rc=$rc): $out"
fi

# --- the install-time wiring --------------------------------------------------

if grep -q 'OMAKEB_FRESH_INSTALL' install.sh && grep -q 'migrate_stamp_latest' install/05-migrations.sh; then
  ok "install.sh detects a fresh install and 05-migrations acts on it"
else
  bad "the fresh-install path is not wired up between install.sh and install/05-migrations.sh"
fi

# The detection must be read before anything can create the state directory.
detect_line=$(grep -n 'OMAKEB_FRESH_INSTALL=' install.sh | head -1 | cut -d: -f1)
preflight_line=$(grep -n 'install/preflight.sh' install.sh | head -1 | cut -d: -f1)
if [[ -n $detect_line && -n $preflight_line ]] && (( detect_line < preflight_line )); then
  ok "the fresh-install check runs before preflight, so nothing has created \$OMAKEB_STATE yet"
else
  bad "install.sh reads OMAKEB_FRESH_INSTALL at line ${detect_line:-?}, after preflight at ${preflight_line:-?}"
fi

echo
if (( fail )); then
  echo "$fail migration check(s) failed"
  exit 1
fi
echo "migrations: all checks passed"
