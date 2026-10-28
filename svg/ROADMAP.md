# SVG engine roadmap

Feature plan for the `graphics:svg` engine. The measurement device is the
W3C SVG 1.1 SE compliance harness (`tests/w3c/`, see its README): one
feature per commit, `run.sh --update` rebases `status.txt` after each, and
the tracked AE total ratchets down. Commit subjects cite the sections of
the spec (`SVG 1.1 §…`) implemented; the authoritative copy is the local
`REC-SVG11-20110816/` (gitignored).

## Where we are

Total suite AE after each step (526 tests; `run.sh` gate):

| step / era            | feature (SVG 1.1 ref)                                            | AE after   |
| --------------------- | ---------------------------------------------------------------- | ---------- |
| step 3 (and earlier)  | harness, engine foundations, geometry compliance (§7, §9, §11)   | ≈ 7.06 M   |
| structure era         | arena document model (§5.1/§5.3)                                 | 6.82 M     |
|                       | use/symbol/a (§5.5/§5.6/§17.2), conditional (§5.8.2-5.8.5)       |            |
|                       | line/transform fixes (§9.5/§7.6)                                 | 6.56 M     |
| paint era             | gradients (§13.2.2-13.2.4), patterns (§13.3)                     | 6.05 M     |
|                       | clip-path (§14.3.5), mask (§14.4), markers (§11.6), image (§5.7) | 5.45 M     |
| filters era (C1..C6)  | filter pipeline + all 15 primitives + lighting (§15.3-15.24)     | 5.05 M     |
| step 5a               | author `<style>` sheets, cascade (§6.4/§6.10/§6.12)              | 4.96 M     |
| step 5b               | CSS selectors, `+`, `:lang()`, `@import` (§6.6/§6.9)             | 4.91 M     |
| step 5c               | text layout: position lists, textLength, spacing, anchor chunks  | 4.91 M     |
|                       | (§10.4-10.5/§10.7/§10.9/§10.11/§10.15)                           |            |

## Next steps

**Step 6 — baseline alignment properties.** `dominant-baseline` and
`alignment-baseline` (SVG 1.1 §10.9.2, plus the inherited `baseline-shift`
already landed in 5c): the one gap 5c left in the text chapter. Runs shift
their baseline per the property's table (auto/use-script/middle/central/
text-top/middle-of-line…). Targets: `text-align-*` (46 K AE now) and the
baseline-offset content in `text-tspan-*`/`text-text-*`. The scoreable win
is capped by the font floor until step 7, but the property model itself is
small and self-contained.

**Step 7 — embedded SVG fonts.** The `font`/`glyph`/`missing-glyph`/
`hkern`/`vkern` + `font-face` chain (SVG 1.1 §20.2-§20.8). The suite's
reference PNGs were rendered with its own SVG fonts from `resources/`
(FreeSans/FreeSerif derivatives); text-intro-03-b, -06-t and -07-t alone
are 480 K of the 530 K `text-intro` AE, and these fonts are the floor
under `text-align-*`, `fonts-*` and the clipped-text masking tests. This
step makes step 6's real effect measurable.

**Step 8 — views and fragment selection.** The `view` element plus
fragment-identifier → viewBox resolution (SVG 1.1 §7.7/§17.3.2-§17.3.3).
Targets: `struct-frag` 344 K (frag-04-t alone 207 K), `conform-viewers`.

**Step 9 — SVG as image.** `<image href="*.svg">` composites through the
offscreen sub-renderer path already used by pattern/clip/mask (SVG 1.1
§5.7). Targets: struct-image-05-b/11-b/12-b/16-f/17-b/19-f (~143 K).

**Step 10 — SMIL core subset.** `animate`/`animateTransform`/
`animateColor` over geometry, paint and transform attributes with
`fill="freeze"` end states. `animate-elem` is the single biggest category
(781 K across 68 tests); the harness already tracks those AE numbers as
future conformance targets (see its "Nothing is excluded" section).

## Deferred / accepted ceilings (do not chase)

- `struct-dom` (228 K) / `types-dom` (39 K): SVG DOM and scripting
  end-states — a CLI renderer has no DOM API surface; verdicts stay as-is.
- `interact-*`: pointer events / interactivity — out of scope.
- struct-image-13/14/15-f (453 K): the reference PNGs deviate from the
  tile PNGs they composite; our tiles match ground truth at AE 0 — a
  reference-suite defect, documented in the `<image>` commit message.
- `filters-turb` (163 K) / `filters-conv` (172 K): feTurbulence noise and
  convolve matrices cannot match the 2009 references pixel-for-pixel.
- Host-font debt (SVGFreeSans/Impact) in `masking-path-03-b/10-b` and the
  remaining `text-*`/`fonts-*` floors — resolved by step 7 or dropped.

## Backlog (small, opportunistic)

- Fix stale § numbers in source comments: `render.d`/`css.d`/`filter.d`
  still cite first-edition numbering (`§6.1` position lists, `§16.x`
  text properties, `§11.4` markers, `§15.6.x` feColorMatrix).
- External-file hrefs and CSS-selector fragment hrefs
  (struct-use-04/05/06/08-b, 11-f).
- `color-interpolation-filters="linearRGB"` pass for the filter chain
  (ch. 15; feeds `filters-conv-03-f` and friends).
- `tref` / `altGlyph` text content elements (§10.6/§10.14.1).
- Round/square caps as dots on zero-length subpaths (browsers paint them;
  the wavelet stroker asserts today — see the `<line>` commit).
