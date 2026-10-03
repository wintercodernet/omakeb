#!/bin/bash
# Static checks for the optional-software layer (lib/apps.sh, apps/*.sh).
#
# The failure this is mostly about: a third-party repository whose signing key
# no longer matches is not a failure of that app alone. `apt-get update` reports
# the broken repository on EVERY later apt operation, so one optional app that
# will not install takes out every one installed after it. That is what a stale
# Spotify key did — it broke Edge and VS Code, which have nothing to do with it.
#
# So repo_add has to leave the machine as it found it when a repository does not
# verify, and repo_usable has to actually notice, including in the case where
# apt reports a signature it cannot verify and still exits 0.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# --- repo_usable, driven by a fake apt-get ------------------------------------
source lib/log.sh
eval "$(sed -n '/^repo_usable() {/,/^}/p' lib/apps.sh)"
APT_ENV=(env)
sudo() { "$@"; }              # the test is not about privilege
printf 'x\n' > "$tmp/fake.sources"

fake_apt() {  # fake_apt <exit-code> <output>
  cat > "$tmp/bin/apt-get" <<FAKE
#!/bin/bash
cat <<'OUT'
$2
OUT
exit $1
FAKE
  chmod +x "$tmp/bin/apt-get"
}

check_usable() {  # check_usable <expect ok|fail> <label>
  local want=$1 label=$2
  if PATH="$tmp/bin:$PATH" repo_usable "$tmp/fake.sources"; then got=ok; else got=fail; fi
  [[ $got == "$want" ]] && ok "$label" || bad "$label: expected $want, got $got"
}

fake_apt 0 "Get:1 https://example.com stable InRelease
Reading package lists..."
check_usable ok "a repository that fetches and verifies is usable"

fake_apt 100 "E: Failed to fetch https://example.com/dists/stable/InRelease"
check_usable fail "a non-zero apt-get update means unusable"

# The one that matters: some apt versions report an unverifiable signature and
# still exit 0. Trusting the exit status alone would let the broken source stay.
fake_apt 0 "E: The repository 'https://repository.spotify.com stable InRelease' is not signed.
N: Updating from such a repository can't be done securely, and is therefore disabled by default."
check_usable fail "an unsigned repository is unusable even when apt exits 0"

fake_apt 0 "W: GPG error: https://example.com stable InRelease: The following signatures couldn't be verified: NO_PUBKEY ABCDEF"
check_usable fail "a NO_PUBKEY GPG error is unusable even when apt exits 0"

# --- repo_usable must not damage the rest of apt ------------------------------
before=$fail
grep -q 'APT::Get::List-Cleanup=0' lib/apps.sh ||
  bad "repo_usable does not set List-Cleanup=0; apt would delete every other repository's lists"
grep -q 'Dir::Etc::sourceparts=' lib/apps.sh ||
  bad "repo_usable does not restrict itself to a private sourceparts directory"
(( fail == before )) && ok "the check is scoped to one source and leaves other repositories' lists alone"

# --- repo_add must roll back --------------------------------------------------
before=$fail
add=$(sed -n '/^repo_add() {/,/^}/p' lib/apps.sh)
grep -q 'repo_usable' <<<"$add" ||
  bad "repo_add never verifies the source it just wrote"
grep -qE 'rm -f "\$source"' <<<"$add" ||
  bad "repo_add does not remove the source when verification fails; one bad repo breaks every later install"
grep -qE 'rm -f "\$keyring"' <<<"$add" ||
  bad "repo_add leaves the keyring behind on failure; the download is skipped when it exists, so every retry fails identically"
(( fail == before )) && ok "repo_add verifies the new source and rolls it back on failure"

# --- both key encodings are handled -------------------------------------------
before=$fail
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' <<<"$add" ||
  bad "repo_add does not distinguish armoured from binary keys"
grep -q 'gpg --show-keys' <<<"$add" ||
  bad "repo_add does not validate that the downloaded bytes are actually a key"
(( fail == before )) && ok "armoured and binary signing keys are both accepted, and validated either way"

