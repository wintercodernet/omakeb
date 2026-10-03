# Palette test corpus

`colors.toml` files **only**, a few hundred bytes each. No images, no per-app
files, no rendered output. This is the one vendoring exception D11 endorses,
and it stops here for a reason: 95% of an upstream `themes/` directory is
background artwork with no attribution, and MIT conveys the rights the licensor
holds — it cannot convey rights to third-party images.

## Why the corpus exists

The palette format is defined by a pre-release upstream (`4.0.0.alpha`) that
has rewritten its theme system twice in a year, and the community ecosystem
ships **three generations of the format at once**. An adapter that implements
only the canonical keys renders roughly a third of that ecosystem black on
black. `test/lint-theme.py` resolves every file here and asserts that the whole
token vocabulary comes out non-empty, so a format change is caught by a test
run rather than by a user with an unreadable desktop.

Each file is loaded as data. Nothing here is executed, rendered into `~`, or
redistributed by omakeb at run time.

## Provenance

| file | generation | source | licence |
|---|---|---|---|
| `gen3-canonical-rose-pine-moon.colors.toml` | 3, canonical semantic keys | `Memnoc/omarchy-rose-pine-moon-theme` @ `main` | MIT, © 2026 Memnoc |
| `gen3-ansi-tokyo-night.colors.toml` | 3, ANSI-shaped keys | `basecamp/omarchy` @ `master`, `themes/tokyo-night/` | MIT, © David Heinemeier Hansson |
| `gen2-transitional-oxocarbon.colors.toml` | 2, `colors.toml` alongside the full legacy per-app set | `HANCORE-linux/omarchy-oxocarbon-theme` @ `main` | MIT, © 2026 HANCORE |
| `gen1-alacritty.toml` | 1, no `colors.toml` at all | **synthetic** — written for omakeb | n/a |
| `gen2-legacy-short.colors.toml` | 2, legacy short + ANSI + invented keys | **synthetic** — written for omakeb | n/a |
| `gen3-sparse.colors.toml` | 3, four declared keys | **synthetic** — written for omakeb | n/a |
| `gen3-light.colors.toml` | 3, light with no `mode` | **synthetic** — written for omakeb | n/a |

The three vendored files are reproduced under the MIT licence, whose text
requires the copyright notice and permission notice above to be retained; the
full text is in `LICENSE.upstream` next to this file.

Four fixtures are synthetic and say so in their own header comment. Two of them
(generation 1, and the legacy-short spelling) had no still-published example
carrying a licence, and the other two are floor cases that no real theme would
bother to be. They reproduce the *shape* the parser has to survive, which is
the thing under test.

## Refreshing

Re-clone upstream and diff `docs/theming.md` when cutting a release.
If a fixture's upstream file has changed, replace it and re-run
`./test/run-all.sh` — a diff in the resolved output is the signal that the
format moved.
