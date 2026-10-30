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
| step 16               | `use` of a positioned nested `<svg>`: the clone   | 3.21 M     |
|                       | keeps its own x/y as the viewport origin (§5.6/§7.9)    |            |
| step 17               | render by namespace, not prefix: only SVG-        | 3.18 M     |
|                       | namespace elements reach the arena (§23.1, XML NS)  |            |
| step 18               | currentColor binds at the element that writes  | 3.17 M     |
|                       | the paint value, not the one inheriting it     |            |
|                       | (§11.2/§12.2)                                 |            |
| step 19               | gradient stops read the definition's place in  | 3.16 M     |
|                       | the tree, not the referencing shape's (§13.2.4) |           |
| step 20               | objectBoundingBox gradients keep their own     | 3.12 M     |
|                       | space: the bbox map is a matrix, so a radial   |          |
|                       | in a non-square box is an ellipse (§7.11)      |          |

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

Step 16 (a `use` of a positioned nested `<svg>`) landed: `useElement`'s
instance branch now takes the *target's* own x/y as a translate inside the
use's, so a cloned `<svg>` establishes its viewport where its own attributes
put it, and struct-image-02-b's photo and blue quadrant sit side by side
again - 27,800 -> 406. §5.6 transfers only width and height from the use to
the generated tree ("these values will override the corresponding attributes
on the 'svg' in the generated tree") and §7.9 puts both new coordinate
systems' origin at the (x, y) of the element establishing the viewport, which
the clone still is; that is the same translate `openViewport` already applies
to the inline nested `<svg>` a few elements later in the same test, which is
why its square3 always landed correctly. `<symbol>` is untouched - §5.5 gives
it no x/y at all - and the unittest pins both halves: the instance at the
use's x/y *plus* the target's while the *size* keeps coming from the use, and
a `<symbol>` that carries x/y attributes painting as if it did not. The
`<image>` instance beside it needed nothing: the clone painted all along and
was simply covered by the misplaced blue box. Nothing else in the suite
moved - the only other `use` of an `<image>` or nested `<svg>` is
animate-elem-30-t (unchanged) and two deferred tests.

Step 17 (namespace-aware rendering) landed: `parseSVG` now resolves every
element name through the bindings in scope - the `xmlns:P` prefixes *and*
the `xmlns=` default, tracked over the subtree as the XLink map already was
- and only elements resolving to the SVG namespace reach the arena, under
their *local* name; a foreign element is skipped together with its whole
subtree, ids included. §23.1: "the SVG user agent will include the unknown
elements in the DOM but will otherwise ignore unknown elements", and the
viewer's conformance clause spells out the second half - "data from non-SVG
namespaces are included in the DOM but are otherwise ignored"; there is no
DOM here, so inert means absent. struct-frag-05-t is the test the rule
exists for, and both halves of it were broken: the pale-yellow `<s:circle>`
(a prefix bound to the SVG namespace) never matched because the arena kept
the *qualified* name, while the blue `<circle>` under
`xmlns="http://www.example.org/notsvg"` matched because only the local name
was ever consulted - wrong disc, and two elements later "Invalid" instead
of "Valid". 30,718 -> 688, the rest being the `Valid` glyphs and the
revision line's metrics. The library's own `prefix()`/`localName()` are
unusable: 0.1.7 memoizes the colon per node and misses it on empty
elements, so `<s:circle/>` reported no prefix at all; the split lives in the
parser, the way `attrs()` already splits qualified attribute names. The
default binding is *seeded* to the SVG namespace exactly as `xlink` was, so
documents that never declare one keep rendering while `xmlns=""` (no
namespace) does not, and dropping foreign subtrees wholesale is also what
keeps text-tref-02-b's `<tref xlink:href="#world">` from pulling its text
out of a foreign `<bar>`. A namespace-aware scan of the suite came first:
struct-frag-05-t was the only file painting a foreign element with an SVG
local name - every other hit is xhtml inside `<d:testDescription>`, which
painted nothing - and the gate agrees: no other row moves.

Step 18 (currentColor binds where the paint value is written) landed:
`color-prop-05-t` is a single rectangle under a group - `<g fill="currentColor"
color="lime"><rect width="150" height="150" color="red"/></g>` - and the square
came out the rect's own red where the reference is lime (`#FF0000` against
`#00FF00` at 195,135), against a pass criterion that reads "the user agent
renders the rectangle with a green fill". The REC does not decide it: §11.2
only says currentColor paints "using the current animated value of the color
specified by the 'color' property", and §12.2 gives the 'color' table
(Inherited: yes) without saying whose color an *inherited* `fill:
currentColor` carries - so the criterion is the oracle, and the rule is that
the color belongs to the element that wrote the paint value and then travels
with the inherited property. `pushStyle` used to store the keyword as
`fillIsCurrent`/`strokeIsCurrent` for `paintOf` to resolve at paint time,
which re-binds it on every descendant; the flags are now cascade scratch that
the end of `pushStyle` resolves into a plain `cfill`/`cstroke`, so no style
inherits the keyword and paint time only ever sees colors. Nothing else had
to change: a flag reaching that point always means "named by this element",
and a `use` instance still follows the use site because its walk starts from
the use element's style and re-applies the target's own declaration inside it
(§5.6, struct-use-05-b unmoved), while animated values ride the same cascade
replay, so animate-elem-85-t's animated `color` with `to="currentColor"`
keeps resolving cyan. The scan's prediction held exactly: 11,680 -> 430 and
no other row moves, this being the only document in the suite where a
currentColor paint declaration is inherited into an element that sets
`color`. A unittest pins the group's lime travelling with the inherited
`fill`, the same rule for `stroke`, and the keyword one level down, where
the child's own red is the right answer.

