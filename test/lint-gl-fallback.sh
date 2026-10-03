#!/bin/bash
# Behavioural checks for bin/omakeb-gl-fallback's cache.
#
# The probe itself cannot run here — it is "start the real terminal and see",
# and that needs a compositor and a GPU. What CAN be checked is the decision
# around it: when a cached answer is trusted and when it is thrown away. That
# decision used to be "trust it forever", which kept a machine on llvmpipe after
# it gained a working GPU and said nothing. So:
#
#   * a cache recorded on this GPU stack is used, and the probe does not run
#   * a cache recorded on a different kernel, or different DRM drivers, is not
#   * a one-line cache from before the fingerprint existed is re-probed
#   * the fingerprint does not depend on card numbering or connector nodes
#
# kitty, timeout and uname are stubbed, and /sys/class/drm is a fixture tree
# (OMAKEB_SYSFS_DRM), so this runs on macOS like the rest of run-all.sh.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() { echo "  FAIL: $*"; fail=$((fail + 1)); }
ok()  { echo "  ok: $*"; }

SCRIPT=bin/omakeb-gl-fallback
[[ -r $SCRIPT ]] || { echo "  FAIL: $SCRIPT is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- stubs --------------------------------------------------------------------
#
# The fake kitty records that the probe ran, and fails without software GL when
# $HW_FAILS is set — a VM without 3D acceleration. The fake hyprctl records that
# software rendering was applied.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/kitty" <<'STUB'
#!/bin/bash
echo "probe LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-}" >> "$CALLS"
[[ -n ${HW_FAILS:-} && -z ${LIBGL_ALWAYS_SOFTWARE:-} ]] && exit 1
exit 0
STUB
cat > "$tmp/bin/timeout" <<'STUB'
#!/bin/bash
shift; exec "$@"
STUB
cat > "$tmp/bin/uname" <<'STUB'
#!/bin/bash
echo "$FAKE_KERNEL"
STUB
cat > "$tmp/bin/hyprctl" <<'STUB'
#!/bin/bash
echo "hyprctl $*" >> "$CALLS"
STUB
for s in systemctl notify-send; do printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/$s"; done
chmod +x "$tmp/bin/"*

# --- fixture sysfs ------------------------------------------------------------
drm=$tmp/sys/class/drm
# set_cards <driver for card0> [<driver for card1> ...]
# Each card gets a connector node beside it, as the real tree has, so a
# fingerprint that forgot to skip them would show up here.
set_cards() {
  local i=0 d
  rm -rf "$tmp/sys"; mkdir -p "$drm"
  for d in "$@"; do
    mkdir -p "$drm/card$i/device" "$drm/card$i-DP-1"
    ln -s "../../../../bus/pci/drivers/$d" "$drm/card$i/device/driver"
    i=$((i + 1))
  done
}

# --- runner -------------------------------------------------------------------
#
# A separate shell under errexit/nounset/pipefail, as Hyprland's exec-once runs
# it — never `if ( set -e; ... )`, which suspends errexit inside the test.
KERNEL=6.12.48+deb13-amd64
run() {
  : > "$tmp/calls"
  CALLS=$tmp/calls FAKE_KERNEL=$KERNEL HW_FAILS=${HW_FAILS:-} \
  OMAKEB_PATH="$PWD" OMAKEB_STATE=$tmp/state OMAKEB_CONFIG=$tmp/config \
  OMAKEB_CACHE=$tmp/cache OMAKEB_SYSFS_DRM=$drm TERMINAL=kitty \
  PATH="$tmp/bin:$PATH" \
    bash -c 'set -euo pipefail; exec "$0"' "$PWD/$SCRIPT" >/dev/null 2>&1
}
mode_file=$tmp/state/gl-mode
probed()   { grep -q '^probe' "$tmp/calls"; }
softened() { grep -q '^hyprctl keyword env LIBGL_ALWAYS_SOFTWARE' "$tmp/calls"; }
cache_mode()  { sed -n 1p "$mode_file" 2>/dev/null; }
cache_print() { sed -n 2p "$mode_file" 2>/dev/null; }

# --- 1. first login: probes and records what it measured on -------------------
before=$fail
set_cards virtio_gpu; rm -rf "$tmp/state"
run || bad "exited non-zero on a first login"
probed || bad "did not probe with no cache"
[[ $(cache_mode) == hardware ]] || bad "cache mode: got '$(cache_mode)', want hardware"
[[ $(cache_print) == "kernel=$KERNEL drm=virtio_gpu" ]] ||
  bad "fingerprint: got '$(cache_print)', want 'kernel=$KERNEL drm=virtio_gpu'"
(( fail == before )) && ok "no cache: probes, and records the mode with the kernel and DRM driver"

# --- 2. same stack: the cache is trusted --------------------------------------
before=$fail
run || bad "exited non-zero on a cached login"
probed && bad "probed again although nothing about the GPU stack changed"
(( fail == before )) && ok "same kernel and drivers: cached answer used, no probe"

# --- 3. software cached on the same stack: applied without probing -------------
before=$fail
printf 'software\n%s\n' "$(cache_print)" > "$mode_file"
run || bad "exited non-zero with software cached"
probed && bad "probed although a matching software answer was cached"
softened || bad "a matching cached 'software' did not apply LIBGL_ALWAYS_SOFTWARE"
(( fail == before )) && ok "cached software on the same stack is applied without a probe"

# --- 4. the bug: nouveau measured software, then the NVIDIA driver arrived ----
before=$fail
set_cards nouveau; rm -rf "$tmp/state"
HW_FAILS=1 run || bad "exited non-zero on the software path"
[[ $(cache_mode) == software ]] || bad "nouveau fixture: want software cached, got '$(cache_mode)'"
set_cards nvidia
run || bad "exited non-zero after the driver changed"
probed || bad "did not re-probe after the DRM driver changed from nouveau to nvidia"
softened && bad "still forced llvmpipe after the GPU gained a working driver"
[[ $(cache_mode) == hardware ]] || bad "after re-probe: want hardware, got '$(cache_mode)'"
(( fail == before )) && ok "DRM driver changed (nouveau -> nvidia): stale 'software' is re-probed, not applied"

# --- 5. a kernel upgrade invalidates it too -----------------------------------
before=$fail
run; probed && bad "control: probed with nothing changed"
KERNEL=6.12.57+deb13-amd64 run || bad "exited non-zero after a kernel change"
probed || bad "did not re-probe after the kernel release changed"
(( fail == before )) && ok "kernel release changed: re-probed"

# --- 6. an old one-word cache is stale, not trusted and not fatal -------------
before=$fail
set_cards virtio_gpu
mkdir -p "$tmp/state"; printf 'software\n' > "$mode_file"
run || bad "exited non-zero on a pre-fingerprint cache file"
probed || bad "trusted a one-line cache file written before the fingerprint existed"
softened && bad "applied software from a pre-fingerprint cache whose probe now says hardware"
[[ -n $(cache_print) ]] || bad "did not rewrite the old cache in the new format"
(( fail == before )) && ok "old one-line cache file is treated as stale and rewritten"

# --- 7. fingerprint is about drivers, not card numbering ----------------------
before=$fail
set_cards nvidia i915 nvidia; rm -rf "$tmp/state"
run; a=$(cache_print)
set_cards i915 nvidia
run
probed && bad "re-probed when only card numbering changed"
[[ $a == "kernel=$KERNEL drm=i915,nvidia" ]] || bad "multi-card fingerprint: got '$a'"
(( fail == before )) && ok "several cards: sorted, de-duplicated driver set; connector nodes ignored"

# --- 8. no DRM devices at all -------------------------------------------------
before=$fail
rm -rf "$tmp/sys"; mkdir -p "$drm"; rm -rf "$tmp/state"
run || bad "exited non-zero with no DRM cards (an unmatched glob under set -u)"
[[ $(cache_print) == "kernel=$KERNEL drm=" ]] || bad "no cards: got '$(cache_print)'"
run; probed && bad "no cards: re-probed although nothing changed"
(( fail == before )) && ok "no DRM cards: still works, and still caches"

echo
if (( fail )); then
  echo "gl fallback checks FAILED ($fail)"
  exit 1
fi
echo "gl fallback checks passed"
