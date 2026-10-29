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
| step 10               | SMIL timeline end states: animate/Color/Transform/Motion,     | 3.44 M     |
|                       | freeze + syncbase + max/min (§19.2); single-argument          |            |
|                       | translate(tx) => (tx, 0) fix (§9.5) landed with it            |            |
| step 11               | external `use` hrefs: document swap for the cloned subtree,  | 3.39 M     |
|                       | scope-tagged inherited url(), cross-file loop guard (§5.6)   |            |

\* step 6 is spec-completeness: no suite test *sets* `dominant-baseline`/
`alignment-baseline`, so the AE total is unchanged by construction - the
gate must stay flat, and it does.

## Next steps

Step 10 (SMIL core subset) landed: the CLI renders every document as
though the timeline had run to t = +infinity - `fill="freeze"` end values,
indefinite runs, syncbase begin/end lists and `max=`/`min=` clamping,
`animateMotion` as a supplemental translate left of the transform chain
(with `rotate="auto"`). `animate-elem` fell 781 K -> 334 K; most of the
rest of the drop is the §9.5 `translate(tx)` fix (linking-a-07-t -33 K,
coords-transformattr -15 K, filters-composite-05-f -16 K).

Step 11 (external `use` hrefs) landed: an external fragment opens and parses
the file, then swaps the renderer's document-dependent state (document,
base URL, author sheets, CSS ancestry/sibling maps, font tables) around the
cloned subtree's walk. Style entries that already carry url() paints at the
*use site* get a two-character scope mark into the snapshot stack, so
inherited references keep resolving in the referring document while
references inside the clone resolve in the external one — including over
colliding ids. Root/`<svg>` fragments fit through the existing viewport-fit
branch; parse failures, dangling fragments and whole-file hrefs paint
nothing, and a file already on the §9.8 open-document chain breaks
cross-file cycles. struct-use-05-b fell 54 K, 04-b 11 K, 08-b 1.8 K;
11-f passes at 418. No planned step follows: what remains is the deferred
ceilings below and the opportunistic backlog (first item: external CSS
sheets).

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
- `animate-elem-53-t` (2.1 K) / `animate-elem-63-t` (1.0 K): the only two
  animate tests whose references cannot be reached from any static
  end-state frame. 53-t's reference shows the RR square *before* its scale
  leg finished and paints the whole blue pair red (capture glitch); 63-t's
  shows the two event-ended `set` rows back at base — only true after the
  checker's click/accessKey plus 5 s — while an unfired end event leaves
  those runs active forever. Every other state in both tests matches.
- struct-image-13/14/15-f (453 K): the reference PNGs deviate from the
  tile PNGs they composite; our tiles match ground truth at AE 0 — a
  reference-suite defect, documented in the `<image>` commit message.
- struct-use-06-b (30 K) / 04-b (16 K) / 07-b (36 K): external-reference
  tests where step 11 renders to spec but the archived references do not.
  06-b's body still carries its own "external use isn't implemented, show
  red rects" fallback *under* the clones, and its reference was captured by
  a UA that showed exactly that fallback, so the correct lime external
  rect now paints over it (+6.8 K at the step-11 rebase). 04-b's reference
  shows colored shapes no spec-correct render of the referenced files
  produces; 07-b's nested-`<svg>` fit is already handled to §7.7.
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
- External CSS sheets: follow `@import` url() targets out of embedded
  sheets (styling-css-09-f imports `selector-types-visibility-hidden.css`,
  10-f `case-insensitivity.css`; ~48 K across the selector-types pair) and
  tolerate unquoted attribute-selector values (`[id=testAttributeSelector]`).
  Verify first whether css.d aborts the whole sheet on an unfetchable
  import - that decides how much of the ruleset is being lost today.
- Viewer-side fragment selection (§17.3.2): `#view-id`, `#svgView(...)` and
  `#xywh=` on the CLI's file argument. Pure viewer-URL feature; the suite
  harness passes bare files, so today the no-fragment case (outer svg's
  viewBox/par) is what renders and `<view>` elements stay registered inert.
- `color-interpolation-filters="linearRGB"` pass for the filter chain
  (ch. 15; feeds `filters-conv-03-f` and friends).
- `tref` / `altGlyph` text content elements (§10.6/§10.14.1).
- Round/square caps as dots on zero-length subpaths (browsers paint them;
  the wavelet stroker asserts today — see the `<line>` commit).