Step 19 (a gradient's stops read the definition's place in the tree) landed:
the REC says it in one sentence, twice - "Properties inherit into the
'linearGradient' element from its ancestors; properties do not inherit from
the element referencing the 'linearGradient' element" (§13.2.2, again in
§13.2.3, and §13.3 says the same of `<pattern>`). What reaches a stop is
what its gradient inherits, so `makeGradient` lost its `Color curColor`
parameter: only the bbox (objectBoundingBox units) and the paint's alpha
cross over from the referencing shape. The subtlety is *what* is inherited,
and §13.2.4's own property tables answer it - `stop-color` and
`stop-opacity` are **Inherited: no** - so `inherit` names the nearest
declaration above while a property the stop leaves out sits at its initial
value (black, 1). pservers-grad-18-b is the four-case pin, four gradients
under `<g stop-color="#f48" stop-opacity="0.5" color="yellow">` and four
rects in groups that all say otherwise: green-to-pink (`inherit`), green at
half opacity (`stop-opacity="inherit"` reaching the group past a gradient
that declares nothing), green to *fully opaque black* (the unnamed stop:
`#000700`, not the group's pink), and green to fully-opaque yellow
(currentColor off the definition's `color`, since `color` really is
inherited - §12.2). Mechanically the arena stores children, not parents, so
`descend` walks root -> gradient, `cascadeProps` applies each ancestor's
declarations top-down (a declaration moves the value; `inherit` and an
unparseable value leave it alone), `scopeFor` puts the two together per
gradient, and `stopValue` resolves one stop against that scope with the
initial values first. Chain links past the head are href targets, so their
stops keep the template's own ancestors (`chainIndex`, §13.2.2). SMIL rides
along: end states rewrite attributes in place, so animate-pservers-grad-01-b's
animations on the definition's own group reach the walk while the four on
the *referencing* groups do nothing. Exactly the predicted rows moved -
18-b 7,592 -> 1,120, color-prop-01-b 5,243 -> 593, animate-pservers-grad-01-b
3,482 -> 1,131, styling-inherit-01-b 4,758 -> 2,750, all 15,481 AE - and
pservers-grad-23-f's 604 did not move, the control case where both readings
are black. All eight of 18-b's stop samples now sit on the reference; its
1,120 and 01-b's 593 are the suite PNGs' own 1-LSB gradient noise. Unittests
pin the four cases and the gradient's own `color="#700"`, and that the
referencing rect's `color`/`stop-color`/`stop-opacity` cannot reach a stop.

Step 20 landed (objectBoundingBox gradient geometry, §7.11): §7.11's
supplemental transformation is a *matrix*, so it belongs between the sample
point and the numbers, not folded into them. Both shaders now hold their
geometry as authored - fractions of the unit square - and `colorAt` starts by
carrying the device sample back through `GradSpace` (origin at the bbox
corner, per-axis extent the bbox size; the identity for
`gradientUnits="userSpaceOnUse"`). Everything after that first line measures
in the gradient's own space: §13.2.3's focal clamp pulls the focus back to
the end *circle* there, because the ellipse is the map's doing and the clamp
has to precede it, and a linear ramp's iso-lines are perpendicular to its
axis there. `brScale = sqrt((w²+h²)/2)`, which made objectBoundingBox `r`
the shape's normalized diagonal, is gone; the percentage basis for a
userSpaceOnUse `r` stays, because that really is §7.5's normalized diagonal.
With the map, `r="20%"` on a 120x90 rect reaches 24 px along x and 18 along y
- the guide ellipses 21-b draws itself (`rx="24" ry="18"`), and the four
rects it checks now sit inside them.

Fractions change the arithmetic budget: the map divides by a box extent that
runs to hundreds of user units, and `spreadMethod` folds `t` at hard
discontinuities. pservers-grad-10-b is the pin. `x1=".4" x2=".6"` on a
460-wide rect puts every `repeat` period boundary on a whole pixel column, so
the sample there is exactly `t = 0`, and a ramp built from `0.4f`
(0.40000000596) lands a hair the wrong side of it and paints the previous
period's last stop - pure lime where the reference paints pure blue, one
column of it, 55 px tall, twice over: 83 pixels. So the geometry is double
end to end: `GradSpace`, the shaders' stored points (`Point!double p0/p1`,
`c/f`, `double r`) and the attribute read, for which `pserver.d`'s `attr` is
now a template whose type follows the defaults. `to!double(".4")` and
`(194.0 - 10.0) / 460.0` are the same double, so the boundary comes back;
the float map costs +28 on that row and the double map 0.

