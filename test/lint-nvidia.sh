#!/bin/bash
# Static checks for bin/omakeb-hw-nvidia.
#
# This is the only omakeb feature that cannot be tested on the hardware it
# targets — there is no NVIDIA card in the project. So the parts that CAN be
# checked without one are checked hard, because they are all we get:
#
#   * the generated hyprlang file must parse the way hyprlang parses. hyprlang
#     truncates every line at an unescaped '#', so a hash anywhere in a value
#     silently produces a different setting than the one that was written.
#   * GBM_BACKEND must stay out. It is in every second NVIDIA-on-Wayland
#     tutorial and is no longer in Hyprland's guidance; someone will try to
#     "fix" this file by adding it back.
#   * the block editors must round-trip exactly. They edit the user's own
#     ~/.config/omakeb/hyprland.conf, and corrupting that file is the same
#     black screen the command exists to prevent.
#   * every menu row that runs this command must be gated on an NVIDIA card
#     actually being present.
#
# What it does NOT check, and cannot: that the driver installs, that the module
# builds, that the machine boots afterwards.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
_mark=0
bad()   { echo "  FAIL: $*"; fail=1; }
ok()    { echo "  ok: $*"; }
mark()  { _mark=$fail; }
# Report a group as passing only if THIS group added no failures. A plain
# `(( fail )) || ok` swallows every later "ok" once anything has failed, which
# hides how much of the file is actually still good.
ok_if() { (( fail == _mark )) && ok "$*"; return 0; }

SCRIPT=bin/omakeb-hw-nvidia

[[ -x $SCRIPT ]] || { echo "  FAIL: $SCRIPT is missing or not executable"; exit 1; }

# --- load the file as a library ----------------------------------------------
export OMAKEB_HW_NVIDIA_LIB=1
export OMAKEB_PATH="$PWD"
# shellcheck source=/dev/null
source "$SCRIPT"
set +e +u
set -u

# --- 1. hyprlang: no unescaped '#' in anything that is not a comment ---------

check_hyprlang() {
  local label=$1 line trimmed n=0
  while IFS= read -r line; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ -z $trimmed ]] && continue
    [[ ${trimmed:0:1} == '#' ]] && continue
    n=$((n + 1))
    case "$trimmed" in
      *'#'*) bad "$label: unescaped '#' in a non-comment line: $trimmed" ;;
    esac
  done
  (( n > 0 )) || bad "$label: produced no directives at all"
}

mark
hypr_env_body          | check_hyprlang "hypr_env_body"
hypr_source_block_body | check_hyprlang "hypr_source_block_body"
ok_if "generated hyprlang files carry no unescaped hash in a value"

# --- 2. exactly the two variables Hyprland currently recommends --------------

envs=$(hypr_env_body | sed -n 's/^env = \([A-Za-z_][A-Za-z0-9_]*\),.*/\1/p' | sort)
expected=$(printf '%s\n' LIBVA_DRIVER_NAME __GLX_VENDOR_LIBRARY_NAME | sort)
if [[ $envs == "$expected" ]]; then
  ok "sets exactly LIBVA_DRIVER_NAME and __GLX_VENDOR_LIBRARY_NAME"
else
  bad "env list changed. got:
$envs
want:
$expected"
fi

# GBM_BACKEND and NVD_BACKEND may be MENTIONED in a comment (they are, with the
# reason) but must never be set.
mark
for v in GBM_BACKEND NVD_BACKEND WLR_NO_HARDWARE_CURSORS; do
  if hypr_env_body | grep -qE "^[[:space:]]*env[[:space:]]*=[[:space:]]*$v"; then
    bad "$v is set as an env; it is not in Hyprland's current guidance"
  fi
done
ok_if "GBM_BACKEND, NVD_BACKEND and WLR_NO_HARDWARE_CURSORS are not set"

# --- 3. modprobe options ------------------------------------------------------

mark
body=$(modprobe_body | grep '^options ')
grep -qE '^options nvidia_drm .*\bmodeset=1\b' <<<"$body" ||
  bad "modprobe body does not set modeset=1, which is the whole point"
grep -qE '^options nvidia_drm .*\bfbdev=1\b' <<<"$body" ||
  bad "modprobe body does not set fbdev=1 by default (trixie has 550, below 570.86.16)"

# When modinfo says the built module has no fbdev parameter, it must be dropped:
# an unknown parameter stops the module loading, which is a black screen.
body=$(modprobe_body "modeset nvidia_drm_load" | grep '^options ')
grep -q 'fbdev' <<<"$body" &&
  bad "fbdev=1 is still written when the module does not declare it"
