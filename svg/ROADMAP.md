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
| step 21               | gradientTransform rides under the gradient's   | 3.11 M     |
|                       | own space: the bbox map composes over it, so   |            |
|                       | a skewed radial paints an ellipse (§13.2.2)    |            |
| step 22               | a radial focus snapped onto the end circle     | 3.11 M     |
|                       | leaves a degenerate quadratic, so its roots    |            |
|                       | are solved without cancellation (§13.2.3)      |            |
| step 23               | a data: URI payload folded across lines is     | 3.10 M     |
|                       | the same bytes: XML §3.3.3 makes the fold a    |            |
|                       | space the base64 decoder has to skip           |            |
| step 24               | an absolute length resolves on the 96 dpi      | 3.09 M     |
|                       | basis the W3C references were captured on      |            |
|                       | (SVG 1.1 §7.10)                                |            |
| step 25               | paint composites in linear light when          | 3.09 M     |
|                       | color-interpolation says linearRGB             |            |
|                       | (SVG 1.1 §11.3)                                |            |
| step 26               | a gradient ramp interpolates in the space the  | 3.09 M     |
|                       | property names: linearRGB mixes the stops as   |            |
|                       | light, sRGB as bytes (SVG 1.1 §11.3.3)         |            |
| step 27               | a zero-length subpath is stroked after all -   |            |
|                       | every capper needs a terminal direction, and   |            |
|                       | this kind of subpath has none (SVG 1.1 §11.2)  | 3.07 M     |
| step 28               | text on a path rides a measured reference -    | 3.07 M     |
|                       | every glyph turns to the chord of its own      |            |
|                       | advance, centred (SVG 1.1 §10.8, §10.13.3)     |            |
| step 29               | a <tref> is a tspan whose text is the          | 3.07 M     |
|                       | referenced element's flattened character       |            |
|                       | data, markup stripped (SVG 1.1 §10.6)          |            |
| step 30               | a text content element keeps the white space   | 3.06 M     |
|                       | the parser used to delete: one string per      |            |
|                       | element, breaks gone, gaps consolidated once   |            |
|                       | (SVG 1.1 §10.15)                               |            |
| step 31               | an altGlyph replaces its character data with   | 3.06 M     |
|                       | the glyphs its href names, by element id in    |            |
|                       | any registered font, first complete            |            |
|                       | altGlyphItem winning (SVG 1.1 §10.14)          |            |
| step 32               | a rotate list turns each character about       | 3.06 M     |
|                       | its own text position, the nearest list above  |            |
|                       | answering over that element's whole subtree    |            |
|                       | (SVG 1.1 §10.2/§10.4-§10.5)                    |            |
| step 33               | a reference, entity or character, resolves on  | 3.04 M     |
|                       | the node it stands on: character data and      |            |
|                       | attribute values decode, a CDATA section keeps |            |
|                       | what it typed (XML §4.1, §4.2, §4.4.7)         |            |
| step 34               | a mask's luminance is taken in the space       | 3.04 M     |
|                       | color-interpolation names on the <mask>        |            |
|                       | element, weighted by §15.10's own row          |            |
|                       | (SVG 1.1 §14.4)                                |            |
| step 35               | an attribute value's white space: XML turns    | 3.04 M     |
|                       | a literal tab or line ending into a space,     |            |
|                       | a reference keeps the character it names,      |            |
|                       | a number list splits on either (§3.3.3, §7.1)  |            |
| step 36               | feConvolveMatrix measures its edges on         | 3.04 M     |
|                       | the input image's own border, and edgeMode     |            |
|                       | starts at none, not the duplicate our          |            |
|                       | parser reached for (SVG 1.1 §15.17)            |            |
| step 37               | the viewer's own URL: the fragment on the file | 3.04 M*    |
|                       | argument picks the initial view - #view-id,    |            |
|                       | #svgView(...) or #xywh= - and a <view> inside  |            |
|                       | a nested <svg> re-roots the document           |            |
|                       | (SVG 1.1 §17.3.2)                              |            |
| step 38               | an feImage href that is not an image file      | 3.03 M     |
|                       | paints the element its fragment names, where   |            |
|                       | it stands, the way `use` does, and the         |            |
|                       | subregion is only a clip (SVG 1.1 §15.18)      |            |
| step 39               | the same fragment on someone else's URL: an    | 3.03 M*    |
|                       | image href into an .svg document picks the     |            |
|                       | view of it that the image shows - <view>,      |            |
|                       | svgView(...), xywh= (SVG 1.1 §17.3.2)          |            |
| step 40               | §15.18's first half: an feImage href that      | 3.03 M*    |
|                       | names an SVG file renders that file the way    |            |
|                       | `image` does - rect as viewport, the fit and   |            |
|                       | the view fragment included (SVG 1.1 §15.18)    |            |
| step 41               | stale section numbers in the source comments:  | 3.03 M*    |
                        | 117 cites re-checked against the SE's own      |            |
                        | contents, and three notes rewritten to say     |            |
                        | what the spec says (comments only)             |            |

\* step 6 is spec-completeness: no suite test *sets* `dominant-baseline`/
`alignment-baseline`, so the AE total is unchanged by construction - the
gate must stay flat, and it does.

\* step 37 is the viewer's own URL: the harness hands the CLI bare file
names, so no row can move - the 526 came back byte-identical, and that is
what the gate checks here.

\* step 39 is §17.3.2 on an external reference: the suite's fragments sit
on `<a>` elements, font hrefs and `use`/`tref` element ids, and the one
`<image>` href that carries a '#' names an element in the *same* document,
which the test says must not display. Nothing to move; 526 rows came back
byte-identical again.

\* step 40 is §15.18 on an SVG file: the harness's 37 `feImage` file
hrefs are PNGs and a JPEG, its 24 element-id hrefs all belong to
`filters-composite-02-b`, and no test aims an feImage at an SVG document,
so this row cannot move either - byte-identical again.

\* step 41 is comments only, so it cannot move a row by construction: 547
`§` cites across the sources, every distinct number matched against the
SE's expanded table of contents, and the 526 rows came back
byte-identical again.

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

Step 21 landed: `gradientTransform` (§13.2.2) was the last attribute of the
gradient geometry chapter the reader ignored. It establishes the coordinate
system that `x1/y1/x2/y2`, `cx/cy/r` and `fx/fy` are authored in, so it rides
*under* step 20's bbox map rather than over it: with objectBoundingBox units
the transformed unit square is what gets carried onto the box, per-axis scales
last, i.e. `user = bbox · gradientTransform · gradient`. `GradSpace` therefore
grows from an origin plus two extents into the six doubles of an affine, laid
out the way `Matrix` is, and `pattern.d`'s `patternTransform` rule is reused
whole: `strAttr` along the href chain, `transformSVG` into a `Matrix`, a
malformed list puts the server in error, and so does the `matrix(0 0 0 0 ..)`
that disables rendering. A transform that cannot be undone is an error too -
the shaders sample by walking this map backwards, so `scale(0)` gives them
nothing to walk - hence `invertible()` and the divide by a determinant `op`
may assume non-zero. Composing in double keeps the transform's float parse as
the only 24-bit step on the path.

`op` keeps two forms, and that is a precision call, not a shortcut. An
axis-aligned map - no transform, or translate/scale only, which is most of
what authors write - stays on the plain divides step 20's boundary pins are
measured against; the general inverse is the same algebra in different last
bits, and pservers-grad-10-b is decided in those bits. Only a skewed or
rotated map takes the general path, which is also where the feature shows
best: a skew turns a radial's circle into a tilted ellipse and stops a
linear ramp's iso-lines from being perpendicular to the axis in *user* space,
so no amount of folding the geometry into user-space numbers would do it.

Measured: 06-b 2,860 -> 765 and 22-b 1,275 -> 462 - 2,908 AE, and those are
the only two rows in the suite that set the attribute, so nothing else moved.
Unittests pin the moved ramp (`translate(20 5) scale(2)` puts the
(0,0)-(10,0) vector on user (20,5)-(40,5), and the iso-line one scaled unit
off the axis is still mid-ramp), the sheared radial (user (270,185) is 42 user
px from the centre but only 30 gradient units out, so mid-ramp and not
t = 0.71), the composition order (objectBoundingBox plus `rotate(90)` on a
20x10 box runs the default ramp up the left edge to (0,10); the other order
would run it along the bottom to (20,0)), and the error states - an
unparsable list, `scale(0)`, `matrix(0 0 0 0 5 5)` - plus the attribute
travelling down an href chain.

