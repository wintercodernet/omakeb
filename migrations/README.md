# Migrations

One-off fixes for machines that **already have omakeb on them**. Run by
`install/05-migrations.sh`, which both `install.sh` and `omakeb-update` reach.

## You probably do not need one

Every install step is idempotent and `install.sh` is the repair tool. Adding a
package to `packages/*.list`, changing a template, adding a `bin/` command or
rewriting a config in `default/` is delivered to every machine simply by
reconverging — which is what `omakeb-update` does on every run. No migration.

A migration is for what reconverging cannot reach, because it is about
**removing or renaming** something an older omakeb created:

- a `~/.config` file we no longer generate, and which now shadows something
- a systemd unit, apt source or pin we stopped shipping
- a state key whose name or meaning changed
- a user override file that has to be rewritten in place rather than reseeded

If reconverging fixes it, do that instead. A migration is code that runs once on
every existing machine and then never again, which makes it the hardest kind of
code in this repo to test.

## Writing one

```sh
printf '%s\n' "$(date +%s)"      # the filename, without .sh
```

`migrations/1756713600.sh`:

```bash
# omakeb:migration=Remove the waybar config we stopped generating in 0.3.
stale="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/modules.json"
if [[ -f $stale ]]; then
  rm -f "$stale"
  log_ok "removed the obsolete $stale"
else
  log_skip "no obsolete waybar modules.json"
fi
```

## The contract

- **Name it `<unix-epoch>.sh`.** Digits only. Epoch, not a date —
  `20260901.sh` is a valid integer that means *August 1970*, so it would sort
  before every real migration and be skipped forever. `test/lint-migrations.sh`
  rejects it.
- **It is sourced in a subshell** with `lib/all.sh` already loaded and
  `set -euo pipefail` on. Every `log_*` helper, `state_get`/`state_set`,
  `write_file`, `apt_install` and `$OMAKEB_PATH`/`$OMAKEB_STATE`/`$OMAKEB_CONFIG`
  are available. It cannot affect the runner's variables or working directory.
- **It must be idempotent, and a no-op on a machine that never had the
  problem.** A machine installed before migrations existed has no high-water
  mark, reads it as 0 and runs every migration ever written. That is deliberate:
  skipping a needed one is a bug, running an unneeded one must cost nothing.
- **It must not assume a session.** No compositor, no D-Bus, no network. It runs
  from a TTY, from an install container, and over SSH.
- **Non-zero aborts the update.** The high-water mark stays where it was, so
  nothing after it runs and a re-run resumes at the failure. Say why in the
  failure — the user is reading it on a machine that is now half-updated.
- **Never write to the user's own files** (`~/.config/omakeb/*`) unless the
  whole point is to rewrite one, and then say so in the description. Those are
  seeded with `run_once` precisely because we cannot tell an untouched file from
  one the user deliberately emptied.

## How the ordering works

The mark lives in `~/.local/state/omakeb/migration` and holds the epoch of the
last migration that succeeded. Only newer ones run, and it advances after each
one — a failure at the third of five leaves the first two recorded.

A **fresh install** stamps the mark to the newest migration without running any
of them: a machine built by the current omakeb is already in the state those
migrations produce. `install.sh` detects this by whether `$OMAKEB_STATE` existed
before it started.