grep -qE '^options nvidia_drm .*\bmodeset=1\b' <<<"$body" ||
  bad "modeset=1 was lost in the no-fbdev path"
ok_if "modprobe options: modeset always, fbdev only when the module declares it"

# --- 4. early KMS block lists the four modules --------------------------------

mark
# DKMS_MODULE_DIR pinned at an EMPTY directory, like every other early-KMS case
# in this file. Without it early_kms_modules() reads the host's real
# /lib/modules/$(uname -r)/updates/dkms, and this assertion — which is about the
# no-flavoured-build fallback to the documented nvidia_* names — silently
# becomes a test of whatever the host happens to have installed.
#
# The polarity was the worst available: it passed on any machine WITHOUT the
# NVIDIA driver (the development host, every CI container) and failed on a
# machine WITH it, which is the only kind this code runs on. It was green on
# macOS for the whole life of the file and red the first time the suite was run
# on the physical test box.
empty_kms=$(mktemp -d)
blk=$(OMAKEB_DKMS_DIR=$empty_kms DKMS_MODULE_DIR=$empty_kms initramfs_block_body)
rmdir "$empty_kms"
for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
  grep -qx "$m" <<<"$blk" || bad "early KMS block is missing module: $m"
done
grep -qi 'hibernat' <<<"$blk" ||
  bad "early KMS block does not warn about resume from hibernation"
ok_if "early KMS block lists the four modules and warns about hibernation"

# --- 4b. desktop vs laptop, which decides the hybrid refusal ------------------
#
# The refusal used to fire on "an Intel display controller exists", which is
# true of nearly every desktop with an NVIDIA card in it — the iGPU is enabled
# in BIOS and nothing is plugged into it. That sent people with a perfectly
# ordinary tower to a PRIME wiki page for a problem they did not have.
#
# The rule is now about whether the NVIDIA GPU can drive the display itself, so
# it has four outcomes and each one has to be pinned down. Driven from fixture
# sysfs trees via OMAKEB_SYSFS_ROOT, because the machine running the tests is
# only ever one of these shapes.

topo_root=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$topo_root"' EXIT

# build_sysfs <dir> <pci vendor list> <connected connectors as card:vendor:status,...>
build_sysfs() {
  local root=$1 vendors=$2 conns=$3 portable=$4
  local i=0 v c card cvendor status
  rm -rf "$root"; mkdir -p "$root/sys/bus/pci/devices" "$root/sys/class/drm" "$root/sys/class/dmi/id"

  for v in $vendors; do
    mkdir -p "$root/sys/bus/pci/devices/0000:00:0$i.0"
    printf '%s\n' "$v"     > "$root/sys/bus/pci/devices/0000:00:0$i.0/vendor"
    printf '0x030000\n'    > "$root/sys/bus/pci/devices/0000:00:0$i.0/class"
    i=$((i + 1))
  done

  for c in $conns; do
    card=${c%%:*}; cvendor=$(echo "$c" | cut -d: -f2); status=$(echo "$c" | cut -d: -f3)
    mkdir -p "$root/sys/class/drm/$card/device" "$root/sys/class/drm/$card-DP-1"
    printf '%s\n' "$cvendor" > "$root/sys/class/drm/$card/device/vendor"
    printf '%s\n' "$status"  > "$root/sys/class/drm/$card-DP-1/status"
  done

  # 3 is Desktop, 10 is Notebook
  if [[ $portable == yes ]]; then
    printf '10\n' > "$root/sys/class/dmi/id/chassis_type"
    mkdir -p "$root/sys/class/power_supply/BAT0"
  else
    printf '3\n' > "$root/sys/class/dmi/id/chassis_type"
  fi
}

topo() { OMAKEB_SYSFS_ROOT=$topo_root SYSFS=$topo_root graphics_topology; }
expect_topo() {
  local want=$1 got
  got=$(topo)
  [[ $got == "$want" ]] || bad "topology: expected '$want', got '$got' ($2)"
  [[ $got == "$want" ]] && ok "$2 -> $want"
}

# The test machine's own shape: MSI tower, Intel iGPU enabled, monitor in the 3080.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:disconnected card1:0x10de:connected" no
expect_topo discrete "desktop, iGPU present, display on the NVIDIA card"

# The same tower with the monitor moved to the motherboard output. `offload`
# needs the OTHER GPU to actually hold a connected output.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:connected card1:0x10de:disconnected" no
expect_topo offload "desktop, iGPU present, display on the integrated output"

