# Testing omakeb

Three tiers, fastest first. Run the cheap ones constantly; the expensive one
only when the cheap ones pass.

## Tier 0 — static, on any host (seconds)

```sh
./test/run-all.sh
```

Runs on macOS. No Debian, apt or compositor needed. Checks shell syntax,
Hyprland bind flags/arity/duplicate chords, D9 architecture assumptions, and the
binding-reference ratchet.

**Run it on Debian too, before believing a green result.** macOS ships bash 3.2
and the target ships 5.2, and they differ on errexit in ways that make a check
about shell semantics pass on the development host with its bug present. Separately, a check that reads the host by omission can be
green on a machine lacking the hardware it is about and red on one that has it —
which is how `lint-nvidia.sh` was green on macOS for its whole life and failed
the first time it ran on the physical box (fact 35).

```sh
tar czf - --exclude .git . | ssh user@testbox \
  'rm -rf /tmp/omakeb-check && mkdir -p /tmp/omakeb-check && tar xzf - -C /tmp/omakeb-check'
ssh user@testbox 'cd /tmp/omakeb-check && ./test/run-all.sh'
```

It touches nothing outside `/tmp`, so it is safe to run against a configured
machine.

## Package names — ask a real apt (one second)

```sh
./test/vm/verify-packages.sh user@testbox
```

Asks that machine's apt whether every name in `packages/*.list` resolves for its
architecture. Reads only, needs no sudo, changes nothing.

Run it whenever a package name is added. The reason it
exists: `packages.debian.org/trixie/<pkg>` returns **200 with a "no such
package" page**, so checking a name in a browser confirms nothing. That is how
`greetd-tuigreet`, which does not exist, got into a package list. Only apt
knows.

`install/10-sources.sh` catches a bad name too, via `require_packages` — but on
someone's machine, at the point where their install stops.

## Tier 1 — container install, inside a Debian VM (about a minute)

```sh
sudo apt install mmdebstrap systemd-container
./test/vm/nspawn-install.sh
```

Builds a throwaway Debian 13 rootfs with `mmdebstrap`, runs the real
`install.sh` in it under `systemd-nspawn`, then asserts. Every run starts from a
genuinely clean system and cannot leave the VM half-configured, so this is where
almost all iteration should happen.

What it proves:

- preflight accepts a real Debian 13
- the backports source and pin are written correctly
- **hyprland resolves from backports and waybar does not** — i.e. the pin is
  doing its job in both directions, which is the single most important thing to
  get right
- every package in all three lists resolves **for the running architecture** (D9)
- the portal preference file lands
- **a second run rewrites nothing** — the idempotency property that makes
  `install.sh` usable as a repair tool

What it cannot prove: anything involving a GPU, a display manager, or a running
compositor. That is Tier 2.

Useful overrides: `ROOT=` (rootfs path), `SUITE=`, `MIRROR=` (a local mirror or
`apt-cacher-ng` makes repeat runs much faster), `TESTUSER=`.

## Tier 2 — real VM session (manual, minutes)

Only this tier can test the parts that matter to a user's hands. Snapshot the VM
first; a failed greetd leaves you at a black screen.

1. Snapshot the VM.
2. Run `install.sh` on the VM itself, not in a container.
3. Reboot.
4. Check, in order — each depends on the previous:
   - [ ] greetd shows a tuigreet prompt (if not: `journalctl -b -u greetd`)
   - [ ] logging in starts Hyprland under uwsm
     (`systemctl --user status wayland-wm@Hyprland.service`)
   - [ ] `hyprctl version` responds
   - [ ] `hyprctl binds -j | jq length` reports ~142 — this is the first proof
         the binding files actually parse. Hyprland skips a malformed bind and
         logs it rather than failing to start, so a lower number means a silently
         dropped binding: check `hyprctl configerrors`.
   - [ ] waybar, mako and hyprpaper are running
   - [ ] SUPER+SPACE, SUPER+RETURN, SUPER+K respond
   - [ ] media keys work, including while locked (that is what the `l` flag buys)
   - [ ] a screenshare picker appears in a browser (proves the portal config)

### Why arm64 is the better VM here

The Hyprland stack is built for eight of Debian 13's nine release architectures.
On an Apple Silicon host, an arm64 VM runs under native virtualization while an
amd64 one must be emulated — so arm64 is both faster *and* the more valuable
test, because it exercises the non-x86 path where D9 bugs would hide.

Testing on amd64 as well is worthwhile before any release, but it is not the
right place to iterate.