Step 22 probed the gradient family's residuals instead of opening a chapter,
and the probe found a real defect rather than a ceiling. §13.2.3's clamp -
"if the focus point lies outside the circle or ellipse defined by r, the focus
point and the perimeter of the circle or ellipse coincide" - is exactly the
state pservers-grad-21-b writes with `cx="100%" fx="25.00%" r="20.00%"`, and
after the clamp `|L| == r` holds only up to rounding: `colorAt`'s
`a = L dot L - r*r` came out as a one-ulp residue (-2.08e-17 on 21-b's 120x90
box) while `b` and `disc` both sit near 0.05, so the textbook
`(-b +/- disc) / 2a` divides a difference of two nearly equal numbers by that
residue and the root is noise. Grad5's ramp turned into plateaus of constant
alpha (191/159/127 where the reference runs 202 down to 128). Where `a` landed
exactly 0 - `cx="00.00%"`, so `fx - cx = 0.25` divides exactly by `r` - the
linear branch was worse: it handed back `t < 0` for points *past* the end
circle and `sampleStops` clamped that to stop[0], so the far half of the
rectangle painted opaque black where the reference is transparent. The solve
is now the cancellation-free one (`q = -(b + copysign(disc, b)) / 2`, roots
`q/a` and `cq/q`), the `a == 0` case pads at the last stop when `b >= 0`
instead of running off the ramp's start, and the root is chosen from the sign
of `a` - a positive `a` crosses both circles, so the smaller non-negative one
- rather than from an `inside` flag rebuilt per pixel from the post-clamp
focus, which was the other half of the same confusion. A unittest pins both
symptoms and the padded case on a 120x90 box: the `c100`/`c0` mirror pair,
focus snapped onto the perimeter, paints stop[0]; alpha sits at 178-183 at
x = 110 where the linear solve says `t = 0.2917`; alpha falls strictly across
x = 97..119, the rows that were plateaus; and both the region behind the
focus and the region past the end circle pad at stop[1].

Measured: pservers-grad-21-b 4,940 -> 968 and pservers-grad-13-b
3,782 -> 2,841, and no other row in the suite moves; the baseline rebases
3,113,645 -> 3,108,732. What is left on 21-b is its own guide-ellipse strokes
(110 AE at the cell at x = 160, y = 120, 70 at x = 160, y = 220), the green
reference box running down x = 360 and the `$Revision` text band - deferred
classes, and the row is at that floor.

The probe also settled 13-b, in the other direction, and it belongs on the
ceiling list. Post-fix its ring geometry agrees with the reference pixel for
pixel: the t = 0.5 ring is at y = 71 in both, the t = 1 boundary at y = 92 in
both, and at x = 300 both end at y = 86. Only the ramp's weighting differs,
and it fits with no free parameter - composited blue is `139*w` for us and
`139*w^2` for the reference, which is interpolating `stop-color` and
`stop-opacity` separately instead of premultiplied; whole columns then agree
to a mean of 1.3 levels (x = 60, x = 100, x = 300). The renderer that captured
those PNGs in 2009 did exactly that, and SVG 2 / CSS Images 4 §4.6 ask for
premultiplied, so ours stays. The corollary explains the family's floor: the
only four gradient tests that mention `stop-opacity` at all - 05-b, 13-b,
18-b, 21-b - are four of its six worst rows, and 21-b, whose fades hold the
colour constant and so cancel the term, fell to the floor as soon as the focus
solve was fixed.

Step 23 read §7.3/§7.4's `<image>` at the place the step-22 sweep had
pointed at, and it takes the suite's largest un-triaged row almost to nothing:
coords-viewattr-02-b 10,977 -> 531 and animate-elem-40-t 4,573 -> 2,324, with
no other row moving; the baseline rebases 3,108,732 -> 3,096,037. 02-b draws one
100x100 JPEG thirteen times under thirteen `preserveAspectRatio` values and
painted none of them - every image box was transparent - while the same blob
written on one source line loads yellow in the same render, from a `probe.jpg`
href and from a data href alike. So the codec was never the question; the
source's line length was. RFC 2397 spells a data: URL's payload as MIME base64,
which folds at 76 characters, and the suite folds all thirteen payloads inside
the href attribute. XML §3.3.3 normalizes an attribute value's newlines to
spaces on the way to us, so `loadDataURL` received a base64 string with spaces
in the middle of it, `Base64.decode` refused it, and §9.8's broken-reference
rule turned that into a cached empty `Bitmap` - blank box, thirteen times. §7.4's
href is a URI-reference, but this whitespace belongs to the payload, not to the
URI, and RFC 4648 §3 does not count whitespace as part of the encoding: every
UA that captured a reference image skipped it. `base64Payload` now strips the
four XML whitespace characters from the payload alone, leaving a space in a path
or a query the error it is. Both directions are pinned in unittests: the
unwrapped 1x1 PNG still decodes edge-to-edge, and the same payload folded across
two lines, indentation and all, paints the same red 10x10 tile.

What the two rows keep is the compare's floor, not the row's. 02-b now has no
strong delta anywhere - a 20%-threshold connected-components pass finds nothing
but the background - so its 531 is the label text band plus JPEG decode drift
under the fuzz. 40-t's two 82x82 image boxes each hold 163 strong pixels of
interior drift, and a 202-pixel label band plus a handful of smaller runs carry
the rest of its 1,515. The negative control is worth recording
for the next time an `<image>` row looks broken: eleven suite rows carry a data
URI whose payload is already on one line, and not one of them moved.

Step 24 changes one constant: `enum dpi = 72` in `parseLength` becomes `96`.
That function is the only place the absolute identifiers are resolved, and both
the presentation attributes and the `<style>`/inline rules reach it, so the basis
is shared and the constant really was the feature: a scratch document that asks
for one stroke width eight ways answers unit-less, `20px` and `2em` correctly and
then paints `0.25in` 18 px wide, `16pt` 16, `2pc` 24, `0.5cm` and `5mm` both
14.17 - each exactly three quarters of what §7.10 asks for.

The number comes from §7.10 itself: the identifiers are "an appropriate
multiple of one px unit ... based on what the user agent knows about its viewing
environment", its worked example is a 90 dpi system ("1pt equals 1.25px", "1in
equals 90px"), and the section then pins the environment the harness cares about
- "The reference image above was generated on a 96dpi system (i.e., 1 inch = 96
pixels)". Before touching the constant that claim was checked against the suite's
own pixels rather than the prose. coords-units-03-b draws its five absolute
lengths as rects one unit high at y=180/200/220/240/260; scanning those rows in
`suite/png/coords-units-03-b.png` finds ink from x=20 to x=115 on all five, i.e.
96 px, where ours measured x=20..91, 72 px. The five rows above them (200 user
units, `200px`, `20em`, `40ex`, `41.67%`) measure x=20..214 in both images, so px,
em, the half-em x-height and the percentage were already right and only the
absolute basis was off. That is why the change is one line: 1pt = 96/72, 1pc = 16
and 1cm = 96/2.54 all follow from the same basis, and the unittests now pin
`1in` = 96, the five spellings equal to each other, and those three ratios.

Measured: coords-units-03-b 5,388 -> 1,733, coords-units-02-b 2,311 -> 570,
filters-morph-01-f 8,527 -> 8,369, and no other row moves, which makes the
sweep's count of three absolute-unit rows exact. -5,554, 3,096,037 -> 3,090,483.
Most of 03-b's gain is not the five rects: its `units-test` group sets
`font-size="10pt"`, which rendered 10 px tall where the references set 13.33. The
residuals are not the unit table either. 02-b has no strong delta anywhere - a
20%-threshold connected-components pass finds nothing but the background - so its
570 sits under the compare's fuzz; 03-b's strong runs are the `Arial` title band
at y=11 and the `$Revision` band at y=317, both host-font debt; and
filters-morph-01-f keeps 8,369 because its four feMorphology result boxes
(144x117, 142x117, 130x92, 128x105) hold 10.9 K strong-delta pixels, the
morphology cousin of the feTurbulence/feConvolveMatrix ceiling.

Two rows that looked like features in the same pass are references no correct
render reaches, and both are now deferred. struct-use-09-b (8,294) nests five
`<symbol>`s, each `<use>`ing the next, and its pass criteria ask for "5 nested
rectangles with different coloured strokes (black, yellow, orange, purple and
blue)": our render has all five rings, at half-widths 90/80/70/60/50, in exactly
those colours, while the archived PNG holds no gold, orange, purple or slateblue
pixel at all - its centre is one 99x99 opaque square and a scattering of red
pixels. struct-cond-overview-05-f (7,485) is that class pointing the other way:
§5.8.1 states that "conditional processing attributes only affect the direct
rendering of elements and do not prevent elements from being successfully
referenced by other elements (such as via a `use`)", which is what we do - three
black `use` clones cover the red decoys at x=200 - while the reference shows the
red decoys, the state the test exists to forbid.

Step 25 landed the paint half of `color-interpolation` (SVG 1.1 §11.3). The
engine had no handler for the property, so every composite ran in the storage
space - which is what the initial `sRGB` value asks for, and 525 rows never name
the property. painting-render-02-b is the row that does: five identical white-50%
rects over black, labelled `dark` and `light` against the `#7F7F7F` and
`#BBBBBB` chips above them, and the two readings of the property differ by one
number - the sRGB-domain blend gives 127, a linear mix gives
srgbEncode(0.502) = 188, and the `light` chip is 187. The rects that name
`linearRGB`, and the one that reaches it through `inherit` from its
`<g color-interpolation='linearRGB'>`, were flat-out wrong; the initial-value,
`sRGB` and `auto` rects already sat under the fuzz.