# Nothing connected anywhere. This is NOT offload: it is what a freshly
# installed driver with modeset still off looks like, and reading it as offload
# made `enable` refuse to finish the job it had already started — observed on
# the test machine between the first enable and its reboot.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:disconnected card1:0x10de:disconnected" no
expect_topo unknown "desktop, two controllers, no connected output visible on either"

# And with no connectors in sysfs at all, which is the same situation.
build_sysfs "$topo_root" "0x8086 0x10de" "" no
expect_topo unknown "desktop, two controllers, no connectors enumerated at all"

# A real Optimus laptop: battery and a notebook chassis, panel on the iGPU.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:connected card1:0x10de:disconnected" yes
expect_topo optimus "laptop with hybrid graphics"

# An Optimus laptop with an external monitor on the dGPU's own HDMI. The
# internal panel is still on the iGPU, so this is Optimus regardless of what is
# plugged in — the chassis has to win over the connector.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:connected card1:0x10de:connected" yes
expect_topo optimus "laptop with an external monitor on the NVIDIA card"

# NVIDIA on its own.
build_sysfs "$topo_root" "0x10de" "card0:0x10de:connected" no
expect_topo single "desktop with only an NVIDIA display controller"

# AMD integrated alongside NVIDIA, on a desktop, display on the NVIDIA card.
build_sysfs "$topo_root" "0x1002 0x10de" "card0:0x1002:disconnected card1:0x10de:connected" no
expect_topo discrete "desktop with AMD integrated graphics and the display on NVIDIA"

# A laptop whose battery has been removed still reads as portable from DMI.
build_sysfs "$topo_root" "0x8086 0x10de" "card0:0x8086:connected card1:0x10de:disconnected" yes
rm -rf "$topo_root/sys/class/power_supply"
expect_topo optimus "laptop with the battery removed (DMI chassis still says notebook)"

# --- 4c. the Secure Boot verdict carries its evidence -------------------------
#
# secure_boot_state used to echo its answer, and both callers read it with
# `sb=$(secure_boot_state)`. That subshell threw away every SB_REASON the
# function set, so the evidence printed blank — including inside the refusal
# that fires when Secure Boot is ENABLED, where a bare "Secure Boot is enabled."
# with no reason is the least useful possible thing to tell someone.
#
# Runs anywhere: with no mokutil and no /sys/firmware/efi (macOS, a container)
# the function still reaches a determination and still has to explain it.
before=$fail
SB_REASON=; SB_STATE=
secure_boot_state
[[ -n $SB_STATE ]]  || bad "secure_boot_state set no SB_STATE"
[[ -n $SB_REASON ]] || bad "secure_boot_state reached '$SB_STATE' but left SB_REASON empty"
case "$SB_STATE" in
  enabled | disabled | unknown) ;;
  *) bad "secure_boot_state returned an unexpected state: '$SB_STATE'" ;;
esac
grep -q 'sb=$(secure_boot_state)' "$SCRIPT" &&
  bad "a caller reads secure_boot_state in a command substitution again; SB_REASON will be empty"
(( fail == before )) && ok "Secure Boot verdict '$SB_STATE' arrives with its evidence attached"

# --- 4d. the two probes that lie on Debian ------------------------------------
#
# Both of these were found only by running the command on a real NVIDIA machine,
# and both failed in the direction that hides a problem rather than inventing
# one, which is why nothing noticed for so long.

before=$fail
# `grep -r` does not follow symlinks met while recursing. Debian's nouveau
# blacklist is /etc/modprobe.d/nvidia-blacklists-nouveau.conf -> /etc/alternatives/...,
# so with -r this probe reported "nothing blacklists nouveau" on the one
# distribution the command targets — silencing the warning that a failed module
# build is now a black screen rather than a slow desktop.
grep -q 'grep -RlsE' "$SCRIPT" ||
  bad "nouveau_blacklisted_by uses grep -r; it cannot see Debian's symlinked blacklist"
grep -q 'grep -rlsE' "$SCRIPT" &&
  bad "nouveau_blacklisted_by still has a symlink-blind grep -r"
(( fail == before )) && ok "nouveau blacklist probe follows symlinks (grep -R)"

