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
| step 12               | static-profile feature strings (Annex I) + the switch's     | 3.34 M     |
|                       | own transform (§5.8.2/§5.8.3)                               |            |
| step 13               | clip-path/mask on `<image>`: the paint goes offscreen      | 3.33 M     |
|                       | with the element's box + user-space CTM (§14.3.5/§14.4)     |
| step 14               | internal-subset general entities expanded over the    | 3.29 M     |
|                       | source text before the walk (XML 1.0 §4.4.2, §G.2/§1.3)  |            |
| step 15               | CSS2 system-color keywords, values of the theme   | 3.24 M     |
|                       | the reference images were captured with (§6.2, CSS2 §18.2) |            |

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
11-f passes at 418.

Step 12 (static-profile feature strings) landed: featureOK claims the
full Annex I set listed under `#SVG-static`, and with it `#SVG-static`,
`#SVGDOM-static` and `#SVGDOM` - Annex I makes SVGDOM true when any
SVGDOM-* string is, and SVGDOM-static is the DOM surface of exactly the
feature set this library parses and paints (parser.d's Document/
Element tree); `#Animation`, scripting and `#SVGDOM-animation`/
`-dynamic` stay honestly false. Triage of the stale "external CSS
sheets" backlog item found a real bug in its place: switchElement never
pushed the switch's own style, so its presentation attrs and transform
were dropped - struct-cond-03-t places its two branches with
`translate(0, 140)` on the switch (§5.8.2). struct-cond-03-t fell
41.0 K -> 0.5 K, animate-elem-36-t 4.3 K -> 2.2 K. The import machinery
itself turned out to have worked since step 5b; the selector-types
trio's 43 K is a defective-reference ceiling (deferred below).

Step 13 (clip-path/mask on `<image>`) landed: `imageElement` routes its
paint through `maskedPaint` when `Style.clipUrls`/`Style.maskUrls` are
non-empty, so a raster image honours both properties like any other
graphics element - §14.3.5 and §14.4 both apply to container elements and
graphics elements, and §3.6.2 makes the image one. The plumbing is the
interesting part: `maskedPaint`, `clipMultiply` and `maskMultiply` now take
the element's geometry as parameters - its box (what objectBoundingBox
fractions are taken of) and its user-space CTM - instead of reading
`path.bounds` and `canvas.matrix`. For an image both reads would be wrong:
it fills a rect in its own natural-pixel space under the §5.7 viewport-fit
transform, while its box is the viewport rect and its clip/mask geometry
belongs in the element's own user space. The two spaces cannot be
decoupled any other way: the blitter always hands a mapping shader
`matrix.inverted` of the canvas CTM (`Blitter.Choose`), so the fit rides
the same matrix the clip would be drawn with.
masking-path-04-b fell 30.6 K -> 15.5 K; the rest is the host-font floor
below (`fc-match Impact` answers Noto Sans, so both the yellow "Clip Test"
row and the glyph outlines cutting the image differ from the reference's
Impact). A unittest pins the four image cases: userSpaceOnUse clip,
objectBoundingBox clip (basis = the viewport rect, not the natural-pixel
path), broken reference (paint dropped) and `mask`.

Step 14 (internal-subset general entities) landed: `parseSVG` expands the
DOCTYPE's internal subset over the source text before the token walk, so
`render-elems-03-t`'s `&shape;` becomes the octagon `<path>` it declares and
the `coords-viewattr` tests' `&Smile;`/`&Viewport1;`/`&Viewport2;` marker
rects appear exactly where they were referenced. The source text is the only
place where a replacement that is *markup* can become markup, and a
replacement that is text still lands in a text node - with attribute values
covered by the same pass. Parameter entities (`%name`, §4.2) and the
external (`SYSTEM`/`PUBLIC`) and unparsed (`NDATA`, §4.7) forms carry no
replacement text and are not collected, and the five predefined entities a
document may not redeclare (§4.4.7) are never in the table; a reference to an
undeclared name - or a cycle, which §4.4.2 forbids - stays written out,
because showing what was typed beats dropping content. The external subset is
never fetched, which is what §1.3 advises. render-elems-03-t fell
31,974 -> 740, coords-viewattr-01-b 8,286 -> 3,618, -02-b 11,433 -> 10,977,
-04-f 6,342 -> 5,941; the other 522 documents carry no `<!ENTITY` and reach
the lexer unchanged. A unittest pins markup and attribute expansion, a
declaration that references another declaration, and the five cases that must
stay as written.

