# W3C SVG 1.1 Second Edition compliance harness

Renders the official W3C SVG 1.1 SE test suite (2011-08-16 archive, the
final SVG 1.1 release) with the `graphics:svg` CLI and pixel-compares every
rendering against the suite's reference image. This is the *measurement
device* for the SVG feature roadmap: every test's differing-pixel count is
tracked against a committed baseline, and the numbers are ratcheted down as
features land.

## Setup

```sh
dub build graphics:svg --config=cli --compiler=gdc   # -> svg/svg-test-application
tests/w3c/fetch.sh                                   # pinned download -> suite/ (gitignored)
tests/w3c/run.sh                                     # render all + compare + CI gate
tests/w3c/run.sh --update                            # rebase status.txt after engine changes
tests/w3c/run.sh shapes-rect*                        # subset run for triage
```

## Layout

| file                | role                                                            |
| ------------------- | --------------------------------------------------------------- |
| `fetch.sh`          | sha256-pinned download; unpacks the archive into `suite/`, gunzips the single `.svgz` |
| `run.sh`            | renders all 526 tests (10 s timeout each, `nproc` wide), `magick compare -metric AE -fuzz 10%`, verdicts, gate |
| `status.txt`        | committed baseline: `NAME.svg <OK\|ERROR> <AE>`                  |
| `suite/`, `out/`    | downloaded suite / renderings, diff + stderr artifacts — all gitignored |

## Nothing is excluded

All 526 tests are rendered, including `animate-*`, `interact-*`,
`script-*` and `*-dom-*`: the renderer ignores SMIL and scripting, so every
test has a deterministic static-frame rendering with a meaningful AE number
against the reference (the suite ships reference PNGs for animation tests
too — they show timeline states, so their absolute verdict hardly matters,
but their AE trend over time does, and once animation support lands the
same numbers become conformance targets). No tier manifests, no curation:
the per-test numbers in `status.txt` are the source of truth.

## Categories

For the summary table, a test's category is simply the first two hyphen-
separated segments of its name (`masking-path-01-b.svg` → `masking-path`,
`coords-trans-01-b.svg` → `coords-trans`, ~100 categories). Display only —
no gating input, nothing to maintain.

## Verdicts and the AE number

- `ERROR` — the renderer crashed / timed out / produced no image, or the
  compare failed; AE is `-`, the engine's stderr goes to `out/NAME.err`.
- `OK` — rendered and compared; AE (`-fuzz 10 %`, channel-weighted,
  rounded to an integer) is the tracked number.
- `out/NAME.diff.png` — side-by-side + highlighted diff, the W3C "overlay"
  review artifact; for the text/font categories the *diff image*, not the
  number, is what gets judged (see the caveat below).

## CI gate

`status.txt` is the committed baseline. Plain `run.sh` fails only on
regressions against it: a test that was `OK` now `ERROR`, an `OK` test
whose AE grew, or suite membership changing without a rebase. Improvements
(`ERROR` → `OK`, shrinking AE) never fail the gate; run `--update` to lock
them in and ratchet the baseline down.

## Current baseline (2026-10, after step 3 "geometry compliance")

524 of 526 tests render and compare (`OK`), 2 are `ERROR`; total tracked
AE ≈ 7.06 M differing pixels. (At first landing it was 357 OK / 169 ERROR /
6.27 M; the AE sum rose because formerly-crashing tests now contribute
their real AE and several not-yet-implemented features shifted pixels.)

- The 2 `ERROR`s (`coords-transformattr-01-f`, `coords-units-02-b`) are
  skew matrices whose projection crosses the vanishing line; control
  points legitimately leave the raster bounds and the wavelet raster's
  debug check aborts. Same verdict as the first baseline.
- Largest remaining AE contributors are deferred feature areas: `<use>`,
  `clip-path`/masking, `<view>` fragments, CSS `<style>` blocks, SMIL
  animated frames and font/text metric differences (see caveat below).

## Text/font caveat

The W3C references were rasterized with the suite's own SVG fonts
(`resources/`, GNU FreeSans/FreeSerif derivatives); this harness renders
real text through fontconfig/FreeType. Hinting and antialiasing never match
across rasterizers, so when touching text code, review
`out/NAME.diff.png` by eye and expect AE wobble in `text-*`/`fonts-*`.

## Suite license

The test suite is © W3C, used under the
[W3C Document License](https://www.w3.org/Consortium/Legal/2015/doc-license/).
It is fetched on demand by `fetch.sh` from
`https://www.w3.org/Graphics/SVG/Test/20110816/archives/W3C_SVG_11_TestSuite.tar.gz`
and is **not** committed to this repository.