Measured: 21-b 10,196 -> 4,940, 13-b 9,812 -> 3,782, 04-b 7,039 -> 459, 05-b
5,584 -> 1,018, 02-b 2,302 -> 459, 12-b 3,127 -> 490, 14-b 3,574 -> 517, 15-b
2,884 -> 434, styling-inherit-01-b 2,750 -> 620 and struct-use-05-b 7,510 ->
600, 41,459 AE over ten rows and nothing else moved - 10-b back on its
baseline 459. struct-use-05-b is the shear case: `x1=0,y1=0,x2=1,y2=1` on
`<use>` boxes that are not square, so its iso-lines follow the unit square's
diagonal rather than the box's. pservers-grad-11-b (5,323) is the control
that says the change is the map and nothing else: every gradient in it is
`userSpaceOnUse`, its map is the identity, and its residual is somebody
else's question. Unittests pin the ellipse on a 120x90 box - the `t=0.5` pair
30 px right and 22.5 px up, the end stop at both points where the ellipse
meets the box - and the sheared ramp, where (90,0) and (0,67.5) share
`t=0.375` while a user-space projection would split them at 0.48 and 0.27.

Up next - step 21, `gradientTransform` (§13.2.2/§13.2.3): the last
attribute of the gradient geometry chapter that the reader ignores. It sits
*under* step 20's map - the gradient's own matrix carries the authored
coordinates into user space - so `GradSpace` grows from an origin plus two
extents into a matrix that gets inverted, which is exactly the shape
`pattern.d` already carries as `Matrix pt` for `patternTransform`. Two suite
rows pin it, both `userSpaceOnUse`, so it is geometry the tests ask for and
nothing else: 06-b's 2,860 (`translate(25 35) scale(0.5)`, and a second
server at `translate(240,155) skewX(45)`) plus 22-b's 1,275 (`rotate(-37)
scale(0.89 1)` and `rotate(-20)`) - 4,135 AE, small, but the whole of it is
the transform. Then the gradient family's residuals deserve a probe before
the next feature: 11-b 5,323 (all `userSpaceOnUse`, `fx` on the centre, so a
shader-side question), 21-b 4,940, 13-b 3,782, 20-b 1,446.

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
- Operator-activation references: `linking-a-01-b` (23.0 K) /
  `linking-a-03-b` (21.5 K) references are the *post-click* view of the
  linked `linkingCircle-f.svg` — the target document replaces the whole test
  frame — and `animate-elem-20-t` (20.4 K) / `-21-t` (21.1 K) show the
  frozen result of a `begin="indefinite"` fade the operator starts by
  clicking the `<a xlink:href="#fadein">` button. Both files render
  correctly as authored (20-t's white square and both buttons match ours),
  so the delta is the activation, not the paint.
- `animate-elem-85-t` (22.3 K): the reference contradicts the file it is
  scored against. The source documents the freeze state (at t = 10 s both
  `color` and `fill` are `#00ffff`) and we paint exactly that — cyan rects,
  circles at their static fills — while the PNG shows yellow rects with
  red/olive circles and no band for the `<g id="draft-watermark">` the file
  still carries uncommented (the other watermark-carrying files, e.g.
  `animate-elem-86-t` and `linking-frag-01-f`, do keep their band). No
  timing or `currentColor` model reaches that reference.
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