Step 15 (CSS2 system colors) landed: `parsePaint` now consults a second
registry behind the CSS3 keyword table, so the seventeen names
`color-prop-04-t` paints with - `Background`, `AppWorkspace`, `Window`,
`WindowFrame`, `ThreeDFace`, `ActiveCaption`, `ButtonShadow` and ten more -
are colors rather than a failed attribute that SVG's error handling throws
away, and the test's desktop, window, menubar, menu and caption appear
instead of one black slab: 49,423 -> 922. SVG 1.1 §6.2 puts these names among
SVG's color keywords ("The normative reference is CSS2 system colors; in
[CSS2], section 18.2"), and §18.2 fixes the twenty-eight names and what each
is the color *of* while leaving the value to the UA ("mapped to the nearest
system value, or to a default color"), so the palette is ours to declare.
Ours is the flat gray/navy/teal theme the suite's reference images were
captured with - the same call already made for fonts, where a host face
stands in for `SVGFreeSans*`. The alternative, the `GetSysColor` defaults
MSDN documents, measures 18,755 on this test, so the palette is worth 17.8 K
of the 48.5 K and is recorded in the source as a UA default, not as a spec
value. The names are the feature: `highlight`, `menu`, `window` and the rest
parse wherever a color parses, attribute or stylesheet, because `parsePaint`
is the one entry point, and a name in neither registry is still dropped
rather than guessed at. A unittest pins four spellings across the case range
and two names that must fail.

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
- styling-css-09-f (18.9 K) / styling-css-10-f (9.8 K) / styling-pres-
  05-f (14.3 K): step 12 triage proved the external-sheet machinery
  works end to end (`@import` fetch, unquoted `[id=...]` selectors,
  case-insensitive property names/values) and we render the spec
  answer for all three: 09-f's seven blue shapes, 10-f's four orange
  circles, pres-05-f all-green. The archived references are broken:
  09-f's and pres-05-f's show *no shapes at all* - 09-f's own pass
  criteria say "seven blue shapes", and pres-05-f's shapes carry
  markup-level fills - and 10-f's reference shows green circles in a
  test that contains no green. Matching those would mean re-breaking
  visibility !important, the CSS case rules, and presentation-attr
  precedence.
- `filters-turb` (163 K) / `filters-conv` (172 K): feTurbulence noise and
  convolve matrices cannot match the 2009 references pixel-for-pixel.
- Host-font debt (SVGFreeSans/Impact) in `masking-path-03-b/04-b/10-b` and
  the remaining `text-*`/`fonts-*` floors: step 7 took the fonts in; what is
  left is raster drift between our AA and the harness's own SVG-font
  rasterizer. Step 13's residual 15.5 K on 04-b is that floor alone - the
  clip now cuts the image by the right *shapes*, only the Impact letterforms
  are missing (`fc-match Impact` answers Noto Sans here).
  `text-intro-03-b/-06-t/-07-t` (480 K) are a different lever:
  Arabic shaping with host Noto against Kayrawan/Scheherezade references.
- White-page references (~1.46 M, 44% of the 3.33 M baseline): ten tests'
  reference PNGs were captured over an *opaque white page* while our canvas
  is transparent, so their AE is page background, not content. Re-comparing
  our own renderings after `magick -background white -flatten` (a one-off
  script; the harness composites nothing) collapses them: animate-elem-77-t
  166.2 K -> 1.3 K, text-intro-03-b 164.5 K -> 11.0 K, filters-turb-02-f
  161.6 K -> 5.1 K, filters-conv-05-f 153.9 K -> 7.6 K, struct-image-
  13/14/15-f 151 K each -> 5.3/5.3/6.4 K, filters-light-02-f 134.8 K -> 66,
  text-intro-06-t/-07-t 158 K each -> 22.2/22.7 K. Compositing over white
  suite-wide is the wrong lever: 3.33 M -> 73.7 M, because the other 515
  references do keep their alpha. Better of the two readings per test puts
  the suite's content floor near 1.86 M - everything still worth chasing,
  including the ceilings above, lives there.

## Backlog (small, opportunistic)

- Decode the five predefined entities and the character references (§4.1,
  §4.3.7) where they belong: on the node, after tokenizing. Today `&amp;` and
  `&#65;` reach a text node written out and get painted as typed - step 14's
  unittest pins that pass-through - and attribute values are the same;
  `css.d`'s `xmlUnescape` already does the job for stylesheet text. Doing it
  textually instead would turn a label into markup: that variant lost 4.7 K
  on `animate-elem-40-t` (`&lt;animate&gt;` descriptions became elements)
  while gaining 2 K on `text-ws-01-t`/`-02-t`.
- Fix stale § numbers in source comments (text-area refs went with step
  6): `render.d` still cites `§6.1/§6.1.2/§6.1.3/§6.2/§7.1` around text
  layout, `§11.4` markers, `§9.8` image; `css.d`/`filter.d` unchecked.
  Chapter numbers from the local SE's own headings: text is 10, painting
  11 (markers §11.6), the `image` element §5.7, `viewBox`/`par` §7.7/§7.8,
  objectBoundingBox units §7.11, clip-path §14.3.5, mask §14.4, feature
  strings Appendix O. Comments only: the gate must stay byte-identical.
- Viewer-side fragment selection (§17.3.2): `#view-id`, `#svgView(...)` and
  `#xywh=` on the CLI's file argument. Pure viewer-URL feature; the suite
  harness passes bare files, so today the no-fragment case (outer svg's
  viewBox/par) is what renders and `<view>` elements stay registered inert.
- `color-interpolation-filters="linearRGB"` pass for the filter chain
  (ch. 15; feeds `filters-conv-03-f` and friends).
- `tref` / `altGlyph` text content elements (§10.6/§10.14.1).
- Round/square caps as dots on zero-length subpaths (browsers paint them;
  the wavelet stroker asserts today — see the `<line>` commit).