# --- the app definitions ------------------------------------------------------
before=$fail
while read -r f; do
  while read -r url; do
    [[ $url == https://* ]] || bad "$(basename "$f"): key URL is not https: $url"
  done < <(grep -oE 'https?://[^ \\]*' "$f" | grep -iE 'key|pubkey|\.asc|/gpg$')
done < <(ls apps/*.sh)
(( fail == before )) && ok "every signing key is fetched over https"

# Spotify pins a key by id and Spotify rotates them; the id in the URL and the
# id recorded in the comment must not drift apart.
before=$fail
url_id=$(grep -oE 'pubkey_[0-9A-F]{16}\.gpg' apps/spotify.sh | head -1 | sed 's/pubkey_//; s/\.gpg//')
doc_id=$(grep -oE '[0-9A-F]{16}, fpr' apps/spotify.sh | head -1 | sed 's/,.*//')
if [[ -z $url_id ]]; then
  bad "spotify.sh no longer pins a pubkey_<keyid>.gpg URL"
elif [[ $url_id != "$doc_id" ]]; then
  bad "spotify.sh pins $url_id but documents $doc_id; one of them is stale"
else
  ok "spotify's pinned key id matches the fingerprint recorded beside it ($url_id)"
fi

# An upstream that drops its own sources.list entry in postinst leaves apt
# warning "configured multiple times" on every update, once per target, forever.
# Both of these are known to do it, verified on the test machine.
before=$fail
for app in spotify vscode; do
  grep -q 'repo_yield_to_vendor' "apps/$app.sh" ||
    bad "apps/$app.sh adds a repo but never yields to the vendor's own source list"
done
(( fail == before )) && ok "apps whose package ships its own source list stand ours down"

# --- npm_tool_install under the runner's own shell options --------------------
#
# omakeb-install-app runs `set -euo pipefail` and calls app_install from an
# untested position. There, `x=$(cmd | grep -o … | head -1)` is a statement that
# fails whenever grep matches nothing, and it ends the script — silently, and in
# the version case AFTER the tool is installed, so nothing gets recorded.
#
# A separate bash process, not `if ( set -e; … )`: a tested
# command has errexit suspended inside it and the check passes with the bug
# present. The status is read afterwards instead.
mkdir -p "$tmp/npmstub" "$tmp/home"
for stub in npm node; do
  # Print nothing and succeed: a package with no engines field, and a node that
  # says nothing useful. Exactly the inputs grep finds no match in.
  printf '#!/bin/bash\nexit 0\n' > "$tmp/npmstub/$stub"
done
# The tool itself prints whatever the case asks for.
printf '#!/bin/bash\nprintf "%%s" "${FAKE_TOOL_OUT:-}"\n' > "$tmp/npmstub/faketool"
chmod +x "$tmp/npmstub"/*

drive_npm() {  # drive_npm <state-dir> <tool --version output>
  PATH="$tmp/npmstub:$PATH" HOME="$tmp/home" OMAKEB_STATE=$1 \
    OMAKEB_CONFIG="$tmp/config" OMAKEB_CACHE="$tmp/cache" FAKE_TOOL_OUT=$2 bash -c '
    set -euo pipefail
    source lib/log.sh; source lib/state.sh; source lib/apps.sh
    apt_install() { :; }     # nodejs and npm are "already there"
    npm_tool_install fake fake-pkg faketool
    echo REACHED-THE-END' 2>&1
}

out=$(drive_npm "$tmp/state-npm1" ""); rc=$?
recorded=$(cat "$tmp/state-npm1/app-version/fake" 2>/dev/null)
if (( rc == 0 )) && grep -q REACHED-THE-END <<<"$out" && [[ $recorded == unknown ]]; then
  ok "npm_tool_install survives set -euo pipefail with no engines field and no version, recording 'unknown'"
else
  bad "npm_tool_install under set -euo pipefail: rc=$rc, recorded='${recorded}' (a grep with no match ended the install)"
  sed 's/^/        /' <<<"$out"
fi

out=$(drive_npm "$tmp/state-npm2" "faketool 1.2.3 (build abc)"); rc=$?
recorded=$(cat "$tmp/state-npm2/app-version/fake" 2>/dev/null)
if (( rc == 0 )) && [[ $recorded == 1.2.3 ]]; then
  ok "npm_tool_install records the version the tool reports"
else
  bad "npm_tool_install recorded '${recorded}' (rc=$rc), expected 1.2.3"
fi

# The same class of bug, anywhere else in the app layer: a command substitution
# whose pipeline ends in grep -o or head, with nothing to absorb a no-match.
before=$fail
while IFS= read -r hit; do
  bad "unguarded grep in a command substitution (fatal under pipefail when it matches nothing): $hit"
done < <(grep -nE '=\$\(.*\|[[:space:]]*grep -o' lib/apps.sh apps/*.sh bin/omakeb-install-app |
         grep -v '|| true')
(( fail == before )) && ok "no command substitution in the app layer dies when its grep matches nothing"

# --- tier-3 staleness ---------------------------------------------------------
#
# D4: tier 3 gets security updates from nobody, and the report is the whole
# mitigation. So every tier-3 app must either be able to say what the latest
# upstream version is, or be explicitly declared as updating itself — never
# silently neither.
before=$fail
for f in apps/*.sh; do
  grep -qE '^app_tier=3' "$f" || continue
  if ! grep -qE '^app_latest\(\)' "$f" && ! grep -qE '^app_self_updating=1' "$f"; then
    bad "$(basename "$f") is tier 3 but defines no app_latest and is not app_self_updating=1"
  fi
done
(( fail == before )) && ok "every tier-3 app can report its latest version, or is declared self-updating"

grep -q 'tier3_report' bin/omakeb-update ||
  bad "omakeb-update never calls tier3_report; recorded tier-3 versions are never looked at"

# The report runs inside omakeb-update's set -euo pipefail. A network failure,
# an app file that is gone, or an app_latest that fails must each produce a line
# and not end the update. Driven untested, in its own process, for fact 15's
# reason — stricter than omakeb-update's own call site.
mkdir -p "$tmp/apps" "$tmp/state-t3/app-version"
cat > "$tmp/apps/fresh.sh" <<'APP'
app_name="Fresh"; app_tier=3
app_installed() { true; }
app_latest() { echo 1.0.0; }
APP
cat > "$tmp/apps/stale.sh" <<'APP'
app_name="Stale"; app_tier=3
app_installed() { true; }
app_latest() { echo 2.0.0; }
APP
cat > "$tmp/apps/offline.sh" <<'APP'
app_name="Offline"; app_tier=3
app_installed() { true; }
app_latest() { return 1; }
APP
cat > "$tmp/apps/selfup.sh" <<'APP'
app_name="Selfup"; app_tier=3; app_self_updating=1
app_installed() { true; }
APP
for id in fresh stale offline selfup vanished; do
  echo 1.0.0 > "$tmp/state-t3/app-version/$id"
done
out=$(OMAKEB_STATE="$tmp/state-t3" OMAKEB_APPS_DIR="$tmp/apps" bash -c '
  set -euo pipefail
  source lib/log.sh; source lib/state.sh; source lib/apps.sh
  tier3_report
  echo REACHED-THE-END' 2>&1); rc=$?
before=$fail
(( rc == 0 )) && grep -q REACHED-THE-END <<<"$out" || bad "tier3_report ended the calling script (rc=$rc)"
grep -q 'Fresh: 1.0.0 (current)' <<<"$out"            || bad "tier3_report did not call a current app current"
grep -q 'Stale: 1.0.0 installed, 2.0.0 available' <<<"$out" || bad "tier3_report did not report a stale app"
grep -q 'Offline: 1.0.0 (could not reach' <<<"$out"   || bad "tier3_report did not tolerate a failed upstream check"
grep -q 'Selfup: .*updates itself' <<<"$out"          || bad "tier3_report did not report a self-updating app as such"
grep -q 'vanished: 1.0.0 recorded' <<<"$out"          || bad "tier3_report did not handle a recorded app with no definition"
if (( fail == before )); then
  ok "tier3_report reports current, stale, offline, self-updating and vanished apps without aborting"
else
  sed 's/^/        /' <<<"$out"
fi

echo
if (( fail )); then
  echo "apps checks FAILED"
  exit 1
fi
echo "apps checks passed"