before=$fail
# Debian builds nvidia-current-drm, not nvidia_drm. `modinfo nvidia_drm` finds
# nothing on a machine where the build succeeded, which the command reported as
# "the DKMS build probably failed" and used to skip the early KMS it had just
# said it would set up.
grep -q '^nvidia_drm_module() {' "$SCRIPT" ||
  bad "no nvidia_drm_module(); the DRM module name is being assumed again"
sed -n '/^nvidia_drm_params() {/,/^}/p' "$SCRIPT" | grep -q 'nvidia_drm_module' ||
  bad "nvidia_drm_params does not resolve the module name; it will miss Debian's flavoured build"
sed -n '/^nvidia_drm_params() {/,/^}/p' "$SCRIPT" | grep -qE '"\$mi" nvidia_drm ' &&
  bad "nvidia_drm_params still calls modinfo on the hardcoded name nvidia_drm"
sed -n '/^nvidia_drm_module() {/,/^}/p' "$SCRIPT" | grep -q "nvidia\*drm.ko" ||
  bad "nvidia_drm_module does not fall back to the built module file"
(( fail == before )) && ok "DRM module is resolved by name or by built file, not assumed"

# --- 4e. early KMS names the files that exist ---------------------------------
#
# initramfs-tools resolves each name in /etc/initramfs-tools/modules to a file
# and does not follow modprobe `install` rules, so the documented nvidia_* names
# put nothing in the image on Debian — silently, with update-initramfs still
# reporting success.

kms_dir=$(mktemp -d)
mk_mods() { rm -rf "$kms_dir"; mkdir -p "$kms_dir"; local f; for f in "$@"; do : > "$kms_dir/$f"; done; }
kms() { OMAKEB_DKMS_DIR=$kms_dir DKMS_MODULE_DIR=$kms_dir early_kms_modules; }

before=$fail
# Debian's default flavour, exactly as found on the test machine.
mk_mods nvidia-current.ko.xz nvidia-current-modeset.ko.xz nvidia-current-uvm.ko.xz \
        nvidia-current-drm.ko.xz nvidia-current-peermem.ko.xz
got=$(kms)
[[ $got == "nvidia-current nvidia-current-modeset nvidia-current-uvm nvidia-current-drm" ]] ||
  bad "flavoured build: expected the four nvidia-current modules in dependency order, got '$got'"
case "$got" in *peermem*) bad "peermem is not needed for early KMS and should not be listed" ;; esac
(( fail == before )) && ok "early KMS names Debian's built files, base first then modeset/uvm/drm"

before=$fail
# Debian's legacy flavour.
mk_mods nvidia-tesla-470.ko.xz nvidia-tesla-470-modeset.ko.xz nvidia-tesla-470-uvm.ko.xz \
        nvidia-tesla-470-drm.ko.xz
got=$(kms)
[[ $got == "nvidia-tesla-470 nvidia-tesla-470-modeset nvidia-tesla-470-uvm nvidia-tesla-470-drm" ]] ||
  bad "legacy flavour: got '$got'"
(( fail == before )) && ok "early KMS follows the driver flavour rather than assuming one"

before=$fail
# Nothing built, or another distribution's layout: fall back to the documented
# names, which is what this always used to write unconditionally.
mk_mods
got=$(kms)
[[ $got == "nvidia nvidia_modeset nvidia_uvm nvidia_drm" ]] ||
  bad "no built modules: expected the documented fallback names, got '$got'"
(( fail == before )) && ok "with no flavoured build, falls back to the documented nvidia_* names"

before=$fail
# A build missing uvm must not name a file that is not there.
mk_mods nvidia-current.ko.xz nvidia-current-drm.ko.xz
got=$(kms)
[[ $got == "nvidia-current nvidia-current-drm" ]] ||
  bad "partial build: expected only what exists, got '$got'"
(( fail == before )) && ok "only modules that were actually built are listed"

# --- 4f. the options must reach the module however it is loaded ---------------
#
# An `options` line is keyed on the name the module is REQUESTED by. Debian
# reaches nvidia-current-drm.ko from the name nvidia_drm through an `install`
# rule, which udev's load-by-alias goes through and a direct load does not.
#
# Early KMS is a direct load — /etc/initramfs-tools/modules must name the built
# files for initramfs-tools to find them — so a file carrying only
# `options nvidia_drm modeset=1` boots to modeset=N, no DRM connectors and a
# compositor with no usable device. That was observed on the test machine, and
# it was caused by fixing early KMS, so the two have to stay tested together.
before=$fail
mk_mods nvidia-current.ko.xz nvidia-current-modeset.ko.xz nvidia-current-drm.ko.xz
body=$(OMAKEB_DKMS_DIR=$kms_dir DKMS_MODULE_DIR=$kms_dir modprobe_body "modeset fbdev")
grep -q '^options nvidia_drm modeset=1 fbdev=1$' <<<"$body" ||
  bad "modprobe body lost the documented alias line"