The blend is `blendPMlin`, blendPM's neighbour: the element's paint goes to a
full-canvas scratch first (the maskedPaint and filteredElement convention), then
both sides are un-premultiplied with filter.d's own rounding, decoded through the
piecewise sRGB curve the §15.4 chain already works in, mixed, and re-encoded on
the way out. Two identities keep the detour cheap and regression-safe: an opaque
source, or a transparent destination, composites the same in either space, so
`flushPath` skips the scratch outright when the element's paint is solid, and the
`<mask>` and `<clipPath>` content that inherits the property while painting
opaquely is untouched by it. painting-render-02-b 5,086 -> 1,184, and what is
left is exactly the seven `dark`/`light` labels inside the boxes: bands of
98x98 to 149x99, 195-489 strong-delta pixels each, host-font AA. Nothing else in
the suite moves.

`clip` (§14.3.3), which the previous sweep lined up as this step, turned out not
to be a feature. §14.3.3 imports CSS 2.1 §11.1.2's
`rect(<top>,<right>,<bottom>,<left>)`, and there the four values are the
offsets from the top and the *left* border edges - all four measured from one
point, which CSS 2.1 still spells out: "future updates may also reintroduce a
syntax for offsetting shapes from each edge instead of offsetting from a point".
`rect(10,10,10,10)` is therefore zero-area, so a conformant render paints *no*
image, while the archived PNG and the pass criteria ("two images inside the red
rectangles") show Batik's from-each-edge inset. Deferred.

filters-composite-03-f (9,647) looked like the next §15 feature and is the same
alpha question instead. Its FillPaint/StrokePaint inputs and the arithmetic are
already right: the identical and clamped squares compare at AE 0. The two that
miss are the semi-transparent results - `2F - 1.5F` leaves alpha 0.5 where the
reference is (127,255,127) opaque, `-0.5F - 0.1` leaves 0.6 black where it is
(102,102,102) opaque - and each reference pixel is ours composited over white.
Flattening *both* sides over white collapses the row 9,647 -> 2,386, which is the
AA of the three guide rings. Also deferred.

Step 26 landed the ramp half of `color-interpolation` (SVG 1.1 §11.3.3), and
painting-render-01-b went 2,354 -> 1,571. The property had its §15 reading from
step 25; a paint server is the other place the spec names it, for the space the
stops are interpolated in. The row paints three bars from the same
white-blue-red-yellow stops - default value, `sRGB`, `linearRGB` - and only the
linearRGB bar disagreed: strong components 97x40+40+240 (2,097 pixels, mean
delta 33) and 99x40+241+240 (856, mean 81). Nothing read the property, because
the ramp is `sampleStops`'s own `lerp` over premultiplied stop bytes, and a mix
of bytes is a mix in whichever space the bytes live in - sRGB, whatever the
property says.

`lerpLinear` is `lerp`'s neighbour: both sides un-premultiply the way
`straightByte` does, decode through `srgbDecodeLUT` - the same piecewise curve
the §15 chain works in, not another approximation of it - premultiply by their
own alphas, mix, and divide by the interpolated alpha on the way back to a byte,
re-encoding through a 4096-entry table because the shader samples per pixel and
a `powf` per channel per pixel is not a gradient's budget; 1/4095 of a linear
step is worth at most 0.003 of a byte, where the curve is steepest. Alpha is
linear by definition and takes no curve, which is why the two readings meet at
both ends of every stop interval and only part company in the middle, and why a
`stop-opacity` fade comes out identical either way - a unittest pins that.

The value comes from the gradient's own place in the tree, which is the rule
`stopsOf` already states for `stop-color` and `stop-opacity`: nothing of the
referencing shape reaches the ramp. So the flag rides `StopScope` and
`cascadeProps` learns one property name - `linearRGB` on an ancestor reaches the
ramp, the element's own `sRGB` overrides it back - while an href template's
declaration rides over that through `strAttr` and the chain walk, the way every
other gradient attribute does. That is how the third bar here is driven: its
gradient sits in the `<defs>` of a translated group, whose translate is also
what puts the ramp where it is.

That bar is now pixel-equal to the reference wherever the file's own marker
lines do not cover it: device x=65 (224,224,255), x=130 (85,85,255) and x=255
(255,113,0) read the same on both sides, where the sRGB bars give (191,191,255),
(23,23,255) and (255,42,0). Per bar the row measures 247 / 247 / 277 of AE, so
771 of its 1,571 is inside the bars and the other 800 sits outside them in the
title and the labels. Inside, what is left is the connected components this step
leaves behind - 96x40+244+240 (229) and 89x40+40+240 (214) on the linear bar,
75x40+265+80 and 64x40+40+80 (186 and 164) identically on each sRGB bar - which
is one-level ramp rounding and the anti-aliasing of the marker lines; that sRGB
pair is the 127-versus-128 midpoint class already on the deferred list. No
other row moves anywhere: this is the only suite row naming the property on a
gradient.

Step 27 landed the line caps of zero-length subpaths (SVG 1.1 §11.2). The row
is the plainest statement of the rule in the suite - three subpaths of no
length at all at stroke-width 96, the three `stroke-linecap` values in turn -
and the reference paints what §11.2 promises: nothing for `butt`, and for the
other two a dot exactly one stroke width across, the file's own comment giving
the areas as pi*r^2 = 7,238 and 4r^2 = 9,216. We painted nothing for all three,
because a subpath that never moves never reaches a capper: `finishContour` in
`src/graphics/core/stroke.d` drops a contour whose two ends are the same point,
and handed one, `ButtCapper`, `RoundCapper` and `SquareCapper` all ask for the
terminal normal, which this has none of. So the cap gets built where the
geometry is still legible: `addZeroLengthCaps` walks the same verb stream the
stroker was fed, and for every subpath that opened, moved nothing and did not
close it appends the cap as a shape onto the already-stroked `Path` - a disc of
diameter `stroke-width` for `round`, and for `square` a square of that side
centred on the point, which is what a square cap comes down to when there is no
direction to point it the way of. `butt` returns early, and a subpath that
closes back on itself is not stroked at all.

Riding the already-stroked path is also what keeps the change small: the caps
inherit the stroke paint, `stroke-opacity`, the clip and mask chain and the
§11.3 linear-blend scratch path with no second copy of any of it, and they
arrive at both places a stroke gets painted - `flushPath` for shapes, and the
text run's. The second of those needed one more loosening: `shape("line")` used
to skip a `<line>` whose ends coincide, on the theory that the stroker would
assert on it. The geometry goes through now, because what such a `<line>` asks
for is a cap and not a ribbon.

painting-control-04-f goes 8,644 -> 577, and two rows nobody aimed at come down
with it. painting-stroke-10-t (4,926 -> 629) is the same test written twice:
`M190,170 L190,170` at stroke-width 50 in the three caps, and `M190,240 c0,0
0,0 0,0` in the row under it. The cubic falls out of the same check for free,
since a `c` whose control points are all the current point moves nothing.
animate-elem-80-t (3,507 -> 2,854) marks each of its grey silhouette positions
with a `<line x1="40" x2="40">` at stroke-width 15 under round caps; those dots
exist now. Nothing else in the suite has a zero-length subpath in it, which is
what the gate confirms.

What the 577 leaves behind is not §11.2. Our disc covers device x 148..243
completely; the reference is half at 148, full 149..243, half at 244 - the same
96 across, half a pixel right. Its 1-unit frame is fully opaque at device x=1
where ours splits 50/50 between 0 and 1, and an ordinary stroke reads the same
way: on shapes-rect-01-t the 8-unit band of `x="30" stroke-width="8"` is
[26,34], ours full at 26..33, the reference 0.5 at 26, full 27..33, 0.498 at
34. Fills are not off that way - the same file's fuchsia `x="130" width="50"`
is crisp at 130..179 on both sides - so what is left is the reference's
convention for the stroker's offset contours rather than a §11.2 remainder,
and it is no AE prize either: rolling our rendering half a pixel right and down
moves shapes-rect-01-t 929 -> 948 and this row 577 -> 573. Recorded, not
chased.

Step 28 landed `<textPath>` (SVG 1.1 §10.8, laid out by §10.13.3). The
element had no case in the walk at all, and an unknown element still walks
its children, so its text joined the `<text>`'s run and ran out from the
text's origin - a baseline at y=0, which leaves next to nothing on the page.
That is why text-path-01-b (2,743) and text-path-02-b (3,882) looked like
font rows: the ink they were missing was not in the frame.

The measuring half is the library's. `PathMeasure` already turns a `Path`
into a distance table - `length`, `getPosAtDistance` - so the renderer adds
one entry per `<textPath>` under the current `<text>`: measure, total, the
resolved `startOffset`, and a `bad` flag. Runs refer to it by index
(`TextRun.onPath`, `size_t.max` meaning the straight pen) rather than by
pointer, because the run list keeps growing while the walk is still adding
paths to the array it indexes into. The closer that dashing needed is the
closer measuring needs too: `expandedCloses` expands the implicit closing
line into an explicit one, and gained a transform argument on the way, since
§10.8.1 reads the reference's *data* in the `<text>`'s user space - the
reference's own `transform` composes onto the geometry, its ancestors' do
not. paths-dom-01-f runs its text around a rect written as `m h v h v`, where
the last edge is a close.

The rule that places a glyph is not the one it looks like. §10.13.3 walks
one charwidth past the startpoint-on-the-path to the endpoint, takes the
midpoint between them, and requires the *glyph-midline* - the vertical line
through the midpoint of the glyph's own x axis - to pass through it, and to
be perpendicular to the line joining those two points. So the outline's
origin travels half an advance *behind* the midpoint, in the rotated frame,
and the rotation is the chord across that stretch rather than the tangent at
one point. A glyph whose midpoint-on-the-path is off either end of the path
is not rendered at all. For a run on a path, `pen.x` carries the distance
travelled and `pen.y` is unused; `x` on a nested `tspan` is an absolute
offset along the path, `y` is ignored, and `dy` moves across it in the
rotated frame - text-path-01-b's fuchsia `Te` at `dy="-12"` is that offset.

`startOffset` resolves three ways and the suite uses all three: a length, a
percentage of the measured length, and - if the reference carries a
`pathLength` - a value in the author's units, scaled by measured/authored.
Only the offset scales, never the glyph advances, which is what the test's
own pass criteria say: with `pathLength="100"` on a 300-unit perimeter the
text starts at the lower-right corner and is "cut off when reaching the end"
rather than squeezed to fit. `text-anchor` picks the start point before the
walk, against the run's own width. `method="stretch"` and `spacing="auto"`
are not implemented; `align` and `exact` are the defaults, and they are what
the suite asks for. A dangling href, a target that is not a `<path>`, or a
`d` that will not parse is §10.8.1's error state - the whole subtree stays
unpainted.

Of the four rows: text-path-02-b 3,882 -> 2,748, paths-dom-01-f 1,095 ->
876, text-align-04-b 2,811 -> 2,693, and text-path-01-b 2,743 -> 3,079, the
one the feature makes worse. Cropping the frame says the placement is right:
the straight `startOffset="33%"` sentence of that same file, on a path that
is a line, goes 944 -> 453 AE. The other two sentences ride beziers in
`Georgia`, which resolves here to a substitute face, and AE carries no
spatial tolerance - ink that is present but mismatched costs about twice
what absent ink costs. Same ceiling as every other text row. Under it there
is one more: `PathMeasure` sums chords over flattened pieces, so on a tight
curve the parameterization comes in a little short of exact arc length and a
long run bunches by a percent or two. The straight-path rows show no such
residue, and separating the two here needs a Georgia this host does not have.
Recorded, not chased.

Step 29 landed `<tref>` (SVG 1.1 §10.6). The element is applied "as if the
`tref` element was replaced by a `tspan` with the referenced character data
(stripped of all supplemental markup)", and that is the shape of the code:
x/y/dx/dy and the style are the tref's own, the run is opened exactly as a
tspan's - so the text node after `</tref>` reopens the parent's - and only
the string comes from the reference. That string is flattened textContent:
every text node in the target's subtree, in document order, no markup carried
across, so a target painted in six fills at three sizes with a `dx` halfway
through still lends one plain line in the tref's style. Internal hrefs go
through `doc.byId`; the `suite/images/` target takes the file-open path step
11 built for `use` - resolve, read, parse, look the fragment up in that other
arena. An href-less tref, a bare file name with no fragment, a dangling
fragment, a non-SVG file and an unreadable file all contribute nothing, and
the splice never paints the target: that is painted only where the document
itself puts it - `<defs>` or `display="none"` in these files - which is what
makes every row hinge on the borrowed string.

Of the five rows: text-tref-01-b 948 -> 602, -02-b 1,025 -> 767, -03-b 932 ->
462, text-align-04-b 2,693 -> 2,677, and text-ws-03-t 5,626 -> 5,470, which
threads four trefs through `xml:space`. The borrowed text is normalized under
the *tref's* `xml:space`, the same reading the run model takes for a tspan.
-01-b's crop says the external sentence lands where the reference puts it:
green ink 262x33 at 12,17 against the reference's 261x32 at 13,18, and what
is left of that 602 is the glyph-shape ceiling every text row pays.

-02-b keeps half its AE, and the reason is honest. Its second href names
`<bar id="world">World</bar>` inside `<foo xmlns="http://example.org/foo">`,
and parser.d leaves an element in any other namespace out of the arena with
its whole subtree - the deliberate reading of §7.4's "included in the DOM but
otherwise ignored", asserted by the parser's own unittests. A tref is the one
place where that character data has a rendering meaning, and the test's other
href, `#hello`, does resolve: the `<text>` inside `<foreignObject><svg>`
stays in the SVG namespace, so the "outside the SVG document fragment" half
the test is named for is covered. The `foo:` half wants a second registry,
ids of dropped subtrees mapped to their flattened text, so they can be found
without a foreign element ever being walked. Recorded, not chased.

Step 30 landed the white space a text content element holds (SVG 1.1 §10.15).
The cursor parsed with `No.preserveWhitespace`, the library default, so a
whitespace-only text node between two elements never reached the arena and the
leading gap of a node opening right after a start tag went with it: at 12 px,
`Hello <tspan>outside</tspan>` came out glued at 72 where the spec's reading
is 75. §10.15 defines that whitespace over the element's whole character data,
so the arena keeps the nodes now and `Yes.preserveWhitespace` is what lets
them through; the renderer already paints nothing for character data outside a
text content element. Four containers read "has children" as "has content",
and character data alone is not content once a container can hold nothing
else: the clip-path, mask and filter href chains in render.d and pattern.d's
content fallback ask `Document.hasElement`, and the parser's whitespace-only
`<clipPath>` unittest pins the same distinction.

Two details of the spec's own order of operations carry the step, and each was
paid for against a row on the way. Newline removal comes *before*
consolidation: a line break is not a space, so a `<tspan>` closed at the end
of a line and the next opened at the start of the next, with nothing but a
break between, are one word, and the gap in the references comes from the
indentation that surrounds the break. Reading a bare break as a space costs
text-altglyph-01-b 1,860 AE - its `<altGlyph>` lines are flush left - which is
why that row still reads 4,185, its value before the step, and not 6,045. And
consolidation spans the character data as one string, so
`<tspan>Hello </tspan><tspan> outside</tspan>` is one gap. The two halves
meet at a run boundary rather than inside a buffer, so `layoutText` carries
"the concatenation so far ends on a space" from run to run; a run the trim
consumes whole has to leave that flag set, or the space in front of the run
after it survives as a second gap. text-tspan-02-b's green sentence - a
`</tspan>`, a line of indentation, and a `<tspan>` opening on a space - is
that case.

The rule the plan did not have: a chunk boundary is a line boundary, and the
white space that trails a line or leads the next renders nothing. A run
carrying an absolute `x` or `y`, or riding a `textPath`, restarts the chunk
(§6.2), and SVG's line model with CSS Text's segment adjustment drops the gap
at one. Left in, the space between two positioned tspans rides in the anchored
width of the chunk before it, and a centred caption sits half a space left of
the point that centres its letters; the first attempt at this step paid +17 AE
on filters-displace-01-f for it.

`xml:space="preserve"` reads the same characters the other way round -
newlines and tabs become spaces, nothing consolidates, neither bound is
trimmed - and it is the whole-element reading that makes that visible. Each
`<tspan>` of text-tspan-02-b's `rotation_values` block opens on a newline, and
under `No` the newline went with the start tag; the annotation rows sit a
space further right in the references than they did here.

Twelve rows moved and none moved up: 3,070,400 -> 3,064,573 AE. The two
whitespace files lead, text-ws-02-t 9,712 -> 7,525 and text-ws-03-t 5,470 ->
5,046. Then the multi-`tspan` labels the consolidation realigns:
text-deco-01-b 2,291 -> 1,369, text-align-03-b 2,962 -> 2,270,
text-align-04-b 2,677 -> 2,214, text-tspan-02-b 4,005 -> 3,741,
text-tspan-01-b 1,290 -> 1,198 and text-dom-01-f 3,520 -> 3,517. Four rows in
the interact category move for the same reason, their captions being
positioned tspans: interact-pevents-08-f 1,034 -> 834, -09-f 1,118 -> 919,
animate-interact-pevents-03-t 1,108 -> 917 and -04-t 1,193 -> 1,003.

Step 31 (`altGlyph`, §10.14) landed. The element is a text content child, so
its run model is the tspan's - its own x/y/dx/dy, its own computed style, and
the character data after `</altGlyph>` back with the parent; what it adds is a
list of glyphs standing in for that character data. `SvgGlyph` keeps the
element's `id`, because that is the name an `altGlyph`/`glyphRef` href uses;
an href landing on a `<glyph>` is the whole substitution. An `altGlyphDef` is
read §10.14.2's way: bare `glyphRef`s are the substitution only if every one of
them resolves, `altGlyphItem` candidate sets are tried in document order until
one is complete, and nothing resolving leaves the run's list empty - an empty
list *being* the fallback the spec asks for, the character data painting as if
there were no `altGlyph` element at all.

Two readings the references settled. A substitute comes from wherever it is
defined, not from the face `font-family` selects: text-altglyph-03-b puts
`EmbeddedSerifBold`'s glyphs into a run whose family is `EmbeddedSans`, so a
substitution carries its owning font with it and the layout scale is taken per
slot - `fontSize / slot.font.upem`, with that font's `horiz-origin-x/y` - in
both passes, rather than the run face's scale applied once to the line. And an
`altGlyph` with nothing inside paints nothing: what gets replaced is character
data, and with none there is nothing to replace. That is the reading the
captured PNG agrees with, even though the test's own hand-written "Expected"
cell shows the serif `a`: -03-b is a draft (`status="created"`) whose XXX note
records that the no-character-data subtests were removed from -02-b, and every
"Actual" cell of those rows is blank in the reference.

Only same-document fragments resolve. `glyphname` and `format` name a glyph in
one of the CSS2 font formats, and no such file loads here; a non-fragment href
leaves the document, and the font store holds no external glyph. Both fall back
to the character data. `rotate` (§10.14.1 gives the element one) waits for the
text list below.

Three rows moved and none moved up: 3,064,573 -> 3,061,812 AE.
text-altglyph-01-b 4,185 -> 2,204, where HAPPY and SAD are the substituted
happy/sad faces and what is left is HappySad's outlines being rasterized -
249 AE on the HAPPY band, 557 on the SAD+SASSY band, 120 on the revision line.
text-altglyph-02-b 1,002 -> 612, most of it the test frame's stroke: crop the
frame ring out and 194 AE of header and footer text is what is left.
text-altglyph-03-b 5,716 -> 5,326, and masking its DRAFT band leaves 580: that
band is the ceiling on the row, because the reference was captured without the
`<g id="draft-watermark">` the file still carries uncommented.

Step 32 (the text `rotate` list, §10.2/§10.4/§10.5) landed. A rotate value is
not a placement: §10.2 defines it as a supplemental rotation *about the current
text position*, so nothing about the line moves - every advance, every x/y/dx/
dy list, the anchor shift of §10.11, the pen handed to the next run, all of it
runs as though the attribute were absent - and only the outline is turned, about
the point on the baseline where its character begins. On a path the value rides
on top of the tangent turn step 28 takes from the path, about that same point:
text-text-07-t's and -09-t's "Both Together" rows are position lists *and*
rotate, and their letters fan off the line the lists set.

The numbering is what needs the tree. A list indexes the characters "of this
element or any of its descendants", so the count is absolute inside the subtree
of the element carrying the list, each character takes its angle from the
nearest element around it that has one, a short list repeats its last value and
a longer list's spare values are never read. That chain cannot be settled during
the walk, because §10.15 decides which characters exist at all: the numbering is
over the string layout sees, so every text content element opens a scope in
`element` and the matching case in `closeElement` closes it, and `layoutText`
walks the chain after the whitespace passes. One scope id per run carries it,
because a run never straddles the element that opened it - text after a
`</tspan>` starts a fresh run, and a fresh run takes that element's parent.
`rotate=""` and a malformed list are no list at all: the nearest ancestor above
answers for those characters instead.

§10.7.1 says what "the glyph" is when one character becomes several outlines,
which is step 31's substitution exactly: the advances between them live in the
rotation's temporary coordinate system. An `altGlyph` holding a two-glyph
`altGlyphDef` at `rotate="90"` therefore puts the second bar *under* the first,
with one angle for the whole substitution - its first character's, §10.14.1 -
while the pen still walks the page's x axis, rotate having no say over the
current text position.

Four rows moved, one of them up: 3,061,812 -> 3,057,076 AE. The two reference
fans, text-text-07-t 1,344 -> 462 and text-text-09-t 1,297 -> 455, and
text-tspan-02-b 3,741 -> 726, the nested case: its red row is one 55-value list
written on the `<text>` and its green row the same turns re-written over
child1..child5, and both now land on the annotation numbers the test prints
under each glyph. What is left in those three is the letterforms, the frame ring
(40 AE on each band it crosses) and -02-b's `$Revision: 1.10 $` line, 441 on its
band, which the reference spells differently.

Step 33 (the predefined entities and the character references, XML §4.1/§4.2/
§4.4.7) landed: a reference resolves on the node it stands on. `attrs()`
decodes each attribute value as it files it, and a text node is decoded as it
is adopted, so `AT&amp;T`, `&#8721;` and `y="&#49;"` reach layout as the
characters they name and not as the bytes the author typed. The pass runs over
the node, never over the source text - the line step 14 drew for the general
entities still holds: `&lt;text id="no"/&gt;` inside a `<title>` mints no
element, and animate-elem-40-t's `x/y on &lt;use&gt;` stays one label, now
spelled the way its reference paints it (2,324 -> 1,556). A CDATA section is
the one place a reference does not exist (XML §4.2), so the cursor runs
`No.conflateCDATA` - the library default folds a section into the character
data around it, and a folded section would stop meaning anything - and the
cdata case adopts its content untouched: `<![CDATA[&shape; &amp; &#65;]]>`
keeps what was written. One pass over the node is also why struct-frag-06-t
still paints its own demo line `(&amp;#x41)= A` as `&#x41;` rather than as `A`.
One decoder now serves the document: css.d's `xmlUnescape` and fonts.d's
`entityDecode` are gone, because a `<style>` body is character data and a
`<glyph unicode>` value an attribute value, and both have been resolved before
either module sees them. §20.4 says outright that a glyph's characters are
usually written as character references, and the suite's font fixtures mean it:
SVGFreeSans-ISO-8859-1.svg carries 623 `&`, SVGFreeSansOblique-Lat1.svg 100
`&#xNN;`.

That is where the three rows up come from. With `unicode="&#x22;"`, `&amp;`,
`&apos;` and `&#x21;` resolved, those fixtures answer their own `" & < > ' !`
cells with the declared face's glyph instead of a host fallback, and
styling-css-05-b pays +2 (1,467 -> 1,469) for an italic exclamation that now
comes from SVGFreeSansOblique - that is the §20.6 map, and the archived
reference predates it. animate-elem-77-t +76 is its three header labels, now
`<text>`, `<g>` and `<a>`: of the 1,271 pixels that moved, 25 match its
reference that missed it before and none the other way, and the row's 166 K is
the white-page ceiling below. text-dom-04-f +298 is the same mechanism landing
on a row whose text was already in the wrong place (ceilings).

46 rows fell, three rose, and the total is down 13.2 K. text-ws-02-t 7,525 ->
6,369 and -01-t 6,112 -> 5,277 for the `&amp;` inside their `<text>`;
animate-elem-37-t/-39-t/-36-t -963/-956/-683 and struct-use-01-t -950 for the
`&lt;animateTransform&gt;` and `&lt;rect&gt;` labels over each panel;
struct-frag-06-t -799; fonts-elem-05-t -598 and -06-t -545;
painting-marker-03-f and -04-f -580/-592. And coords-transformattr-01-f, which
used to *error*: its transform lists separate the functions with
`&#x0020;`/`&#x0009;`/`&#x000D;`/`&#x000A;` references, and those are now the
white space §7.3 says they are, so the row went ERROR -> OK at 613. Suite total
3,057,076 -> 3,043,913.

Step 34 is §14.4's reading of a mask's colour half. That half is a luminance,
it is taken in the space `color-interpolation` names on the `<mask>` element,
and the weights are the ones §14.4 borrows - "as defined in the `feColorMatrix`
filter primitive", §15.10's `0.2125 0.7154 0.0721` row - where the mask code
had the Rec.709-rounded `0.2126 0.7152 0.0722`. `filter.d` already carried that
row for `luminanceToAlpha`, so it is one shared `lumCoefs` now rather than two
near-copies. The property gets the read §11.3 gives it on a paint server: down
the mask's own `href` chain, never from the referrer, so a
`<g color-interpolation="linearRGB">` around the masking shape changes nothing
and a template carries the answer with it. Under `linearRGB` a mask pixel
leaves storage through the same un-premultiply and the same piecewise curve the
§15 chain uses, is weighted, and only then meets alpha - "the computed
luminance value is multiplied by the corresponding alpha value". That order is
what the unittest pins: one opaque `#808080` square masks to 128/255 under the
sRGB reading and 55/255 under linearRGB, and the same grey at `opacity="0.5"`
to 64 against 28.

The suite cannot show the branch, and the reason is worth keeping. Exactly two
rows name `linearRGB` on a `<mask>` (masking-mask-01-b, masking-intro-01-f),
and every mask among them paints white or a pure primary at full intensity -
luminance 1, 0.2125, 0.0721 - which are the same numbers on either side of the
curve, because the decode leaves 0 and 255 where they are. Strip the attribute
out of either file and the render is byte-identical (`magick compare` AE 0), so
masking-mask-01-b holds at 845 no matter what the read says. The one row that
does move, masking-intro-01-f 611 -> 613, moves from the coefficients alone: on
the red-on-blue `AA` ring of its mask the swapped row is worth a few hundredths
of a byte, enough to flip a rounding boundary or two. Accepted and rebased like
the step-33 rows - the spec names §15.10's numbers, and an archived capture
cannot settle ±1/255. Suite total 3,043,913 -> 3,043,915.

Step 35 is the white space *inside* an attribute value, which is two rules and
not one. XML 1.0 §3.3.3: by the time a value reaches the application each
*literal* tab, carriage return and line ending it was written with has become a
space, and §2.11 folds a CR/LF pair to one line ending first, so a pair is one
space and not two. A character reference is character data and §3.3.3 leaves it
alone, so `&#10;` keeps the newline it names - which is why parser.d's
`normalizeAttrWS` runs over the source text and step 33's `decodeRefs` runs
*after* it; normalize the other way round and a written-out newline is erased.
SVG §7.1 supplies the other half: space, tab, CR and LF are one thing, white
space, in its own attribute grammars, so the newline a reference leaves behind
still separates two numbers.

The damage was in the number lists. Eight filter primitives split theirs with
`splitter(value, " ")` - one space, not a run of white space - so a value
written across lines, or indented with a tab, or carrying a double space,
yields an empty item; `to!float` throws on it; the primitive is disabled. And
§15.1's answer to a broken primitive is transparent black, so the filtered
element is simply missing from the page, with nothing in the harness's `.err`
file to say why. `numList` in render.d splits on a whitespace run instead,
which is what `parseDash` and the length lists already did.

`filters-conv-03-f` is the row that shows it. It writes both sharpen kernels
across three lines with tab indentation, so both convolves were disabled and
its middle panel - the SMIL one, whose frozen
`<set attributeName="in" to="passimg">` moves the convolve from the squid to
the bird - painted nothing. Read the list properly and that panel is the
sharpened bird its pass criteria ask for: 1,486 -> 334. The panel to its left
holds at 2,216, because it carries no filter at all and its answer is the
`<script>` repointing `img.href.baseVal` at the bird. The one to its right
goes 1,486 -> 2,300: its convolve now runs, but stays `in="SourceGraphic"` -
the script would have set `prim.in1.baseVal` to `passimg` - so we sharpen the
squid where the reference sharpens the bird. That is the scripting ceiling the
ceilings list already carries, now reached by sharpening the wrong picture
rather than no picture. Row 6,095 -> 5,757, and nothing else in the suite
moves: 15 files hold a literal line ending or tab inside a quoted value, but
17 of those are `xlink:href` base64 data URIs folded
at 76 characters and already handled by `base64Payload`, then 10 `d`, 4
`points` and 3 `transform`, whose grammars already treated a newline as white
space, and one each of `status`, `onload` and `height`, which are script. A
five-cell probe - one 100 px lime square per spelling of the separator - reads
0.8576 over the cell for a single-line kernel and now also for a literal
newline, a literal tab, `&#10;` and `&#9;`; all four of those read 0 before,
which is an empty panel.

One bug fell out of the `&#9;` cell. `refCodePoint` required three characters
before the `#`, which rejects a one-digit decimal reference, and `&#9;` - the
tab - is two characters, so it named nothing and stayed written out like an
undeclared entity. No suite file writes one (coords-transformattr-01-f spells
its tab `&#x0009;`), so no row moves, but §4.1's Char production admits tab,
newline and carriage return. Suite total 3,043,915 -> 3,043,577.

Step 36 is §15.17's edge box. `edgeMode` is defined against "the boundaries of
the 'in' image", and ours were measured against the raster - the offscreen the
chain works in, which is device-aligned and as wide as the canvas. So
`duplicate` clamped to the canvas's first column and `wrap` joined the canvas's
far edge, both of them transparent padding: outside the picture every mode
answered zero and the mode made no visible difference at all. `convolve` now
takes the input image's box next to the raster, the same box `feTile` already
carries for its tiling, and the chain resolves it the way it resolves any
input - `namedSub` for a named result, the filter region for SourceGraphic,
which §15.5 has already region-clipped.

The probe says it plainly: three squares, a region the size of each, and a
kernel with one tap on the pixel to the left. Their left columns used to come
out transparent under all three modes; now `none` leaves it transparent while
`duplicate` repeats the edge and `wrap` joins to the far side, both lime at
alpha 255. A second probe, with the region twenty pixels wider than the square,
keeps the square's own left column transparent under every mode - correctly,
because there is padding there and not image: with `in="SourceGraphic"` the
image is the region. In `filters-conv-05-f`, whose pass criteria read "if they
all look the same the test has failed", the three panels went from
pixel-identical to 200-219 differing pixels between each pair and the row gives
up 292; `filters-conv-01-f`, which spells `duplicate` out on one panel, gives
up 205.

Two bugs, one found through the other. §15.17's initial value for `edgeMode`
is `none`; our parser reached for `duplicate`, and had no branch for the word
"duplicate" at all - the spelling worked only because it was the default.
Fixing the initial value before adding that branch made `filters-conv-04-f`
worse by 1,052 and `filters-conv-02-f` by 53: neither names an edge mode, and
the old default had been quietly behaving like `none` because a clamp at the
canvas edge lands on padding, which is what `none` wants. Both rows are back
at their step-35 values, and what the fix really buys is that the two spellings
now mean different things. Suite total 3,043,577 -> 3,043,080.

Step 37 is §17.3.2, the viewer's own URL. Nothing in the renderer had ever
held an address: `<view>` elements parsed, registered an id and stayed
inert, and the outer `<svg>`'s view attributes always won. The CLI now
splits the first '#' off its file argument - read, base directory and the
PNG's name all use the path without it - and hands the rest to `renderSVG`.

A bare name that names a `view` displays that element's *closest ancestor
`svg`*, the view's attributes overriding that element's - and only the ones
the view actually carries. A view naming just a viewBox leaves the
element's own `preserveAspectRatio` standing, which is how a square viewBox
in a document that says `none` still stretches to 100x50 while the same
view with `meet` written on it centres at +50,0 instead. If that `svg` is a
nested one, §17.3.2 displays *it* in the viewport: the renderer re-roots,
so the nested element's x and y, its ancestors and everything beside them
are out of the picture, and the canvas is that element's own 100x50. The
arena is sealed immutable, so the override is a copy of one element's
attributes - which is what the rule means: the fragment overrides the
element for this viewing, not the file.

`#svgView(...)` spells a view out instead: the five parameter types in any
order, ';' between them - or `%3B`, the url-escaped separator the spec adds
so an animated list of IRIs keeps its semicolon - and a comma inside one
attribute, because "spaces are not allowed in fragment specifications". A
repeated type ("each type may only occur at most one time"), an unknown
name or a viewBox that is not a rect makes the fragment not a correctly
formed SVG fragment identifier at all, and it lands with any other
element's id and every unknown id at the fourth rule: the `svg`'s own
attributes. Falling back instead of failing matters here - `setupRoot`
enforces a positive viewBox, and a mistyped fragment is user input, not a
broken document.

Three of the five parameters are parsed and then dropped, on purpose.
`zoomAndPan` and `viewTarget` are interaction - §17.3.4's highlight is a
CSS `:target` rule this engine does not match - and `transform(...)` is in
the production while §17.3.3's `view` element carries no `transform`
attribute for it to mean, which is how §17.3.2 defines the parameters.
`#xywh=x,y,w,h` is not in this grammar either: it is the SVG Tiny 1.2
shorthand and the spelling people type into an address bar, so it is taken
for the viewBox it is. `xpointer(id('MyView'))`, which §17.3.2's prose
shows once, is not in the production, and stays unimplemented.

The AE column cannot move - the harness hands the CLI bare files - and the
526 rows came back byte-identical, which is the check this step has. The
probe carries the evidence: a 200x100 canvas whose outer element says
`preserveAspectRatio="none"`, two views (`sq` naming only a viewBox,
`sqmeet` naming `xMidYMid meet` too), and a nested `svg` of 100x50 holding
a third view. `#sq` stretches to 100x50, `#sqmeet` centres at +50,0,
`#nested` renders a 100x50 picture with the outer rect gone, and
`#svgView(viewBox(0,0,50,50);viewBox(0,0,10,10))` is the document's own
25x25 at the origin again.

Step 38 is §15.18, and `feImage` had been reading only the first half of
its own paragraph: "If the 'xlink:href' references a stand-alone image
resource such as a JPEG, PNG or SVG file, then the image resource is
rendered according to the behavior of the 'image' element; otherwise, the
referenced resource is rendered according to the behavior of the 'use'
element." A PNG href gets a viewport and a `preserveAspectRatio` fit; an
href starting '#' went through the same file resolver, which answers
nothing for a leading fragment, so the primitive returned transparent
black. `filters-composite-02-b` is built entirely out of that second half
- twelve filters, two `feImage`s each, aimed at `path`s in `<defs>` - and
all twelve of its triangle pairs were missing.

The fragment now resolves by id and the element is painted where it
stands. No viewport, no fit, no `preserveAspectRatio`: §15.18 sends that
case to `use`, and none of the three is part of `use`. The current user
space is the scratch canvas's matrix, the plain parent CTM the
SourceGraphic snapshot used, so the referenced triangle lands exactly
where the filtered element's own geometry would have. `x`, `y`, `width`
and `height` stay what §15.1 says a primitive's are - the subregion, a
clip on the output, never a placement - so `feImageRect` still computes
the box, `clipTo` still applies it, and the box still goes into the
subregion record the next primitive reads for its edge measurement
(§15.7.3).

`use`'s broken-reference rules arrive with it: an id that names nothing,
an element with `display="none"`, one whose conditional attributes fail
and a target already on the instance stack all leave transparent black.
The stack check is what keeps a self-referential chain finite - an
feImage aimed at the very element whose filter is running would otherwise
recurse to the depth cap. A `symbol` or `svg` target paints as its
content in the current space rather than as the nested viewport `use`
would give it: the fit needs a synthetic `use` element, the arena is
sealed, and the suite never asks.

Offscreen, canvas-sized, device-aligned. `referencedRaster` paints into a
fresh bitmap at the chain's matrix and hands it to `rasterFrom`, because
every other raster in a chain is canvas-sized and region-clipped, and a
bbox-sized one would leave each later primitive doing arithmetic against
a different origin.

One row moved, and it is the only row that could: `filters-composite-02-b`
13,882 -> 2,174, since the suite's `feImage` hrefs are 24 element ids, all
in that file, and 37 image files everywhere else. The 2,174 that stays is
diffuse - the strongest difference clusters are bands 43-89 wide and
18-24 tall, the shape of text baselines and triangle edges rather than a
panel still missing. Suite total 3,043,080 -> 3,031,372.

Step 39 is §17.3.2 a second time, on a link out of a source document
rather than the viewer's own address. `resolveHref` had been dropping the
'#...' tail of every href before the renderer looked at it - right for a
file name, wrong for the IRI. The rules are the same four as step 37's: a
`view`'s id, `svgView(...)`, `xywh=`, and anything else falling back to the
element's own attributes; what changes is that §17.3.2 writes them for a
URL reference *to an SVG image*, and `<image>` is that case. An `<image>`
aimed at a file with any of the three spellings after its '#' showed the
file's own view instead.

`svgImageBitmap` takes the fragment as a second argument and runs it
through `viewFragment`, the same function the CLI's own URL goes through;
all that differs is where the IRI came from. `imageElement` keeps the raw
href, splits at the first '#' and hands the tail down, because
`resolveHref`'s job is to answer *which file* and a file name has no
fragment in it. A '#' with nothing after it is the empty fragment, the
same as none.

Re-rooting matters more here than it did for the CLI, because this
sub-renderer's canvas *is* the image's intrinsic size. A `view` inside a
nested `<svg>` makes that element the picture: its own `width`/`height`
become the raster the `<image>` element's viewport then fits, and the rest
of the referenced document - its other children, its background - is not
in the picture at all. Probed against an external 200x100 page carrying a
red 50x50 at the origin and a nested `<svg>` at 100,50 sized 100x50 with a
`view` naming a 25x25 box: with no fragment the image reads red
x0..49/y0..49 and blue x100..199/y50..99; with `#nv` the red is gone and
the blue, met into the nested element's own 100x50, runs x51..199 at full
height; and a `svgView` naming a 50x50 corner puts the red at x50..149
full height with the blue outside that region entirely.

`use` stays out of it. §5.6 says its fragment "identifies a fragment of
the currently referenced SVG document" - an element id - while §17.3.2's
rules belong to an IRI that locates a document, which is what `<image>`
does and what `feImage` will do when it learns to read an SVG file. A
`use` aimed at an element id is untouched; one aimed at a `<view>`'s id
paints the `view` element, which carries no renderable content, and an
href spelling out an `svgView(...)` spec names no element at all and is a
broken reference. Those are §5.6's readings, not holes in this step.

No row moves, and one row is worth naming for why not. `struct-image-12-b`
is the only test in the harness with a '#' on an `<image>` href, and it is
the negative case - "image elements can't reference elements in an svg
file", an href of '#svg-root-circle' at a `<defs>`-nested `<svg>`, which
must not display and does not. Every other fragment in 526 files sits on
an `<a>`, a font href or a `use`/`tref` element id. The gate came back
byte-identical, and the unittest pins the re-root, the `svgView` spelling
and the three fallbacks - an id nothing carries, a degenerate viewBox, an
`xywh=` with a zero box - against a real file on disk.

Step 40 is the half of §15.18 that step 38 left behind: "If the
'xlink:href' references a stand-alone image resource such as a JPEG, PNG
or SVG file, then the image resource is rendered according to the behavior
of the 'image' element". JPEGs and PNGs have always gone down that
branch; an SVG path went down it too, into `loadSVGImage`, and that
decoder holds no SVG, so the primitive returned an empty raster and the
filtered element vanished - while `<image>`, two sentences of the
specification later, renders the very same file without trouble.

The primitive now dispatches the way `imageElement` does: a resolved path
ending `.svg` goes to `svgImageBitmap`, everything else to the bitmap
decoder. Nothing else in the case moves, and that is the point - the
placement rect is the image's viewport, `viewFit` fits the natural pixels
into it under the element's own `preserveAspectRatio` ("The processing of
the 'preserveAspectRatio' attribute on the 'feImage' element is identical
to that of the 'image' element"), step 38's subregion still only trims the
output, and `f.linearRGB` still decides how the raster is decoded into the
working space.

The fragment rides along, and it belongs there: §17.3.2's rules are
written for an IRI that locates an SVG document, and an `feImage` href is
one. `x.svg#view-id` re-roots the referenced document to a nested element
and *that* picture is what the rect fits, exactly as it is for an
`<image>`. The loop guard is `svgImageBitmap`'s own, so an SVG that
reaches itself through an feImage stops at the nesting cap and paints
nothing instead of recursing.

Probed at 200x100 against the external file step 39 uses, with the filter
region over the whole canvas: a rect covering the region lands the file
1:1 - red x0..49/y0..49, blue x100..199/y50..99. A rect at 50,25 sized
100x50 meets the 200x100 natural pixels into it, and the red moves to
x50..74/y25..49 with the blue at x100..149/y50..74. `#nv` re-roots to the
nested viewport, so the red is gone and its blue runs x51..199 at full
height; `#svgView` naming the 50x50 corner puts the red at x50..149 full
height and leaves the blue outside that region. The filtered element's own
rect is replaced in every case, and an href at a file that is not there
paints nothing at all.

Suite: byte-identical, and it could not be otherwise. The harness's 37
`feImage` file hrefs are PNGs and one JPEG, its 24 element-id hrefs all
belong to `filters-composite-02-b`, and nothing aims an feImage at an SVG
document. The unittest covers the file fitted to the whole region, a rect
of its own with the meet centring and the subregion clip, a `#view-id`
written inside the referenced file, and a file that is missing.

Step 41 (the stale § numbers) landed. The sources cite the spec by section
number in 547 places, and 117 of those cites named a section that does not
say what the comment attributed to it; rewriting them touched 122 comment
lines over nine files. Every number was matched against the local SE's
expanded table of contents - 565 numbered sections - and each flagged line
was read against the section it names before being moved.

The bulk of the moves are the ones the "Up next" notes have carried since
step 6. Text layout sits at §10.4 (the per-glyph x/y/dx/dy lists and
textLength), §10.5 (`rotate`), §10.9.1 (`text-anchor`), §10.11
(`letter-spacing`/`word-spacing`) and §10.15 (white space handling), not at
§6.1/§6.1.2/§6.1.3/§16.3/§16.4 - chapter 16 is the SE's *User interface
events*. The white space character list and the comma-or-white-space
number-list separator are §4.2, which is also where the CSS system colours
enter SVG, so `color.d` and the number-list helper moved there. `textPath`
is §10.13.2 - the element, its broken-reference rule, `startOffset` - with
§10.13.3 for the layout. Markers split three ways: §11.6.2 the element,
§11.6.3 the properties, which is the half that keeps marker content
marker-free, and §11.6.4 the drawing rules, including markers painted
after the object is filled and stroked.

The element chapters follow the SE too: `image` §9.8 -> §5.7 (9.8 is a DOM
interface section), `xml:base` §5.1.2 -> §5.10.1, the initial viewport
§7.5.1 -> §7.2, the `transform` attribute §9.5 -> §7.6, radial gradients'
cx/cy/r defaults §7.5 -> §13.2.3, mask §14.1 -> §14.4 with the broken
reference rule at §14.3.5/§14.4, data: URIs §7.4 -> §17.1.2, and the
XLink-is-a-namespace-not-a-prefix rule §5.1.2 -> §17.1.5. SMIL's timing
tokens move from §5.2 to §19.2.8/§19.2.8.1, its href retargeting from the
non-existent §19.2.0 to §19.2.4, and animateMotion's supplemental translate
to §19.2.14. The filters kept a flat draft numbering: §15.6.4/§15.6.5 is
feColorMatrix §15.10, §15.6.23 is feComposite §15.12, §15.16.1 is
feGaussianBlur §15.17, §15.6.12 is feFlood §15.16, §15.4 is feBlend §15.9,
and the working-space claims - linearRGB as the initial
`color-interpolation-filters`, premultiplied inputs, the clamp on each
primitive's result - all belong to §15.7.1.

Three of them changed a claim, not only a pointer. The filter header said
the spec lets intermediates leave [0,1] and that nothing is clamped between
primitives; §15.7.1 clamps every primitive's RGBA result, so the note now
states what this code does - floats stay raw here, the clamp waits for
encode. The pattern note said the SE treats every empty or zero-sized tile
as an error; §13.3 splits it - a negative value is an error, zero
"disables rendering of the element". And a `rotate` note quoted
"supplemental to any rotation due to text on a path", a sentence the SE
never writes; it now says what §10.5 and §10.13.3 do, that the rotation is
about the current text position, so it adds onto the path's tangent.

Cites naming other specifications stay as they were: CSS 2.1 §6.4.3, CSS
§6.5.1, CSS2 §15.3.3, XML 1.0 §2.11/§3.3.3/§4.4.x, SMIL smil20 §2.6 and
RFC 4648 §3. The local copy is the SVG SE and nothing else, so those
numbers went unchecked.

Suite: byte-identical, 526 rows and the same 3,031,372 AE. A comment sweep
cannot move a pixel, which is exactly what this gate checks.

Up next - step 42, the biggest row no ceiling note has ever looked at:
`text-text-08-b` (15,072). Its panels are the fill-opacity, stroke-opacity
and `opacity` properties on `text`, handled the same way as on shapes ever
since the text era, and nothing in the roadmap has asked what the archived
reference there actually shows.


## Deferred / accepted ceilings (do not chase)

- `struct-dom` (228 K) / `types-dom` (39 K): SVG DOM and scripting
  end-states — a CLI renderer has no DOM API surface; verdicts stay as-is.
  struct-image-11-b (22 K) belongs here too: the references were captured
  after the W3C checker clicked every `<image>` (`onclick` makeGreen), so
  the correct static (blue) state can never match.
  extend-namespace-01-f (23.6 K) is the same class: its pie chart is built
  at load by ECMAScript from the `bd:` business data (`getElementsByTagNameNS`,
  then `createElementNS` arcs), so the reference is a post-script state no
  static render reaches - the foreign-namespace half of it, ignoring the
  `bd:` elements, is already right.
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
- `text-altglyph-03-b` (5.3 K): 4.7 K of it is that same band. The file is
  `status="created"` and carries its `<g id="draft-watermark">` uncommented,
  which we paint; its reference was captured without it. Mask the band and the
  row is 580 AE, so the altGlyph rows themselves are at their floor.
- `text-dom-01-f` (3.5 K), +3 at step 32: the line that carries
  `<tspan rotate="45,90">is</tspan>` is not visible in its reference at all.
  The file's DRAFT band is painted *over* it there, and the only ink the PNG
  keeps at that place is the script's own lightblue `getExtentOfChar` boxes -
  which do enclose "the diagonally rotated fifth glyph 'i'", the reading our
  rotate agrees with. Turning the pair moved 3 AE of band mismatch around;
  the geometry is right and the row's floor is the band.
- `text-dom-04-f` (12.4 K), +298 at step 33: its `<text>` asks `y="2em"` at
  `font-size="4000"` under `scale(0.02)`, and the line lands at y=22..59 while
  the reference sits at y=120..219 - 1.9 K lime pixels against its 10.7 K. That
  em reading, and the SVG-font scaling of a 4000-unit size, are the row's own
  defect and older than the entities. Step 33 only changed which glyph
  `simplesvgfont` is asked for: the content is now `abca`, U+1D352, `cb` rather
  than the twelve characters `&#x1D352;` spells out, and one more cell of a
  face already placed wrong is all the +298 buys.
- struct-image-13/14/15-f (453 K): the reference PNGs deviate from the
  tile PNGs they composite; our tiles match ground truth at AE 0 — a
  reference-suite defect, documented in the `<image>` commit message.
- struct-use-06-b (30 K) / 04-b (16 K) / 07-b (36 K): external-reference
  tests where step 11 renders to spec but the archived references do not.
  06-b's body still carries its own "external use isn't implemented, show
  red rects" fallback *under* the clones, and its reference was captured by
  a UA that showed exactly that fallback, so the correct lime external
  rect now paints over it (+6.8 K at the step-11 rebase); its second clone
  aims at the external `svg-root` itself, whose 450x450 lime square is
  scaled into that `use` element's own 122x122. 04-b's reference shows
  colored shapes no spec-correct render of the referenced files produces;
  07-b's nested-`<svg>` fit is already handled to §7.7.
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
- types-basic-02-f (8.2 K), from the step-23 sweep: its pass criteria ask for
  "six circles with the same thick green stroke visible, and no red", which is
  what we paint, and the archived PNG is the state its own description carves
  out - "if the SVG user agent doesn't support CSS styling then this test does
  not apply". Three of the six positions (the ones styled by the `<style>`
  element's `#id` rules) show the red reference ring instead of the green one
  there, 5.1 K strong-delta pixels per ring band, and the other three, styled by
  presentation attribute and inline `style`, are green in both.
- `struct-use-09-b` (8.3 K) and `struct-cond-overview-05-f` (7.5 K), both triaged
  during the step-24 unit sweep, are references of the same broken kind. 09-b's
  pass criteria want five nested rings in black/yellow/orange/purple/blue, and we
  paint exactly those at half-widths 90/80/70/60/50, while its PNG contains no
  gold, orange, purple or slateblue pixel anywhere. 05-f is the reverse: we obey
  §5.8.1 ("conditional processing attributes ... do not prevent elements from
  being successfully referenced by other elements (such as via a `use`)") so the
  three black clones hide the red decoys and no red shows, and the PNG is the
  red-decoy state the test was written to eliminate.
- `filters-turb` (163 K) / `filters-conv` (169 K): feTurbulence noise and
  convolve matrices cannot match the 2009 references pixel-for-pixel.
  filters-morph-01-f (8.4 K) belongs to the same family: its four feMorphology
  result boxes (144x117, 142x117, 130x92, 128x105) carry 10.9 K strong-delta
  pixels, and the only unit content in the file, a `12pt` label, was worth the
  158 AE step 24 took off it.
- Gradient ramps that change colour across a `stop-opacity` change
  (`pservers-grad-13-b` 2.8 K, `-05-b` 1.0 K, `-18-b` 1.1 K): the archived
  references interpolate `stop-color` and `stop-opacity` separately - step 22
  pinpoints composited blue as `139*w^2` there against our `139*w`, whole
  columns to a mean of 1.3 levels - while we interpolate premultiplied, as
  SVG 2 and CSS Images 4 §4.6 require. Ring geometry matches exactly;
  only the weighting is the reference's.
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
  161.6 K -> 5.1 K, filters-conv-05-f 153.6 K -> 7.0 K, struct-image-
  13/14/15-f 151 K each -> 5.3/5.3/6.4 K, filters-light-02-f 134.8 K -> 66,
  text-intro-06-t/-07-t 158 K each -> 22.2/22.7 K. Compositing over white
  suite-wide is the wrong lever: 3.33 M -> 73.7 M, because the other 515
  references do keep their alpha. Better of the two readings per test puts
  the suite's content floor near 1.86 M - everything still worth chasing,
  including the ceilings above, lives there.
- `masking-path-06-b` (7,905): the suite's only `clip="rect(...)"` row, and its
  reference is Batik's from-each-edge inset rather than the CSS 2.1 §11.1.2
  geometry §14.3.3 imports. There `rect(<top>,<right>,<bottom>,<left>)` are
  offsets from the top and left border edges, all four from one point, so
  `rect(10,10,10,10)` is zero-area and a conformant render paints no image at
  all. Census: we paint 68,317 opaque pixels, the reference 54,772, and the gap
  is exactly the 10-unit border of the two 200x120 image boxes; the spec's
  reading would drop all 48,000 image pixels and put the row near 35 K.
- `filters-composite-03-f` (9,647): arithmetic feComposite, including its
  FillPaint/StrokePaint inputs, is right - the identical and clamped squares
  compare at AE 0. The two that miss are semi-transparent (alpha 0.5 for
  `2F - 1.5F`, 0.6 black for `-0.5F - 0.1`) and each reference pixel is ours
  composited over white: (127,255,127) and (102,102,102), opaque. Flattening
  both sides over white collapses the row to 2,386, the AA of the three guide
  rings; the harness composites nothing, so the alpha gap stays as the AE.

## Backlog (small, opportunistic)

- Not the filters' colour space, their arithmetic: `filter.d` keeps the §15.2
  linearRGB working space already - `rasterFrom` decodes, `bitmapFrom` encodes,
  `color-interpolation-filters="sRGB"` flips the flag at `makeFilter` - and
  what looked like arithmetic in `filters-conv-03-f`'s 308x77 band was a parse
  failure, which step 35 closed. What is left of that row is two script panels
  (4,516 of it) plus 334 of sharpening the bird itself, unexamined - step 36
  moved the convolve's edge box and that 334 did not blink.
