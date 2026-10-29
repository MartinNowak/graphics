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
| step 6                | baseline alignment properties (§10.9.2), host-metric tables      | 4.91 M*    |
| step 7                | SVG fonts: faces/glyphs/kerning, external font files,           | 4.36 M     |
|                       | CSS face matching (§20.2-20.8)                                 |            |
| step 8                | viewer viewport + root svg sizing, root viewBox/par fit        | 4.02 M     |
|                       | (§7.5.1/§7.7)                                                  |            |
| step 9                | SVG as image content: .svg image hrefs via a sub-renderer,    | 3.90 M     |
|                       | loop guards (§9.8)                                           |            |

\* step 6 is spec-completeness: no suite test *sets* `dominant-baseline`/
`alignment-baseline`, so the AE total is unchanged by construction - the
gate must stay flat, and it does.

## Next steps

**Step 10 — SMIL core subset.** `animate`/`animateTransform`/
`animateColor` over geometry, paint and transform attributes with
`fill="freeze"` end states. `animate-elem` is the single biggest category
(781 K across 68 tests); the harness already tracks those AE numbers as
future conformance targets (see its "Nothing is excluded" section).

## Deferred / accepted ceilings (do not chase)

- `struct-dom` (228 K) / `types-dom` (39 K): SVG DOM and scripting
  end-states — a CLI renderer has no DOM API surface; verdicts stay as-is.
  struct-image-11-b (22 K) belongs here too: the references were captured
  after the W3C checker clicked every `<image>` (`onclick` makeGreen), so
  the correct static (blue) state can never match.
- `conform-viewers` (14 K): references captured after script-driven viewer
  zoom/pan (`onload` handlers, `viewport.zoomAndPan`) — scripting end-states
  again; step 8's viewport sizing did not move them.
- `interact-*`: pointer events / interactivity — out of scope.
- struct-image-13/14/15-f (453 K): the reference PNGs deviate from the
  tile PNGs they composite; our tiles match ground truth at AE 0 — a
  reference-suite defect, documented in the `<image>` commit message.
- `filters-turb` (163 K) / `filters-conv` (172 K): feTurbulence noise and
  convolve matrices cannot match the 2009 references pixel-for-pixel.
- Host-font debt (SVGFreeSans/Impact) in `masking-path-03-b/10-b` and the
  remaining `text-*`/`fonts-*` floors: step 7 took the fonts in; what is
  left is raster drift between our AA and the harness's own SVG-font
  rasterizer. `text-intro-03-b/-06-t/-07-t` (480 K) are a different lever:
  Arabic shaping with host Noto against Kayrawan/Scheherezade references.

## Backlog (small, opportunistic)

- Fix stale § numbers in source comments (text-area refs went with step
  6): `render.d` still cites `§6.1/§6.1.2/§6.1.3/§6.2/§7.1` around text
  layout, `§11.4` markers, `§9.8` image; `css.d`/`filter.d` unchecked.
- External-file hrefs and CSS-selector fragment hrefs
  (struct-use-04/05/06/08-b, 11-f).
- Viewer-side fragment selection (§17.3.2): `#view-id`, `#svgView(...)` and
  `#xywh=` on the CLI's file argument. Pure viewer-URL feature; the suite
  harness passes bare files, so today the no-fragment case (outer svg's
  viewBox/par) is what renders and `<view>` elements stay registered inert.
- `color-interpolation-filters="linearRGB"` pass for the filter chain
  (ch. 15; feeds `filters-conv-03-f` and friends).
- `tref` / `altGlyph` text content elements (§10.6/§10.14.1).
- Round/square caps as dots on zero-length subpaths (browsers paint them;
  the wavelet stroker asserts today — see the `<line>` commit).