grep -q '^options nvidia-current-drm modeset=1 fbdev=1$' <<<"$body" ||
  bad "modprobe body has no options line for the name early KMS loads (nvidia-current-drm)"
# Every name early KMS lists that takes these options must be covered.
for m in $(OMAKEB_DKMS_DIR=$kms_dir DKMS_MODULE_DIR=$kms_dir early_kms_modules); do
  case "$m" in
    *-drm)
      grep -q "^options $m " <<<"$body" ||
        bad "early KMS loads '$m' but no options line names it"
      ;;
  esac
done
(( fail == before )) && ok "modprobe options are written for both the alias and the real module name"

before=$fail
# Where the documented name IS the real one, do not write the same line twice.
mk_mods nvidia.ko nvidia_drm.ko
body=$(OMAKEB_DKMS_DIR=$kms_dir DKMS_MODULE_DIR=$kms_dir modprobe_body "modeset fbdev")
[[ $(grep -c '^options ' <<<"$body") == 1 ]] ||
  bad "duplicate options lines when the real module name is already nvidia_drm"
(( fail == before )) && ok "no duplicate options line when the documented name is the real one"

# --- 5. the block editors round-trip exactly ----------------------------------
#
# This is the check that matters most: block_set/block_clear are let loose on a
# file the user wrote.

tmpdir=$(mktemp -d)
f=$tmpdir/hyprland.conf

cat > "$f" <<'USERCONF'
# The user's own file.
input {
    kb_layout = us,no
}

# A line that merely mentions omakeb-hw-nvidia in passing.
monitor = eDP-1, preferred, 0x0, 1
USERCONF
before=$(cat "$f")

hypr_source_block_body | block_set "$f" user >/dev/null 2>&1
grep -qF "source = $HYPR_ENV_FILE" "$f" || bad "block_set did not add the source line"
grep -qF 'kb_layout = us,no' "$f" || bad "block_set destroyed the user's content"

hypr_source_block_body | block_set "$f" user >/dev/null 2>&1
n=$(grep -cF '>>> omakeb-hw-nvidia >>>' "$f")
[[ $n == 1 ]] || bad "block_set is not idempotent: $n marker blocks after two runs"

block_clear "$f" user >/dev/null 2>&1
after=$(cat "$f")
if [[ $before == "$after" ]]; then
  ok "block_set then block_clear round-trips the user's file byte for byte"
else
  bad "block_clear did not restore the file. diff:
$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
fi

# A file with no block at all must come back untouched.
block_clear "$f" user >/dev/null 2>&1
[[ "$(cat "$f")" == "$before" ]] || bad "block_clear altered a file that had no block"

# --- 6. nvidia-detect parsing -------------------------------------------------
#
# Fed the two shapes of output that matter. There is no NVIDIA card here, so
# nvidia-detect is shimmed.

detect_case() {
  local label=$1 want=$2 out
  out=$(nvidia_detect_packages | tr '\n' ' ')
  out=${out% }
  if [[ $out == "$want" ]]; then
    ok "nvidia-detect parsing, $label -> '${out:-<nothing>}'"
  else
    bad "nvidia-detect parsing, $label: got '$out', want '$want'"
  fi
}

nvidia-detect() { cat <<'OUT'
Detected NVIDIA GPUs:
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [10de:1c03] (rev a1)

Checking card:  NVIDIA Corporation GP106 (rev a1)
Your card is supported by all driver versions.
It is recommended to install the
    nvidia-driver
package.
OUT
}
detect_case "current card" "nvidia-driver"

nvidia-detect() { cat <<'OUT'
Checking card:  NVIDIA Corporation GK208B (rev a1)
Your card is only supported up to the 470 legacy drivers series.
It is recommended to install the
    nvidia-tesla-470-driver
package.
OUT
}
detect_case "legacy card" "nvidia-tesla-470-driver"

nvidia-detect() { cat <<'OUT'
Checking card:  NVIDIA Corporation G92 (rev a2)
Your card is only supported up to the 340 legacy drivers series, which is no
longer available in Debian.
OUT
}
detect_case "unsupported card (must name nothing, not guess)" ""
unset -f nvidia-detect

# --- 7. the menu row is gated on the hardware ---------------------------------

