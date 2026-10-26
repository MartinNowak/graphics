# W3C SVG 1.1 Second Edition compliance harness

Renders the official W3C SVG 1.1 SE test suite (2011-08-16 archive, the
final SVG 1.1 release) with the `graphics:svg` CLI and pixel-compares every
rendering against the suite's reference image. This is the *measurement
device* for the SVG feature roadmap: tolerances start loose and get
ratcheted down as features land.

## Setup

```sh
dub build graphics:svg --config=cli --compiler=gdc   # -> svg/svg-test-application
tests/w3c/fetch.sh                                   # pinned download -> suite/ (gitignored)
tests/w3c/run.sh                                     # render + compare + CI gate
tests/w3c/run.sh --update                            # rebase status.txt after a re-render
tests/w3c/run.sh shapes-rect*                        # subset run for triage
```

## Layout

| file                | role                                                            |
| ------------------- | --------------------------------------------------------------- |
| `fetch.sh`          | sha256-pinned download; unpacks the archive into `suite/`, gunzips the single `.svgz` |
| `run.sh`            | renders all 526 tests (10 s timeout each), `magick compare -metric AE -fuzz 10%`, verdicts, gate |
| `tiers/*.txt`       | committed test-name manifests per roadmap tier (`tiers/generate.sh` regenerates from the prefix rules) |
| `status.txt`        | committed baseline: `NAME.svg <VERDICT> <AE> <tolerance>`        |
| `suite/`, `out/`    | downloaded suite / renderings + diff artifacts — all gitignored  |

## Tiers

526 tests (525 `.svg` + `conform-viewers-01-t.svgz`); membership by W3C
chapter prefix, curated once — see the header of `tiers/generate.sh`:

| tier       | tests | rules                                                            |
| ---------- | ----- | ---------------------------------------------------------------- |
| `geometry` | 111   | `shapes- paths- coords- render- conform- styling-pres- color-prop- painting-{fill,stroke,control}-` |
| `servers`  | 119   | `struct- pservers- masking- styling-` (non-`pres`)               |
| `text`     | 74    | `text- fonts-`                                                   |
| `skip`     | 164   | `animate- interact- script- linking- types-dom- svgdom-`, any `*-dom-*`, `color-prof-` (ICC) |
| (other)    | 58    | uncategorized: `filters-*` (43), `painting-marker-*` (8), `painting-render-*`, `types-basic-*`, … — future work packages |

## Verdicts and tolerances

- `ERROR` — the renderer crashed / timed out / produced no image, or `magick
  compare` errored. The engine's stderr goes to `out/NAME.err`.
- `PASS` — AE within the tier tolerance; `DIFF` otherwise.
- `out/NAME.diff.png` — side-by-side + highlighted diff (the W3C "overlay"
  review workflow; for the text tiers the *diff image*, not the verdict, is
  what gets judged).

Initial tolerances (AE at fuzz 10 % on the 172 800 px reference canvas;
edit the `TOL_*` vars in `run.sh` to ratchet, then re-record):

| geometry | servers | text | skip | other |
| -------- | ------- | ---- | ---- | ----- |
| 1200 (0.5 %) | 1728 (1 %) | 43200 (25 %, review-only) | 0 | 1200 |

Note: ImageMagick's `-metric AE` is a channel-weighted difference count and
can be fractional; `run.sh` rounds it to an integer.

## CI gate

`status.txt` is the committed baseline. Plain `run.sh` fails only on
regressions against it: a verdict worse than the baseline (PASS→DIFF,
DIFF→ERROR, …), a tier pass-count drop, or tests appearing in / vanishing
from the suite without a rebase. Improvements never fail the gate.

## Baseline at first landing (2026-10)

| tier       | tests | PASS | DIFF | ERROR |
| ---------- | ----- | ---- | ---- | ----- |
| geometry   | 111   | 0    | 76   | 35    |
| servers    | 119   | 1    | 67   | 51    |
| text       | 74    | 44   | 4    | 26    |
| skip       | 164   | 0    | 132  | 32    |
| other      | 58    | 0    | 33   | 25    |

Known systematic causes behind these numbers:

- Every test carries `width="100%" height="100%"`; `parseLength` turns that
  into a 100×100 canvas, so even correct geometry renders wrong (roadmap
  step 3, item 1). The text tiers PASS early because their references are
  mostly white on white and the tolerance is 25 %.
- Most `ERROR`s are `guip.color()` asserting on CSS color keywords it does
  not know (`lime` etc.) — the paint-attribute work in step 3 absorbs this.

## Text/font caveat

The W3C references were rasterized with the suite's own SVG fonts
(`resources/`, GNU FreeSans/FreeSerif derivatives); this harness renders
real text through fontconfig/FreeType. Hinting and antialiasing never match
across rasterizers, which is why the text tiers stay review-only
permanently — compare `out/NAME.diff.png` by eye when touching text code.

## Suite license

The test suite is © W3C, used under the
[W3C Document License](https://www.w3.org/Consortium/Legal/2015/doc-license/).
It is fetched on demand by `fetch.sh` from
`https://www.w3.org/Graphics/SVG/Test/20110816/archives/W3C_SVG_11_TestSuite.tar.gz`
and is **not** committed to this repository.