mark
rows=$(grep -n 'omakeb-hw-nvidia' menu/menu.jsonc || true)
if [[ -z $rows ]]; then
  bad "menu/menu.jsonc has no omakeb-hw-nvidia row"
else
  parent=$(grep -n '"setup.nvidia":' menu/menu.jsonc || true)
  [[ -n $parent ]] || bad 'menu/menu.jsonc has no "setup.nvidia" submenu'
  grep -q '"setup.nvidia":.*"when":.*0x10de' menu/menu.jsonc ||
    bad '"setup.nvidia" is not gated on a "when" testing PCI vendor 0x10de'
  # Every leaf must live under that gated parent.
  while IFS= read -r line; do
    case "$line" in
      *'"setup.nvidia.'*) ;;
      *) bad "an omakeb-hw-nvidia menu row is outside the gated setup.nvidia branch: $line" ;;
    esac
  done < <(grep 'omakeb-hw-nvidia' menu/menu.jsonc)
  ok_if "menu rows for omakeb-hw-nvidia are gated on an NVIDIA card being present"
fi

# --- 8. the installer offers it, but never enables it unattended ---------------

# The installer MAY notice an NVIDIA card and offer the setup — that is
# install/35-nvidia.sh, and offering is better than leaving the feature
# undiscovered. What it must never do is enable anything without an answer from
# the user. So the rule is not "no reference" but "no unattended enable":
#   * never pass --yes, which is the non-interactive override (comment lines are
#     skipped — the step's own comment explains why it does NOT pass it, and
#     matching that would be a false positive)
#   * only run it behind a terminal test, so a scripted install cannot be walked
#     into a proprietary driver by something answering prompts blindly
refs=$(grep -rl 'omakeb-hw-nvidia' install/ boot.sh install.sh 2>/dev/null || true)
if [[ -z $refs ]]; then
  ok "not referenced from the installer at all"
elif grep -rhn 'omakeb-hw-nvidia' $refs | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q -- '--yes'; then
  bad "the installer runs omakeb-hw-nvidia with --yes; enabling must require a real answer"
elif ! grep -rq -- '-t 0' $refs; then
  bad "the installer calls omakeb-hw-nvidia without a terminal guard"
else
  ok "installer offers NVIDIA setup interactively only, never with --yes"
fi

# --- 9. enable and revert invalidate the cached GL mode -----------------------
#
# omakeb-gl-fallback caches "this GPU needs software OpenGL". A first login on
# nouveau measures exactly that, and before this the answer outlived `enable`:
# a working NVIDIA card left on llvmpipe, with nothing saying so. Both commands
# change the GL stack, so both must drop the answer on their success path.

before=$fail
for fn in cmd_enable cmd_revert; do
  sed -n "/^$fn() {/,/^}/p" "$SCRIPT" | grep -qE '^[[:space:]]+gl_mode_cache_clear$' ||
    bad "$fn does not call gl_mode_cache_clear; the GL-mode cache survives the driver change"
done
# The two files must agree on where the cache lives, or the clear is a no-op.
grep -q '^mode_file=\$OMAKEB_STATE/gl-mode$' bin/omakeb-gl-fallback ||
  bad "omakeb-gl-fallback no longer keeps its cache at \$OMAKEB_STATE/gl-mode"
grep -q '^GL_MODE_FILE="\$OMAKEB_STATE/gl-mode"$' "$SCRIPT" ||
  bad "omakeb-hw-nvidia clears a different path from the one omakeb-gl-fallback caches in"

# Pinned at a fixture: GL_MODE_FILE was computed from the HOST's $OMAKEB_STATE
# when the script was sourced, and this must not delete the real one (fact 35).
gl_tmp=$(mktemp -d)
GL_MODE_FILE=$gl_tmp/gl-mode
printf 'software\nkernel=x drm=nouveau\n' > "$GL_MODE_FILE"
gl_mode_cache_clear >/dev/null 2>&1 || bad "gl_mode_cache_clear failed with a cache present"
[[ -e $GL_MODE_FILE ]] && bad "gl_mode_cache_clear left the cache in place"
gl_mode_cache_clear >/dev/null 2>&1 || bad "gl_mode_cache_clear fails when there is no cache (revert run twice)"
rm -rf "$gl_tmp"
(( fail == before )) && ok "enable and revert both clear the cached GL mode, so the next login re-probes"

echo
if (( fail )); then
  echo "nvidia checks FAILED"
  exit 1
fi
echo "nvidia checks passed"
