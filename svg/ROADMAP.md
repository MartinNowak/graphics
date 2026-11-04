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
|                       | 117 cites re-checked against the SE's own      |            |
|                       | contents, and three notes rewritten to say     |            |
|                       | what the spec says (comments only)             |            |
| step 42               | a zero-length edge still has its first and     | 3.03 M     |
|                       | final vertex, so its markers paint even with   |            |
|                       | butt caps (SVG 1.1 §11.6.3)                    |            |
| step 43               | a feColorMatrix type keeps the case the spec   | 3.02 M     |
|                       | writes it in: hueRotate and luminanceToAlpha   |            |
|                       | fell to the identity matrix (§6.7, §15.10)     |            |
| step 44               | a filter's background inputs read the page     | 3.01 M     |
|                       | beneath the element, not the element itself:   |            |
|                       | the page is named before the swap (§15.4)      |            |
| step 45               | an SVG file referenced by `image` is sized     | 3.01 M     |
|                       | by the element that references it - once, at   |            |
|                       | the rate it is displayed (SVG 1.1 §5.7)        |            |
| step 46               | a PNG says in its gAMA chunk how the samples   | 2.98 M     |
|                       | were encoded, so loading one re-encodes them   |            |
|                       | onto the page's own 2.2 curve - for `image`    |            |
|                       | and feImage alike (PNG 1.2 §4.2.2.3)           |            |
| step 47               | a bare `float` field starts as NaN, not 0, and | 2.97 M     |
|                       | stroke-dashoffset's initial value is 0 (§11.4);|            |
|                       | so every dash length came out NaN-wide: a      |            |
|                       | stroke-dasharray with no dashoffset drew       |            |
|                       | nothing at all                                 |            |
| step 48               | a closepath leaves the current point at the    | 2.96 M     |
|                       | subpath's own start (§9.3.2), and `Path.close` |            |
|                       | adds no point to read back, so every relative  |            |
|                       | command after a `z` measured from a stale one  |            |
| step 49               | a smooth cubic reflects the cubic before it    | 2.96 M     |
|                       | through the current point (§9.3.2); the parser |            |
|                       | seeded the handle with the current point and   |            |
|                       | moved the parsed one instead of the first      |            |
| step 50               | 'overflow' starts at 'hidden' and applies      | 2.95 M     |
|                       | to every viewport, so an inner `svg` - and     |            |
|                       | a `use` instance of a `symbol` or `svg` -      |            |
|                       | clips what it holds to its box (§7.6.4,        |            |
|                       | §7.7, §19.4)                                   |            |
| step 51               | feGaussianBlur's 'stdDeviation' is one or      | 2.94 M     |
|                       | two numbers - x then y, and a zero leaves      |            |
|                       | its own axis sharp; the pair's counter sat     |            |
|                       | outside the loop body, so its last token       |            |
|                       | alone set both axes (§15.19)                   |            |
| step 52               | a primitive subregion takes its absent         | 2.94 M     |
|                       | sides from the filter region, not from         |
|                       | the element's own -10%/120% numbers, so        |
|                       | a flood giving only width/height sat 10%       |
|                       | of the bbox off both leading edges             |
|                       | (§15.1, §15.7.3)                               |            |
| step 53               | a clip-path or mask FuncIRI that does not      | 2.94 M     |
|                       | resolve is dropped rather than fatal - the     |            |
|                       | declaration counts as never written, so the    |            |
|                       | element paints; only a layer that resolves     |            |
|                       | and then covers nothing hides the paint        |            |
|                       | (§14.3.5, §14.4)                               |            |
| step 54               | an invisible `clipPath` child is no part       | 2.94 M     |
|                       | of the clip: §14.3.5 excludes a child made     |            |
|                       | invisible by 'display' or 'visibility',        |            |
|                       | and only the display half was honoured, so     |            |
|                       | a hidden child still clipped the whole cell    |            |
|                       | (§14.3.5)                                      |            |
| step 55               | an empty `requiredFeatures` is false, not      | 2.94 M     |
|                       | vacuously true: §5.8.3 ends by ruling a null   |            |
|                       | or empty value false, so a blank list skips    |            |
|                       | the element instead of painting it - which     |            |
|                       | is what empty 'requiredExtensions' and         |            |
|                       | 'systemLanguage' already did (§5.8.3-5)        |            |
| step 56               | an axis-aligned hairline centred on a pixel    | 2.69 M     |
|                       | boundary is one whole pixel in the captures -  |            |
|                       | their raster decides an edge by the pixel      |            |
|                       | centres it covers, ours integrates the cell    |            |
|                       | and splits it 128/127, so nearly every test's  |            |
|                       | frame paid a quarter of a pixel per side       |            |
| step 57               | a filter's primitiveUnits box is the filtered  | 2.69 M     |
|                       | element's bounding box whatever filterUnits    |            |
|                       | says: with a userSpaceOnUse region the basis   |            |
|                       | stayed empty, so oBB dx/dy and every fraction  |            |
|                       | scaled to nothing, so feOffset drew no shift   |            |
| step 58               | a group's opacity lands once, not per child:   | 2.68 M     |
|                       | the subtree paints opaque offscreen, so an     |            |
|                       | opaque child hides the ones under it, which    |            |
|                       | is what masking-opacity-01-b's four rows and   |            |
|                       | render-groups-01-b spell out (§9.2, §9.3.1)    |            |
| step 59               | every axis-aligned stroke band shifts half a   | 2.65 M     |
|                       | device pixel, not just a hairline: their band  |            |
|                       | is ours translated by half a pixel, at width 1 |            |
|                       | and 40 alike; a zero-length subpath has no     |            |
|                       | band, only §11.2's cap, and stays put          |            |
| step 60               | the nudge rides the device point, not the      | 2.65 M     |
|                       | user one: a quarter turn and an anisotropic    |            |
|                       | view fit carry it too, so the CTM need only    |            |
|                       | invert - the contour, not the matrix, has to   |            |
|                       | be axis-aligned                                |            |
| step 61               | `inherit` on a presentation attribute is       | 2.65 M     |
|                       | the parent's value: dropping the declaration   |            |
|                       | is the whole rule, and the enumerations that   |            |
|                       | reached for an initial value - linecap, -join, |            |
|                       | -dasharray - are the ones that noticed         |            |
| step 62               | the `<style>` element's `type` names the       | 2.65 M     |
|                       | language of its contents: absent or text/css   |            |
|                       | is the one sheet language this engine reads,   |            |
|                       | and one that names anything else is not a      |            |
|                       | sheet at all - not even a name like text/css2  |            |
| step 63               | the prolog's xml-stylesheet PI names a         | 2.64 M     |
|                       | sheet for the whole document - the one         |            |
|                       | the external fragment carries and this         |            |
|                       | engine never read - and its rules lead         |            |
|                       | the cascade as if written in the prolog        |            |
| step 64               | wherever a sheet can name the media it is      | 2.64 M*    |
|                       | written for it is finally asked: the PI,       |            |
|                       | style, @import, @media - all one matcher,      |            |
|                       | and the one painted medium is screen           |            |
| step 65               | the @font-face block names a font to           | 2.63 M     |
|                       | the font store, not a rule for the             |            |
|                       | page: family and src - this file's or          |            |
|                       | a file's - pick the face it registers          |            |
| step 66               | a font's declared glyph origin is              | 2.63 M     |
|                       | a record, not a shove: the accepted            |            |
|                       | 05-t sits every outline's corner on            |            |
|                       | the pen whatever the origin says               |            |
| step 67               | the scripting rows we assumed                  | 2.63 M*    |
|                       | get rendered: indicator squares                |            |
|                       | and stale captures - five rows                 |            |
|                       | join the deferred list, AE holds               |            |
| step 68               | §11.6.3 culls the miter by its own             | 2.63 M     |
|                       | ratio, 1 / sin(theta/2): joins                 |            |
|                       | tighter than ~29 degrees bevel                 |            |
|                       | at the default limit of 4                      |            |
| step 69               | stroke-dasharray entries are lengths,          | 2.63 M     |
|                       | so 10px 20px 20px dashes return;               |            |
|                       | the 300-1,500 band swept clean                 |            |
| step 70               | sweep the last unclassified band:              | 2.63 M*    |
|                       | the 100-300 rows block-scan to                 |            |
|                       | zero solid regions - all ceiling,              |            |
|                       | AE holds                                       |            |
| step 71               | working images get a device origin: a          | 2.63 M     |
|                       | region spilling off the page pads and          |            |
|                       | repaints its scratch - offset-02-b             |            |
|                       | 2,512 -> 87, total -2,425                      |            |
| step 72               | text-decoration painted: §10.12's three        | 2.63 M     |
|                       | lines ride the cascade, painted with the       |            |
|                       | specifying element's own paint - deco-01-b     |            |
|                       | 951 -> 690, 03-b +116, total -145              |            |
| step 73               | writing-mode tb-rl layout: §10.7.1 vertical    | 2.63 M     |
|                       | runs: upright glyphs ride one-em boxes with    |            |
|                       | ink centred on the baseline - 05-b 1,196 ->    |            |
|                       | 207, 06-b 2,533 -> 2,319, total -1,203         |            |
| step 74               | marker viewport overflow: §7.8 hands `auto`    | 2.63 M     |
|                       | to the user agent, and the capture and 05-f's  |            |
|                       | own pass criteria both put that column beside  |            |
|                       | visible - 05-f 731 -> 232, total -499          |            |
| step 75               | font-weight: bolder/lighter + raw numerics;    | 2.62 M     |
|                       | the keywords step the inherited number by      |            |
|                       | 200, SVG faces match exact weights - 203-t     |            |
|                       | 1,891 -> 45, total -1,846                      |            |
| step 76               | marker defining-site inheritance: §11.6.2      | 2.62 M     |
|                       | seeds marker content from the ancestors it     |            |
|                       | hangs under, never the referrer - 02-f         |            |
|                       | 1,079 -> 848, total -231                       |            |

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

\* step 64 is spec-completeness too: the suite writes no `<style media>`,
no `@media`, and three `@import` none of which carries a clause, so the
gate must stay flat by construction - 526 rows came back byte-identical
a fourth time.

\* step 67 is measurement, not pixels: the two animate-dom rows are
script-drawn indicator squares over matching pages, the two
script-specify captures were shot from revisions older than their own
markup, and `pservers-pattern-01-b`'s diff is nothing but the Arial
captions of a pattern that already matches - five ceilings confirmed by
rendering, so the 526 rows came back byte-identical a fifth time.

\* step 70 is measurement too: every 100-300 row scanned for solid
content, the scan dilating the diff's matching background 1 px inward
twice and asking for surviving 100-px components - in a band where a
row's whole diff budget is 299 pixels, no lost or misplaced element can
hide a 10x30 swatch from that, and none carries one. The lone flag,
`animate-script-elem-01-b`, is another black-to-green script indicator
square, recorded with the band. 526 rows byte-identical a sixth time.

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

Step 42 landed the marker at a degenerate vertex (SVG 1.1 §11.6.3). The
walk already gave `M 0 0 L 0 0` its two junctions, and the vertex rule
already reads marker-start at the first and marker-end at the final one.
In front of them sat a rule of our own, from the first marker commit,
with nothing cited for it: when a junction's direction came out as the
zero vector and the line caps were the default butt, the marker was
skipped - a stroke that paints no dot was taken to hide its marker too.
§11.6.3 sets no such condition: "marker-start defines the arrowhead or
polymarker that shall be drawn at the first vertex" of the shape,
marker-end "at the final vertex". `imp-path-01-f` is the suite's own
test of exactly that shape - a `path d="m 0 0 L 0 0"` and a
`<line x1="0" x2="0" y1="100" y2="100">`, stroke-width 25 both,
marker-end both - and its reference carries a 75x75 marker square at
each vertex, 11,028 blue px where we were painting none.

Orientation was the only half of the old rule with anything behind it.
§11.6.2: when the incoming and outgoing tangents produce a zero vector,
"the direction of marker is undefined" - about `orient="auto"`. That
file never asks for auto: its marker keeps the default `orient="0"`, so
its square sits axis-aligned, east and south of the vertex. Where auto
*is* asked for on a zero-length edge, a tangent of (0, 0) puts atan2 at
0 and that reading lands on the same square.

Suite: one row moves, `imp-path-01-f` 9,790 -> 5,055. What is left there
is not markers. 4,748 of it is the y=0..25 band: the file is
`status="reviewed"` and still carries an uncommented
`<g id="draft-watermark">`, which we paint and its reference does not, so
our 7,993 red px sit exactly where the reference shows the top of the
marker's own ink. The rest, ~530, is the frame ring - 12-25 AE per 25-row
band on the sides, 248 along its bottom edge, that half-pixel stroker
convention recorded under step 27. Between those two floors the two
marker squares agree.

Step 43 landed the case of a feColorMatrix `type` keyword (SVG 1.1
§15.10). The filter walk read the attribute through `toLower` before
handing it to `cmMatrix`, whose switch is labelled with the spellings the
spec itself writes - `matrix`, `saturate`, `hueRotate`,
`luminanceToAlpha` - so the two mixed-case keywords matched nothing and
fell through to the default branch, which builds the identity unless
twenty numbers come with them. The primitive ran, wrote its input back
out unchanged, and reported success. filter.d's own unittest of
`cmMatrix` never caught it because that one calls it with the exact
spelling.

§6.7 is the sentence behind the fix: presentation attributes are XML
attributes, and "keyword values, such as italic in font-style="italic",
are also case-sensitive and must be specified using the exact case used
in the specification which defines the given keyword" - the same
sentence that settles "the keyword sRGB must have lowercase s and
uppercase RGB". The value now goes through verbatim.

Asked of every other keyword the walk lowercases, the same reading comes
out clean: fill-rule and clip-rule, visibility, overflow, display, the
line cap/join/alignment sets, feComposite's `operator`, feBlend's
`mode`, feFunc's `type`, feTurbulence's `stitchTiles`, feConvolveMatrix's
`edgeMode` and `preserveAlpha` - each of those SE keyword sets is
spelled all lowercase, so lower-casing both sides loses nothing. The
mixed-case values the engine does read, `sRGB` and `linearRGB` for
`color-interpolation` and `color-interpolation-filters`, are compared
case-insensitively against the exact literal, so they were already
reaching their branch. feColorMatrix's `type` was the one value sent, by
the walk, into a branch it could never reach.

Suite: one row moves, `filters-color-01-b` 7,811 -> 2,480, and it moves
completely. Its five panels - unfiltered, `type="matrix"`, `saturate`,
`hueRotate 90`, and the `luminanceToAlpha` panel whose alpha comes only
from the matrix's A row, through `feComposite in="SourceGraphic"
in2="a" operator="in"` - each compare at AE 0 in their tight 442x24
crops, including the `#Matrix` filter's region clipped exactly to the
bbox, `x="0%" y="0%" width="100%" height="100%"`, where the file's other
three filters run -5%/-5%/110%/110%. Before the fix the first three were
at 0 and the last two at 1,155 and 4,163. What is left of the row is its
floor: ~1.9 K in its five Verdana labels, host substitution, and ~540 in
the two frame rings, 128 along the top and 258 along the bottom, the
half-pixel stroker convention recorded under step 27.

Step 44 landed the two background inputs, BackgroundImage and
BackgroundAlpha (SVG 1.1 §15.4/§15.6): what they name is "an image
snapshot of the canvas under the filter region at the time that the
'filter' element is invoked" - the page as it stood *beneath* the
element, not what the element drew. `filteredElement` puts the subtree
on an offscreen scratch first, which it must, because the chain's output
replaces the element; but it took the snapshot after that swap, so the
backdrop was the subtree and every background input was fed the
element's own paint. The page is now named before the swap
(`auto backdrop = bmp;`) and handed to `runChain` beside the source, and
`initBg()` rasterises that; nothing else in the chain moves.

The four rows that read those inputs moved: `filters-overview-03-b`
8,505 -> 6,144, `filters-overview-01-b` 3,540 -> 1,178,
`filters-overview-02-b` 8,408 -> 6,047 and `filters-background-01-f`
4,968 -> 2,680, -9,372 in all. `filters-blend-01-b` (7,422) did not
move: its one background `in=` sits on an `feFlood`, which ignores `in`.
Cropped per panel, -03-b's background pair now scores 117 and 125, which
is the floor the two Source* panels sit at (142 and 157). What is left
of that row is the paint-server pair, recorded under ceilings, about
1.7 K of watermark, frame and labels, and a few hundred along the region
edges. In `filters-background-01-f` the residual sits inside the
filtered groups - 1,954 of 2,680 across y=160..240 - and it is not an
offset: rolling the crop 1-2 px finds no better alignment, and the
band's mean colour is the reference's 64 against our 71, so it is
soft-edge drift in the blur.

§15.6 also gates these inputs: a container ancestor must declare
`enable-background` before BackgroundImage/BackgroundAlpha mean
anything, and without it the value is in error and paints nothing. That
gate is not modelled - any chain that asks gets the live page. It costs
nothing in this suite: every file that reads those inputs declares it
(`filters-background-01-f` four times, the three `filters-overview`
files once each), so the `accumulate`/`new` bookkeeping stays behind it.

Step 45 landed §5.7's sizing of a referenced SVG document.
`svgImageBitmap` drew the file on the default 480x360 page and then
fitted that raster into the element's viewport, so the fit ran twice and
the second time against the wrong aspect: `coords-viewattr-04-f`'s 30x60
`xMinYMin meet` case of a 30x40 viewBox came out at 0.5625 with an x
offset of 6.56 where the reference is 1.0 flush at x=0. `loadRefDoc` and
`renderRefDoc` replace it. The file is read once and its outermost
`viewBox` is fitted once into the *referencing* element's viewport, at
the rate that viewport is being drawn, so the raster arrives already at
the resolution it is displayed at. The referenced root's own
`x`/`y`/`width`/`height`, its `clip` and `overflow` and - unless the
element's `preserveAspectRatio` starts with `defer` - its own
`preserveAspectRatio` are dropped. `feImage` shares the code: §15.18
says its `preserveAspectRatio` is processed as `image`'s, and its
placement rect already arrives in the raster's own units.

Two neighbouring viewport rules came with it, both §7.5. A file that
declares no width/height is 100% of the container, not a 100-unit
square, which is what keeps `struct-image-16-f`'s two-leg chain of
size-less files filling its page instead of letterboxing a 100x100 one.
And a file with no `viewBox` has nothing to fit, so its user units land
one for one in the user space that references it and the viewport is
only a clip: that is why `struct-image-18-f`'s reference shows a quarter
of a 50x50 circle through a 25x25 viewport, not a small whole circle.
All three cases - fit, 100%, clip - are pinned beside the `defer` case
in the §5.7 unittest.

Four rows moved and none moved up: `coords-viewattr-04-f` 5,941 ->
1,610, `struct-image-18-f` 2,613 -> 793, `struct-image-19-f` 1,312 ->
1,248 and `masking-path-06-b` 7,616 -> 7,584, -6,247 in all - 526 rows,
3,005,687 AE. Cropped per case, 04-f's thirteen images now score 37-189
each, from 69-522; what is left of that row is its labels, the frame
ring and the antialiasing along each fitted edge. `struct-image-18-f`'s
793 is 190 along the quarter's arc and about 600 on the frame ring - 325
across the top, 298 along the bottom with the label - the half-pixel
stroker floor recorded under step 27.

Step 46 landed PNG's `gAMA` chunk. The decoder in use is stb's and it
parses no chunks at all - `grep -r gAMA src` is still empty - so
`pngFileGamma` walks a file's own chunk stream: IHDR, then the chunks
before the first IDAT, which is where the ancillary colour chunks live,
and it reads the 4-byte fixed-point gamma there. It answers 0 when the
file also carries `iCCP` or `sRGB`, because PNG 1.2 §4.2.2.4 and
§4.2.2.5 rank both ahead of `gAMA` and there is no ICC reader here to
honour either; such a file is read as sRGB, which costs nothing in this
suite, since every profiled file in it carries a profile that sits near
45454 anyway. `color-prof-01-f` (6,811) therefore still waits on a
profile reader, not on gamma.

`applyPNGamma` folds the two curves into one table. A PNG holds samples
meant for a display of gamma `100000/gAMA`; the page displays at 2.2,
so a sample leaves the file's curve and enters the page's as
`out = (s/255)^(100000/(2.2*gAMA))` - one power, no round trip through
linear. Only the three colour bytes move: alpha is not stored in a
file's gamma. Both loaders run it, `loadDataURL` and `loadSVGImage`, so
the `image` element and every filter input that reads a file arrive
already in the page's space and share one cached raster. The five
ramps of `struct-image-03-t` pin the arithmetic point for point: 128
stored at gAMA 1.00 gives 186, 2 at 1.00 gives 28, 64 at 2.00 gives 85
and 64 at 0.30 gives 31 - and 186 is what the reference shows for all
five bars.

Nineteen rows moved, -26,401 in all - 526 rows, 2,979,286 AE. The
three big ones are `struct-image-03-t` 9,296 -> 463,
`filters-displace-01-f` 13,396 -> 2,387 (its `feImage` input is
`sphere.png`, gAMA 100000) and `struct-image-09-t` 2,549 -> 463. The
PngSuite files behind `filters-composite-04-f` and `-05-f` (801 and
1,303 -> 604 each), `filters-conv-03-f` -227 and
`filters-image-03/04/05-f` -66/-50/-78 come from the same 100000-gamma
`basn*` inputs, and `struct-image-13-f`/`-14-f` -1,280 each and `-15-f`
-291 are those tiles composited. Two rows went up and both are
accepted: `filters-image-02-b` +39 and `filters-blend-01-b` +4 both
read a gAMA 45000 picture, whose exponent is 1.0101 - almost identity,
and the reference behaves as though it were exactly identity, so
honouring it moves a few mid greys one step.

Step 47 fixed the default of `stroke-dashoffset`. The style struct held
a bare `float dashOffset;`, and D seeds a float field with `float.init`
- NaN. The source warns about that trap at three other places already;
this was the last bare float field in the module, and a grep for one is
empty now. `svgDash` opens the pattern at `offset % L`, so the first
dash came out `intervals[0] - NaN` wide, that failed the `seg > 0`
test, and the dash pass handed the stroker an empty path: a
`stroke-dasharray` with no `stroke-dashoffset` drew nothing at all, on
any shape. §11.4's initial value is 0, so that is what the field says
now. The rasterizer unittest had pinned the dash for six steps without
catching it, because the element it draws also writes
`stroke-dashoffset="0"`; it draws the pattern twice now, with the
attribute and without.

Fifteen rows moved, -9,338 in all - 526 rows, 2,969,948 AE. Eleven
down: `animate-elem-35-t` 8,353 -> 4,296, `painting-stroke-06-t`
4,058 -> 1,626, `painting-stroke-09-t` 2,299 -> 642, the three
`filters-overview` files -404/-414/-413 each, whose page frame is
dashed, `animate-elem-41-t` -46, `-78-t` -29, `-33-t` -5 and
`interact-pevents-07-t` with `animate-interact-pevents-02-t` -2 each.
Four up, +123 together: `interact-pevents-09-f` +38,
`animate-interact-pevents-04-t` +37, `interact-pevents-08-f` +24 and
`animate-interact-pevents-03-t` +24. All four are hairline
`stroke-width="1"` frames dashed `1,1` or `3,3`, and cropped, both
sides draw the same dashed rectangles at the same places; which pixel a
dash boundary takes is rasterizer detail, and that is the whole of the
difference.

Up next - step 48: `paths-data-02-t` (5,496) has one cluster left, a
6,167-pixel one over x=331..456, y=10..128, and it is a single subpath
of `Bez_fill_MQzmqz`: `M372 130Q272 50 422 10zm70 0q50-150-80-90z`.
The file pins that leaf's own vertices with 4x4 markers - a moveto at
442,130, which is `m70 0` measured from 372,130 - and we never draw
it. `addSVGPath` takes the current point of every relative command
from `path.points[$-1]`, and `Path.close` appends a Close verb with no
point of its own, so after a `z` that is still the last point the
*previous* command wrote. §9.3.2 says a closepath leaves the subpath's
start as the current point; read the wrong way round, `m70 0` starts
at 492,10 and its curve runs off through the top of the canvas.

Step 48 landed that. `addSVGPath` asked `path.points[$-1]` for the
current point of every relative command, and `Path.close` appends a
Close verb with no point of its own, so after a `z` it was still the
last point the command *before* the close had written. The builder now
carries the grammar's own current point: `curPt`, alongside the
subpath's `subStart`, both set by `M`/`m`, with `z` putting `curPt`
back where `subStart` is; and `addArc` takes its start as a parameter
for the same reason - the last point held is not the point the grammar
is standing on. The two files that spell the pattern out moved:
`paths-data-03-f` 5,109 -> 897 and `paths-data-02-t` 5,496 -> 1,497,
-8,211 in all - 526 rows, 2,961,737 AE, and no verdict changed.
`Arc_MaZmAzmaz` in 03-f is the clearest case, three subpaths closed and
reopened as `Z ... m 30 30 ... Z ... m 40 24`; in 02-t it is
`Bez_fill_MQzmqz`'s second leaf, `m70 0` measured from 372,130 -
exactly where that file's own 4x4 vertex markers say it must land -
rather than from the 422,10 the quad ended on. What is left in both is
edge and antialiasing noise, no raw cluster over 600 pixels.

Up next - step 49: the smooth cubic is the other half of the same
grammar, and it is wrong. `Lscubic` seeds `pts[0]` with the current
point and then adds `cur - prevC2` to the *parsed second* handle, so an
`S` after a `C` meets it with a cusp instead of a continuation, and
case `s` never assigns `pts[0]` at all - it reads whatever the previous
command left there. `T`/`t` get it right one label below, reflecting
into `pts[0]`. Probe `out/gsvg-st.svg`: the `M 10 50 C 30 10 50 90
70 50 S 110 10 130 50` chain loops away into the top right, the Q/T
chain drawn under it is smooth. Seven suite files use it -
`animate-elem-35-t` (4,296), `conform-viewers-01-t` (3,014),
`paths-data-01-t` (2,657), `animate-elem-83-t` (1,796),
`paths-data-19-f` (1,780), `paths-data-12-t` (847) and
`metadata-example-01-t` (758) - and one core.d unittest pins the
present shape as though it were intended, so it is rewritten with the
fix. One trap in fixing it: the reflection is gated on
`path.verbs[$-1] == Cubic`, but `addArc` decomposes an arc into cubic
verbs, so an `A` followed by an `S` reflects off a handle the grammar
never drew - the gate wants the previous *command*, not the previous
verb.

Step 49 landed that. `Lscubic` reflects into `pts[0]` now, which is the
one line `Lsquad` had always run, and case `s` assigns `pts[0] = rel`
instead of the `pts[0] = pts[0]` that re-read whatever the previous
command had left in the scratch array. The gate went with it: both
smooth commands ask `lastCmd`, the class of the command the grammar
last ran - 'm', 'l', 'c', 'q', 'a' or 'z' - and not `path.verbs[$-1]`,
because `addArc` fills the path with cubic verbs and
`M 0 0 C 1 1 2 2 3 3 A 10 10 0 0 1 20 20 S 30 30 40 40` had been
reflecting off an arc's last handle. Unittests pin both halves:
`C 1 1 2 2 3 3 S 4 4 5 5` and `c 1 1 2 2 3 3 s 1 1 2 2` land on the
same seven points, the smooth handle at 4,4 - 2,2 reflected through
3,3 - and the `S` after that `A` keeps its handle at 20,20.

Ten rows moved, -5,164 in all - 526 rows, 2,956,573 AE.
`paths-data-01-t` 2,657 -> 754 and `conform-viewers-01-t`
3,014 -> 1,112 are the same three drawings twice: `X_curve_MCSmcs`,
`Rem_Rib_mcs` and `Circle_Mcssz`. Then `paths-data-19-f` -461,
`animate-elem-83-t` -329, `paths-data-12-t` -276 and
`metadata-example-01-t` -262. Three rows moved by a handful of pixels
- `text-text-03-b` -16, `text-tspan-01-b` -14, `animate-elem-77-t` -2
- and they carry no path of their own: their letters come from the
suite's own SVG fonts in `resources/`, whose glyph outlines are
`d` strings too, FreeSerif alone holding 59 smooth cubics. Every
`S` join in those glyph runs had a cusp in it. `animate-elem-35-t`
(4,296) has four smooth cubics and did not move: they are the icon
paths inside `visibility="hidden"` groups that its `<set>` elements
uncover further along the timeline, which is the operator-activation
ceiling, not the grammar.

Step 50 landed the clip a viewport comes with. §7.6.4 and §7.7:
'overflow' applies to viewport-creating elements and its initial value is
`hidden`, so an inner `<svg>` cuts what it draws at the box its own
x/y/width/height make, and §19.4 gives a `<use>` instance of a `<symbol>`
- or of a referenced `<svg>`, §5.6 - that same viewport and that same
cut. The box was always there: `openViewport` places it and `viewFit`
maps the viewBox into it. Nothing ever cut at its edge, so whatever the
fit let past the edge went on painting into the parent.
`masking-path-03-b`, the suite's own test of the property, puts two
labels and a green rule outside its inner `<svg>` and its reference shows
them gone; `coords-viewattr-01-b`'s `slice` cells scale a face to 1.5x a
30x60 viewport and its reference cuts the face at the frame.

`clipViewport` maps the box itself with `matrix.mapRect` and runs the
clip under an identity CTM. The engine clips a device-space AABB and
`Canvas.clipRect` maps the whole-number `IRect` it is handed through the
current CTM, so handing it x/y/w/h as integers would truncate them before
the map and put a fitted viewport a pixel off. An axis-aligned CTM -
every inner viewport the suite has - makes that box exact; a rotated one
gets a bounding box, which is how the marker viewport's clip, the
renderer's only other `clipRect`, has always behaved (§22.4).
`overflow="visible"` skips it, read off the element's own attributes the
way the marker clip reads it: 'overflow' does not inherit, and CSS rules
are folded in at `pushStyle`, out of reach of both.

The nested-`<svg>` unittest gained three cases: a rect that starts
outside the box stops at all four edges and a sibling paints where it
could not, so the clip ends with the viewport; `overflow="visible"`
spills; and a `<symbol>` instance cuts at its own 20x20.

Five rows moved, -8,244 in all - 526 rows, 2,948,329 AE.
`masking-path-03-b` 7,025 -> 1,689 and `coords-viewattr-01-b`
3,618 -> 681 are the property's own two tests, and what is left of them
is the host-font label floor and the antialiasing along each fitted edge;
`filters-color-01-b` gave up 6. Two went up, +35 together, and both are
`use`-of-`<svg>` instances whose fit is exact, so only a shape's own
half-pixel stroke reaches past the viewport: `struct-dom-07-f` +26, whose
three squares its `onload` script paints green while the file authors
them red, and `struct-use-06-b` +9, whose capture is test revision 1.4 -
a UA that showed the file's own "external use isn't implemented" red
fallback - against the revision 1.5 file in `suite/`, which we resolve to
its lime external squares. Both were ceilings before the clip and both
stay ceilings.

Step 51 is §15.19's two-number 'stdDeviation'. feGaussianBlur takes one
or two numbers: the pair is the standard deviation along x and along y
separately, and a zero leaves its own axis untouched, so "20 0" smears
sideways under a hard top and bottom and "0 10" is the other way round.
The parser filled s1/s2 with a `seen` counter, and that counter sat
outside the `foreach` body - D takes the body to be the single `if` -
so the loop never advanced it, every token overwrote s1, and the
`seen == 1` line then copied that last token into s2. "20 0" collapsed
to 0/0, which blurs nothing, and "0 10" collapsed to 10/10, which
blurs both ways: the two filters in the suite's own test of the
property drew one identical blob and one untouched pair. The four other
number-list readers in the switch (`order`, `baseFrequency`, `radius`
and `kernelUnitLength`) already brace their bodies; this was the odd
one.

`filters-gauss-02-f` states the rule in its own description - "blurred
only in the non-zero direction" - and its boxes now smear along their
own axis only, 4,730 -> 913; `filters-gauss-01-b`'s
`stdDeviation="20 1"` box takes the same correction, 3,050 -> 632.
What is left in both is the profile of the blur rather than its shape:
a sigma that wide goes through the three-box approximation the engine
uses above sigma 2, so the falloff and where it stops sit a few pixels
off the reference. `filters-gauss-01-b` is a stale capture as well -
its PNG says `$Revision: 1.6 $`, `suite/` holds 1.7.

Two new unittests pin the pair: `stdDeviation="8 0"` puts ink 10 px out
to either side of the box and nothing above it, `"0 8"` the reverse,
and both leave the corner clear, which is the pixel an isotropic blur
would fill.

Two rows moved, -6,235 in all - 526 rows, 2,942,094 AE.

Step 52 is the other half of §15.1: where a primitive's subregion starts
when the primitive does not say. x/y/width/height are primitiveUnits
numbers, so they are not the effects region when the units differ, but
the sides the primitive leaves out are that region's own sides -
§15.7.3 says the default subregion IS the filter region, and a primitive
naming only some of the four has to fill the rest the same way.
`primSubregion` instead handed all four attribute names to `lengthBox`,
which is the filter region's reader and supplies §15.1's -10%/120%
defaults, so a primitive that gave only width/height sat 10% of the bbox
off both leading edges.

The box was already being resolved correctly one case over. `feImageRect`
walks the four sides itself - viewport percentages in userSpaceOnUse,
bbox fractions in objectBoundingBox - and takes a missing side from the
region. That body is now `primBox`, returning continuous device coords;
`primSubregion` rounds it out to a pixel box, empty when the primitive
asks for a zero width or height, and `feImageRect` keeps only its own
zero-size check. `lengthBox` is back to serving the filter region alone.

`filters-offset-02-b`'s first box is the reading: `feFlood
width="100%" height="100%"` inside `x="0%" y="0%" width="200%"
height="200%"`, so the flood begins at the region's edge and its own
100x100 extent ends where the bbox ends. The old defaults started it 10
px early in both axes, the intersection with the region hid that, and
after `feOffset dx="0.1" dy="0.2"` the lime came out 10 px short of the
frame's right edge and 10 px short of its bottom. Each of that row's
three boxes lays a filtered square over an unfiltered one, so the answer
is three solid green squares; the first one is now as green as the
second, and their residual clusters match to the pixel at 392 each - the
antialiased fringe of the 2-unit black frame, which the 2009 capture has
and our rasterizer draws crisp.

The row only falls 837 because most of it was never the subregion. 5,145
of its strong-delta pixels are the third box, whose offset source lies
off the page (new ceiling bullet below), and 989 + 115 are the DRAFT
band and a `$Revision: 1.2 $` label set against our 1.4.

Two new unittests pin the rule in each primitiveUnits. With the region at
10..70, a `feFlood width="40" height="40"` with no x/y runs 10..50 and
not 2..42; and the objectBoundingBox form of the suite's own filter puts
the offset flood 4 px past the box along x and 8 px along y while
leaving the corner it used to fill clear.

One row moved, -837 - 526 rows, 2,941,257 AE.

Step 53 is the difference between a masking reference that does not
resolve and a masking layer that resolves to nothing. `clipMultiply` and
`maskMultiply` both answered false for an unknown id, a target of the
wrong kind and a reference cycle, and `maskedPaint` read that false as
"paint nothing" - the same answer an empty layer gives. The two are not
the same and only one of them hides anything. §14.3.5's 'clip-path'
entry says the first case in as many words: "If the IRI reference is not
valid (e.g. it points to an object that doesn't exist or the object is
not a 'clipPath' element) the 'clip-path' property must be treated as if
it hadn't been specified." §14.4 goes no further than "It is an error if
the 'mask' property references a non-existent object", leaving the mask
half to Error Processing, so the harness decides that one - and
`masking-path-08-b` and `masking-path-10-b` are the clip and mask halves
of a single test, each carrying a cell aimed at `url(#unknown)` under
the comment "This has an intentionally broken clip-path url". Both
captures show the referencing element in that cell: 50x50 of lime over
the red behind it, which is what an ignored declaration paints.

So both multipliers return nothing now. A reference that does not
resolve leaves the scratch alone and the paint carries on; the layers
that resolve and then cover nothing zero the scratch instead - an empty
`clipPath` or `mask`, children all `display:none`, objectBoundingBox
units with no bbox to be fractions of, a mask region with no extent -
and those are the other half of the file's own grid, the `emptyclip` and
`displayclip` cells two columns over. The per-primitive `any`
accumulators went with the return values: `maskedPaint` already scans the
scratch before compositing, and that scan is what now decides whether
there is anything to sprite. An `href` cycle between `clipPath` elements
belongs to the broken half - the chain cannot be read, so the declaration
is not valid - while a `clip-path` *attribute* cycle belongs to the
empty half: both references resolve, the depth cap stops the recursion,
and the inner clip ends up covering nothing.

Filters keep the opposite answer and it is not an inconsistency to
smooth over. §15.4's 'filter' entry never mentions a broken reference at
all, but `filters-felem-01-b`'s circle at 330,60 carries
`filter="url(#notthere)"` and the capture has no red there - the green
behind it shows, on our side too, at 479 AE. Broken clip-path or mask:
paint. Broken filter: do not.

The clip, mask and image unittests moved with the split - unknown id,
wrong target and `href` cycle now assert the paint, empty content,
`display:none` children and the attribute cycle still assert nothing -
and two new ones pin the half that could regress silently: a
`maskUnits="userSpaceOnUse" width="0"` region, and an objectBoundingBox
mask on a zero-width rect, both hide the paint.

Two rows moved, -1,238 each - 526 rows, 2,938,781 AE. What is left of
them is one residue on both sides: four ~98-pixel clusters and three
50-pixel 1-px lines, all on the edges of cells whose red square is inset
`x="0.5" width="99"` under a 0.5 scale, so its edges fall on half
pixels. `masking-path-08-b` keeps one more whole 50x50 block and that
one is ours, which is why it no longer sits in the stale-capture list
below.

Step 54 is one sentence the module had backwards. The same §14.3.5
paragraph that makes every `clipPath` child a 1-bit silhouette
"exclusive of rendering properties such as fill, stroke, stroke-width"
ends: "If a child element is made invisible by 'display' or 'visibility'
it does not contribute to the clipping path." Only the display half was
there. `renderChild` drops a `display:none` subtree before the clip
rasteriser ever sees it, and the two `clipMode` branches - the one in
the shape painter, the one in the text painter - then set `doFill =
true`, which threw away the `s.visible` the ordinary paint path had
already worked out. A `visibility="hidden"` child therefore painted its
full outline into the clip mask.

`doFill = s.visible` in both branches is the change. `if (doFill ||
doStroke)` already guards every draw call, so an invisible child leaves
the mask alone, and when it was the clip's only child the layer resolves
but covers nothing - the half step 53 left standing - and the
referencing element disappears. Inheritance rides along: the clip
renderer pushes the `clipPath` subtree's own presentation attributes
onto a fresh style stack, so a `<g visibility="hidden">` inside the
`clipPath` hides its children exactly as the file's flat attribute does.

Why this survived so long is a unittest that asserted the opposite with
a sample that could not see it: a `clipPath` holding one hidden 10x100
rect, sampled at (5,50), where a *different*, contributing child's clip
covered that pixel regardless of the answer. The case is now four
independent cells - a child under `opacity="0" fill="none"
stroke-width="4"` and a child under an 80-unit stroke both still clip,
which is the "exclusive of rendering properties" half, and a
`visibility="hidden"` rect plus a hidden `<g>` both leave their cell's
lime showing through.

One row moved, -1,237 - 526 rows, 2,937,544 AE. `masking-path-08-b`'s
raw-diff count fell further than its AE, 3,043 -> 593, because the
compare's fuzz had already been forgiving the half-tone pixels along the
cells' half-pixel edges: the two metrics never agree about what a rule
is worth, so only the AE belongs in the table.

Step 55 is one clause of `conditionsPass`. The three conditional
processing attributes are true when absent, and a present-but-empty
`requiredFeatures` read as the vacuous case of "every feature in this
list is supported" - no features listed, nothing to fail. §5.8.3 shuts
that reading: after describing how the list is tested it ends "If a null
string or empty string value is given to attribute 'requiredFeatures',
the attribute returns false." §5.8.4 says the same words about
`requiredExtensions`, which we already refused because this renderer
claims no extension, and an empty `systemLanguage` list has no language
to match, so those two already landed where the REC puts them.

`conditionsPass` now counts the tokens it tested and fails the element
when that count is zero. The count covers a value of nothing but
whitespace too - the split yields no token, so there is nothing to
accept - and every test goes through this one predicate at all four of
its call sites: `renderChild`, the `use` instance that skips a
switched-off target, and both halves of the `<switch>` search. So a
blank branch inside a `switch` is skipped and the next child takes the
slot, which is what the second `switch` in the module's own test now
pins, and the unittest that used to claim the vacuous pass has asserts
that can actually see the difference.

`struct-cond-overview-03-f` is the suite's test of exactly these three
blank values - three blue boxes, each with a twin carrying one empty
attribute - and its pass criteria, "the test passes if three blue boxes
are visible", agree with the REC and the capture against us: our
requiredFeatures="" twin painted its default black across the first
box. 2,510 -> 604. What is left is the row's older residue: 1,365
pixels of DRAFT band, which is the white label and its host-font AA,
the revision text under it, and two 2x100 columns at x=0..1 where the
test frame's stroke disagrees.

Step 56 was that experiment, and it is the largest single move the gate
has seen: 507 rows better, 8 worse, -247,601 AE over all, the total
down to 2,688,037.

The disagreement is the suite's own furniture rather than any test.
Every W3C file carries `<rect id="test-frame" x="1" y="1" width="478"
height="358" fill="none" stroke="#000"/>` - one pixel wide, centred on
an integer device coordinate, four sides of it - and the same shape
recurs inside the tests: the DRAFT band's strokes at y="1" and y="21",
fonts-kern-01-t's 200x50 sample boxes, coords-units-03-b's grid. The
captures resolve such an edge by the *pixel centres* it covers, so
painting-fill-01-t is opaque black at (1,50) with (0,50) untouched and
at (240,1), (479,180) and (240,359), and the DRAFT band's own rows 1
and 21 are solid. Ours integrates coverage over the pixel cell, which
splits that band 128/127, and the harness charges about a quarter of a
pixel for each extra half-covered one - a whole one where the frame
crosses something coloured.

`Path`'s raster sits in the prebuilt guip dependency, so the
correction is geometry rather than sampling: `snapHairline` (step 59
renames it `snapStrokeBand`) walks the path a stroke is about to consume
and moves every axis-aligned vertex half a device pixel toward larger
coordinates, which puts the band on the pixel the captures light. It
fired only where that convention was forced - a CTM with no rotation or
skew, the same scale on both axes, a device stroke width of exactly one
pixel (the test step 59 drops), and a contour whose every
edge runs along an axis. A plain `<rect>` qualifies: addRoundRect
emits four degenerate cubics even with no radius, so the test looks at
the verb's points and not at the verb. One tilted edge disqualifies
the whole contour instead of part of it, because a half-snapped stroke
would tear open at the join. Nothing already lying between pixel
centres moves - the test is per vertex and per coordinate - and fills
are left alone, because cell integration and centre sampling agree at
an integer edge, which the captures confirm. The rule is in the SVG
layer at the one call that hands geometry to `strokePath`; the text
site keeps its own raster.

Fills' agreement is why the rule is stroke-only; the counter-family
is why it is a rule and not a law. Some captures came from a
raster that splits the frame exactly as ours used to: the test frame
of painting-stroke-05-t reads 127/127 across columns 0 and 1 there,
as do those of text-fonts-202-t and filters-light-02-f, so those three
now pay 651, 418 and 53 AE more and five other rows a handful each -
1,144 in all against the 248,745 recovered. The two conventions belong
to the captures, not to us; the split-family rows are listed under the
ceilings.

Everything the lead named moved. `painting-fill-01-t` is exact now
(645 -> 0), `painting-control-05-f` and `pservers-grad-16-b` too
(1,099 and 1,075 -> 0), `struct-cond-overview-03-f` 604 -> 37,
`fonts-kern-01-t` 2,617 -> 467, `coords-units-03-b` 1,733 -> 480,
`text-align-07-t` 6,338 -> 5,611, `render-groups-01-b` 3,158 ->
2,741. `pservers-pattern-01-b`, the counter-case that had to be
explained first, was the missing tile edge and not the convention, and
came along anyway: 3,192 -> 2,545.

Step 57 is the primitive coordinate system, and the lead above was
wrong about it in a way worth keeping. All three `feFlood` boxes were
already exact: the "75x75 block at x=80" was a probe window's artifact
- the window ran x=80..180, y=0..100, and the lime it counted was the
star row's blob at x=40..115, y=65..137 leaking over its corner, not a
misplaced flood. What that file really tests, and what was broken, is
§15.3: `primitiveUnits` and `filterUnits` are independent, and the box
the primitive numbers are fractions of is the filtered element's
bounding box either way. `primsObjBB` reached the chain correctly; the
chain only built its `basis` box when the *region* was
objectBoundingBox, so a filter spelling its region in user units and
its primitives in fractions of the box had no basis at all, and the
primitive scale answered 0 for every number in it. The middle star's
`feOffset dx="2" dy="2"` - two box widths, 152 px across and 146 down -
drew no shift at all: the star stayed at x=40..115, and where the
capture has its shifted self, x=190..270, only the 667-px decoy outline
stood instead of 2,774 px of star.

So: one branch in the filter path. When the primitives are fractions of
the box and the region is spelled in user units, take the basis
anyway. The §15.5 rule that a zero-area bbox disables rendering stays
where the spec puts it, on the objectBoundingBox *region* - that filter
still paints nothing - while the same chain inside a user-space region
paints, its own fractions scaled to nothing by the empty box.

One row moved and none moved back: `filters-felem-02-f` 2,495 -> 440,
-2,055. The other five files in the suite that name `primitiveUnits`
were unchanged by it - `filters-conv-05-f` 153,636,
`filters-offset-02-b` 2,773 and `filters-tile-01-b` 621 exactly as
they were, `filters-image-03-f` 24 and `filters-light-03-f` 395 within
a pixel of themselves. 526 rows, 2,685,982 AE. What is left of that
file is not the coordinate system: 1,030 raw pixels sit in the middle
circle's halo, where obb2's `stdDeviation="0.2"` of a 60x60 box -
sigma 12 - darkens the same extent in both rasters and shapes the tail
apart, the filters-blur question, and the rest is a one-row lime
fringe beside the two offset stars.

Two rows triaged out of the way and ruled out: `fonts-desc-04-t` (4,966) and
`fonts-desc-05-t` (5,001) are the DRAFT band and nothing else -
9,063 raw pixels of their 9,063 and 9,108, all of it x=2..478 y=2..20,
their SVG fonts exact - and `text-tselect-02-f` (4,249) is the
selection state its `onclick` buttons drive; all are ceilings.

Step 58 is the group offscreen that the lead above called a spread of
edges. The colour census gave it away: the capture has *no* pixel of
either colour that ink under a half-alpha red rect makes - (128,63,88) of
red over glyph-on-a-guide-line, (113,48,73) of red over the #C0C0C0 page -
while we had 5,485 of the two; and its red-over-white (12,042) plus
red-over-#C0C0C0 (11,322) come to 23,364, which is exactly the picture's
area under that rect outside the `<image>`. The text that rect covers is
simply not in the capture: the group paints at full strength and
composites once, which is §9.2 and §9.3.1 saying so outright, and
`masking-opacity-01-b` - the suite's own four rows of group opacity
against the rectangles' own, run through in the same file to show the
difference - is the test of it. Folding the alpha into every child draws
the same picture only while no child can see another; here it let covered
text shine through an opaque rect.

One wrapper in the dispatch and one blend. A `g` or `a` whose own style
alpha is between 0 and 1 paints its subtree into a full-canvas scratch and
lands it on the destination once, at that alpha; `a` joins `g` because
§9.3.1 makes it the same kind of container. The alpha is consumed on the
way in, so the style answers 1 for everything below and a child naming
`opacity` opens a layer of its own instead of multiplying this one twice -
two nested 0.5 groups over black land on 64, not 32. The blend scales the
premultiplied scratch by round(op*255) through alphaMul/alphaScale, the
rounding resolvePaint already uses, so an opaque child of a 0.5 group
carries alpha 128 and its red over #C0C0C0 is (161,96,121) in both
rasters. And, exactly as in filteredElement, `bmp` goes back *before* the
blend: blend while `bmp` is still the scratch and the layer composites
onto itself, which is how that row read 13,202 for one build. An element
that names a `filter` keeps its old path - it is offscreen already and
folds its alpha at the primitive.

Seven fractional container opacities sit in the whole suite, in three
files, and all three rows moved: `masking-opacity-01-b` 862 -> 0,
`render-groups-01-b` 2,741 -> 1,126, `filters-background-01-f`
2,114 -> 1,694, its one filtered group left as it was. Nothing else can
move: the `filters-overview-*-b` groups that spell 0.6 also name a
`filter`, `filters-conv-01-f` spells only 1, and no file puts `opacity`
on a `use`, `switch` or nested `svg`, so those containers stay unwired on
purpose. 526 rows, 2,683,085 AE: -2,897, three rows better, none worse,
no verdict changed.

What is left of `render-groups-01-b` is the edge family after all:
1,717 raw px of frame, whose 1-px stroke is 1.8 device px under
`scale(1.8)` and which the capture spreads over three pixels as
0.2/1.0/0.2 where we integrate the area into 0.9/0.9 across two - step 56's
snap answered a hairline exactly one pixel wide and nothing else, the
condition step 59 drops. The rest
is that same 1-px call at the .5 edges of the guide lines below the grey
rect (six 71-px clusters at y=298..315) and one column down the `<image>`'s
right edge at 435.6, which is all that is left of it now.

Step 59 is the rest of step 56's convention, and the lead above walked
into it by accident. `pservers-grad-11-b`'s right-hand rect is
`x="250" y="30" width="170" height="100"` with `stroke-width="40"`, so the
band it paints runs 230..270 in x and 10..150 in y, every edge along a
grid line. Ours bounds each edge with the pixel it covers: column 230 is
ink the whole height, 229 untouched. The capture gives column 230 alpha
128 and column 231 full ink, and the same at 440, at y=10 and y=150, and
at the hole's edges 270 and 50 - a band that is ours translated half a
device pixel toward larger coordinates. That is the hairline finding
again: a 1-px band centred on `x="1"` spans 0.5..1.5, half a pixel over
is 1.0..2.0, one whole lit column at x=1. One rule covers both widths,
and the "device width exactly one pixel" test goes away.

The control that keeps it a stroke rule and not a geometry rule is that
file's left rect - `x="10" width="210"`, fill only - where the capture
lights column 10 and not 9, 219 and not 220, agreeing with our
cell-integrated fill to the pixel. So the shift rides on the stroked
outline alone: `snapStrokeBand`, step 56's `snapHairline` renamed and
without its width test, nudges the contour a stroke is about to consume
and the fill path never sees it.

What still has to hold is what held before, all of it measured in device
space: no rotation or skew, the same |scale| on both axes, every edge of
the contour along an axis - one tilted edge would tear the stroke open -
and only a vertex already on a grid line moves. Two things are new. The shift
goes *across* the band and not along it: the coordinate that separates
the two edges moves, the cap and corner coordinates that run along the
axis do not, so §11.2's square caps still end where §11.2 puts them and
`painting-stroke-02-t`'s three linecap variants come to 1 AE. And a
zero-length subpath has no band at all, only the cap §11.2 gives it, so
its contour stays where it is; nudged, the round dot of `M 12 10 L 12 10`
at width 8 moves its centre to (12.5, 10.5) and the disc stops ending at
x=16, which the module's §11.2 unittest pins. Such a contour is flagged
as it is read and left alone, and that costs 346 AE against shifting the
caps too - no file with a zero-length subpath regressed either way.

Four module unittests had pinned the cell answer for a band - the 2-px
`<line>`, the gradient-stroke bbox sample, and the bare polyline under
markers twice - and now read half, full, half, 127 at the boundary
column; the snap's own cases swap the width sweep for the 40-px band and
a 2x CTM, where the nudge is half a *device* pixel and so half as far in
user units.

The gate is the argument for taking the majority convention: 526 rows,
2,653,290 AE, 103 rows better by 31,143 and four worse by 1,348, no
verdict changed. Rows going to essentially nothing are the tell:
`painting-fill-04-t` 961 -> 0, `masking-path-01-b` 792 -> 1,
`painting-stroke-02-t` 692 -> 1, `styling-class-01-f` 395 -> 1,
`fonts-overview-201-t` 589 -> 3, `animate-elem-13-t` 2,234 -> 5,
`painting-stroke-08-t` 784 -> 62, `painting-render-02-b` 767 -> 79. The
scaled ones come along: `render-groups-01-b` 1,126 -> 195, its
1.8-device-px frame band spread over the right three pixels at last,
`render-groups-03-t` 1,220 -> 289, and `painting-stroke-06-t`'s dash
boundaries 1,208 -> 869, since under `scale(1.8)` its 9-device-px dashes
start on a grid line and carry the band with them. The wide band that
started this is fixed and the row barely moves: `pservers-grad-11-b`
4,905 -> 4,530, because 5,701 of its raw pixels sit in the y=236..271
glyph band of the 45-px `Gradient on text stroke` line, not on the chips.

The four that pay are the counter-family the step-56 note already
records, now seen whole. `painting-stroke-05-t` (+1,120) is the file that
*probes* stroke widths, so it reads the reference's raster directly, and
there the other convention runs end to end: not only is its frame 127/127
across two columns, every vertical stroke is split symmetrically about
its own centre line and quantized to 1/8 - 64/64 at width 0.5, 255/255 at
2.1, mass conserved, no half-covered boundary pixel anywhere.
`masking-path-02-b` (+187) is the same at width 4: full pixels at
48..51 where the shifted convention half-covers 48 and 52. The split
belongs to the captures file by file, not to any declared intent - of
the ten files that spell `shape-rendering="geometricPrecision"`,
`masking-path-01-b` and `masking-path-03-b` gain 791 and 884 while those
two lose 187 and 1,120 - so holding both would be a per-file raster
policy and we take the majority.

Step 60 is what step 59's guards were really guarding. `struct-group-03-t`'s
22-px cell grid sits under `<g transform="translate(70, 150) rotate(-90)">`,
which carries a user point to the device point `(y + 70, 150 - x)`: the
cells are axis-aligned in user space *and* in device space, axes swapped
and one of them flipped, and their bands half-cover the boundary pixel in
the capture just as they do at identity. Step 59 could not reach it because
its nudge was computed in user space - a half-*device* pixel there means
dividing by `sx` and `sy` separately, which is one translation only when
the matrix has no rotation and equal |scale| on both axes. Those two
conditions protected the arithmetic, not the rule.

So the nudge moves to where the rule is stated. `snapStrokeBand` maps the
contour into device space through the whole matrix, decides the shift
there, and maps the nudged point back through the 2x2 inverse - `det =
a*d - b*c`, and a zero or non-finite determinant has nothing to map back
through, so such a matrix is refused outright. The half pixel is added to
the *grid line*, `round(pt.x) + 0.5f` and deliberately not `pt.x + 0.5f`,
because `rotate(-90)` carries a cosine of -2.5e-20 along with it and that
drift is not part of where a band belongs. Nothing about *whether* to nudge
changed: the test is still device-space, one tilted device edge still
refuses a whole contour, and a vertex already between pixels still stays
put.

The equal-|scale| test was the open half, and there the captures split.
Under `scale(1, 1.5)` `pservers-grad-07-b`'s 30-device-px band half-covers
rows 150, 180, 195 and 225 - the shifted convention, and that row comes
out exactly 0. `preserveAspectRatio="none"` makes `struct-frag-02-t`'s
whole view fit anisotropic and it goes to 0 too, and `scale(1.2 2.5)` and
`scale(0.75, 0.5)` take `coords-trans-11-f` and `interact-pevents-07-t`
down 75 and 45. `paths-data-18-f` goes the other way: under `scale(8, 2)`
its black band covers device rows 46..53 wholly, edge pixel included, and
the nudge costs it 429. Four files follow the device rule at anisotropic
scales against one that does not, and a non-uniform CTM stops making the
shift ambiguous once the shift is one device vector instead of two user
ones - so the guard goes with the arithmetic it was written for.

526 rows, 2,653,290 -> 2,651,152 AE: ten rows better by 2,790, four worse
by 652, no verdict changed. The target, `struct-group-03-t`, goes 1,568 ->
298; `pservers-grad-07-b` 427 -> 0 and `struct-frag-02-t` 201 -> 0 come
out exact; `animate-elem-82-t` 886 -> 492 and `animate-elem-36-t` 859 ->
605 follow their `rotate(180)` and `rotate(90)` groups; and
`coords-trans-12-f` 247 -> 206 is the suite's own proof that `rotate(90)`
and `matrix(0 1 -1 0 0 0)` paint the same picture, since both halves snap
the same way now. The payers are that split seen from the other side:
`paths-data-18-f` +429, `pservers-grad-17-b` and `-20-b` +64 and +65,
`filters-light-02-f` +94.

One of the snap's unittests changes meaning. The 45-degree matrix step 59
refused *as a matrix* is now refused *as a contour*, and a
`translate(70, 150) rotate(-90)` case pins the quarter turn at
(0.5, 1.5) -> (478.5, 1.5) -> (478.5, 359.5) -> (0.5, 359.5): user x back
by half a pixel, user y forward by half, one device nudge arriving through
a flipped axis. That one is compared at a tolerance of 1e-4 rather than
`==`, for the same cosine hairline the nudge itself sheds.

What is left of `struct-group-03-t` is not raster. Two green blobs, 54 raw
px at x=216..226 y=195..200 and 43 px at y=160..164, are the round caps of
the `stroke-linecap="inherit"` line sample: the capture rounds its ends to
y=160 and y=200 and we cut them square at 165 and 195. A probe says
'inherit' is honoured for `fill-rule`, `visibility`, `display`, `fill` and
`stroke-width` and is not routed for `stroke-linecap`.

Step 61 is §6.4 and §6.14: the `inherit` keyword on a presentation
attribute. `struct-group-03-t` is that rule made visible - seventeen
property rows whose top row spells the word `inherit` and whose bottom
row spells out the value that should arrive. Sixteen of the seventeen
samples use the keyword, plus one more in the reference row, where
`stroke-dasharray` was meant to be spelled out and is not; that is why
both of that sample's rows are dashed in the capture.

Every property's value grammar ends in `| inherit` - the local copy of
the spec says so for `stroke-dasharray`, `text-anchor`, `font-style`,
`fill-opacity` and the rest - and §6.14 makes inheritance mean the parent
element's computed value. `pushStyle` already starts every element from a
copy of its parent's whole `Style`, so the keyword asks for exactly what
those fields already hold: dropping the declaration *is* the rule, and it
lands as one early return at the top of `apply` rather than as an
`inherit` arm per property. It also covers the properties no one
enumerated - `color-interpolation`, `mask`, `overflow`, and the rest the
cascade forwards to a field it never re-reads.

What varies is what each handler does with a token it does not
understand. A length or a number goes through `parseLength` or `to!float`,
throws, and the `catch` keeps the inherited answer - which is why
`stroke-width`, `stroke-miterlimit`, `stroke-dashoffset`, `font-size` and
`font-weight` honoured the keyword already. An enumeration has a
`default:` arm that reaches for the property's *initial* value -
`stroke-linecap`'s butt, `stroke-linejoin`'s miter, `text-anchor`'s
start, `font-style`'s roman - and a list property simply assigns what it
parsed, which for `inherit` is nothing at all: `stroke-dasharray` turned
the line solid. Hence a keyword that looked honoured for some properties
and lost for others. The stale comments claiming `inherit` reaches those
arms say "a token the grammar does not allow" now, which is what does
reach them.

526 rows, 2,651,152 -> 2,651,071 AE, and exactly one row moves:
`struct-group-03-t` 298 -> 217. Everything else in the suite that spells
the keyword - the eleven `stop-color="inherit"` and four `stop-opacity`
uses across `pservers-grad-18-b`, `pservers-grad-23-f` and three
`animate` rows, `color-prop-01-b`, `masking-path-12-f`,
`interact-events-202-f`, and `styling-inherit-01-b`'s middle stop, whose
green came from its gradient element - already kept the parent's answer
and came back byte-identical.

Three unittests pin the arms that changed, one per family: the round cap
`stroke-linecap="inherit"` inherits, half a stroke-width past `x1`; the
round join `stroke-linejoin="inherit"` inherits - that sample's polyline
closes to 30 degrees at its apex, so a miter spikes nine device pixels
over the vertex where a round join is a 2.5-pixel arc - and
`stroke-dasharray="inherit"` keeps its gaps. Each is paired with the
initial value spelled out on the same element, so each pair measures the
keyword and not the stroker.

Two things the rule does not buy, both unmeasurable here: the two
baseline properties are reset to `parent` on every descent (step 6's
footnote), so `inherit` there keeps the initial value rather than the
ancestor's; and `opacity="inherit"` on a child of `<g opacity>` reads the
1.0f that step 58's layer consumed. The suite never sets either, so the
gate cannot see them and no code was written for them.

What is left of `struct-group-03-t` is shared by both rows now: every
cluster comes in a pair 50 px apart, so our two rows agree with each
other and differ from the capture identically - the round join's top arc
at x=240..244, the cell grid's band edges at x=219..223 and 285..289, the
rotated property labels' antialiasing at x=258..265, and the *ends* of
the dashes at x=199, where the capture runs each dash one device pixel
longer than we do (160..165 against 160..164, 170..172 against 170..171)
at an identical phase. All raster, none of it inheritance.

Step 62 is §6.10's `type` on `<style>`. The attribute is a content-type
naming the language the element's contents are written in; absent, the
element takes the document's default style sheet language (§6.13), and
CSS - `text/css` - is the only language this engine reads. The element's
attributes come from HTML, and HTML's rule for a language the user
agent does not support is that the style element and its children are
ignored completely: not parsed, not cascaded, never rendered. The gate
at the head of `collectStyles` is that rule entire: absent or `text/css`
- case-insensitive, media-type parameters like `charset=` along per
RFC 2046 §3.6 - is a sheet; anything else is not one, and `text/css2`,
HTML's own example of a language to ignore, is not `text/css` merely
because it starts the same way. The unittests pin all five shapes: the
untyped sheet, the two spellings of `text/css`, and both rejects.

The suite spells the attribute just three ways across its 47 `<style>`
elements: 43 say `text/css`, 3 say nothing, and one says
`text/some-unknown-styling-language` - the last in styling-elem-01-b,
whose lower rectangle sits on the 50x50 square that bogus sheet was
never meant to fill. One row moved: 956 to 17, and the 17 is what
magick's 10% fuzz makes of a render with zero pixels differing by more
than 4/255 anywhere - the square is exact, the bogus sheet is inert,
and the file's untyped sheet is still honoured. Total 2,651,071 to
2,650,132 across 526 rows, no verdict changed.

Step 63 is §6.9's `xml-stylesheet` processing instruction: an SVG user
agent supports it, and XML Style 1.1 says where it lives and what it
means - a PI in the prolog, before the document element, naming an
author style sheet for the whole document, and the user agent acts on
the first of them, in document order, whose attributes it can act on.
The parser now keeps the raw content of every `xml-stylesheet` PI above
the document element (`Document.sheetPIs`), and `collectStyles` reads
them before it walks the element's own: an `href` to fetch, a `type`
that passes the §6.10 gate, no `title` - a titled sheet is an alternate
between sheets, and there is no user here to choose - and a `media`
list that names the medium this engine paints. The PI's attributes are
`name="value"` pairs (XML Style 1.1 §1.1: the value must be quoted, and
the first occurrence of a name owns it, XML 1.0 §3.2), and a surviving
href rides the `@import` machinery verbatim - same `resolveHref`, same
`baseDir`, same splice at the head of the cascade. And for an external
document that `baseDir` is that document's own directory, so a relative
href lands beside the file that named it.

That is the whole of `struct-use-04-b`: four `use` clones of fragments
in `../images/svgRef4.svg`, whose prolog names `svgRef4.css` - four
fill rules, fuchsia, blue, green and gold - through the only PI in the
suite. The clones' geometry was already right down to the stroke band;
only the fills disagreed, and now they agree: 15,089 to 388, what's
left being stroke AA and caption text already known as debt. Two
unittests pin the halves: the parser keeps exactly the prolog PIs whose
target is `xml-stylesheet` - the xml declaration, other targets, and
the same target below `<g>` or after `</svg>` are all dropped - and the
cascade hands five PIs to one document: the unknown type, the titled
sheet and the `media="print"` sheet step aside, `media="screen, all"
type="TEXT/CSS"` is acted on once, and its rules lead the document's
own sheet with no later PI riding along. Total 2,650,132 to 2,635,431
across 526 rows, no verdict changed.

Step 64 is the media selector of CSS 2.1 §10.3.1, asked wherever a
sheet can name the media it is written for: §6.10's `media` attribute
on `<style>`, the media clause of §6.4.3's `@import`, the `@media`
rule itself, and - replacing a hand-rolled all-only test - the
xml-stylesheet PI's descriptor from step 63. One function decides them
all. `mediaMatches` splits the list at commas into groups; a group is
a medium name, optionally qualified by `only` or inverted by `not`,
and this engine paints one medium, the one CSS calls `screen` and
`all` also names. A group asserting a media feature in parens does
not match: the engine implements no media features at all, and a
clause it cannot evaluate is not a clause it can call true. An empty
list restricts nothing.

The three places ask it in their own way. A `<style media>` that fails
is not a sheet at all, like `type` at step 62. An @import's clause
sits between the URI and its `;`, and when it fails the fetch never
happens. An `@media` block whose selector matches splices its
contents into the cascade at the block's place - the order counter
rides through by reference, and the block's own `@media` and `@import`
reparse recursively - and when it does not, the block is dropped
whole, inner rules and all.

Four unittests pin it: the matcher's table (the empty list, `all`,
`ScReEn`, `print, screen`, `only screen` and `not print` hold;
`print`, `braille, print`, `only print` and the parenthesised feature
do not); @media splicing and dropping; the @import clauses that fetch
and don't; and a `<style>` whose `media="print"` steps aside while
`all` and the absent attribute stay. The gate came back
byte-identical, 2,635,431 over 526 rows, and that flatness is the
result: the suite writes zero `media` attributes, zero `@media`, and
three `@import` none of which carries a clause.

Step 65 is CSS's `@font-face`, the one at-rule that is not a rule.
`fonts-elem-07-b` (1,354) and `fonts-elem-04-b` (1,357) each draw the
same five-character string twice: the upper line is hand-placed
`<path>` glyphs of an SVG-font Comic Sans, the lower is that text
rendered in the same face, and the test asks the two lines to agree
in size, baseline and advance. We were off by exactly 1,354 and
1,357 because the lower line came out in a host face - and the one
thing tying those `<text>` elements to the font is an `@font-face`
block that css.d used to throw away as noise. A block is a
descriptor table, so parseSheet keeps one as a `FontFace` - raw
`font-family`/`src`/`font-weight`/`font-style` strings - on a side
sink that threads `@import` and `@media` like a rule order does, and
`sheetFaces` hands back, for every document, exactly the sheets
collectStyles reads: the prolog PI's sheet and the media-matching
`<style>` elements. The block does not join the cascade; it belongs
to the font store, and fonts.d is what walks it. A `src` URI with a
`#` fragment names a `<font>` here - in 07-b the block is the only
name the embedded `#InternalFont` has, its `<font-face>` carries no
`font-family` - or names one in a file, and the same loader
`font-face-uri` rides reaches it, so 04-b's
`../images/ext-TestComic.svg#Font` comes along for free. The
registration lands in the store step 7 built, under the block's
family and weight and style, where the `svgFace` lookup already
looks; a face named only by a sheet now answers `font-family`.

Three scope lines stay on the ledger: `local()` sources name host
fonts this engine has no access to, `format()` hints are believed
only when the file parses as SVG (a binary font throws, and the
face is skipped), and `unicode-range` is not consulted.

The first version of the block crashed, and the crash is worth
recording: it tested `if (auto h = find(href, '#'))`, and a slice's
truth in D is non-null, not non-empty - `find`'s miss is an empty
slice, so the test is always true, and `h[1 .. $]` then draws
outside the array. `text-text-05-t`'s fragment-less `src` walked
straight into it. The same idiom sat in four older places - the
`font-face-uri` walk, `resolveHref`'s fragment strip, and the
fragment parsers of `<use>` and `tref` - where a `h.length < 2`
guard had made the body accidentally right and one `else` branch
had never once run. All five now test the range itself; the two
that changed nothing could have hidden a real bug tomorrow.

Three unittests pin it: the descriptor table picks `url()` over
`local()`, drops a face written for print and keeps the screen one
through `@media`, rides the face along the `@import` path, and
contributes nothing from a `media="print"` `<style>`; the end-to-end
one registers an anonymous `<font id="IF">` under
`'Test Comic'`/bold and finds its glyphs by `matchFace(700, bold)`
and nothing else. In the gate, 07-b falls 1,354 to 264 and 04-b
1,357 to 267 - the residue is the test-frame band that sibling 03-b
also sits at, 267 - and no other row moves: 2,635,431 to 2,633,251
over 526 rows, no verdict changed.

Step 66 is the `<font>` glyph origin, and the lead's guess about it
was wrong. `fonts-elem-05-t` (1,462) is the only file in the suite
that sets the pair anywhere: two of its three fonts carry
`horiz-origin-x` 500 and 1000, and each of its three rows draws
`1234` as boxes grown from the glyph coordinate origin - a square
from (0, 0) up to the glyph's width - with a pale blue marker
square at each pen position, the 500 and 1000 rows adding ticks
15 and 30 px along to mark where an outline corner would land if
the origin shoved it. Our engine shoved: it mapped outlines by
`(coord - origin)`, the reading "the X coordinate in the font
coordinate system of the origin of a glyph" (§20.3) invites, and
measurement put its boxes at columns 290/335/380 - fifteen px left
of the pens at 305/350/395. The archived reference put them at
305/350/395 exactly: every box's left edge on the pen, at origin
500 and 1000 alike. The lead guessed the capture shoved the other
way, `+origin`; it ignores the pair entirely, and the test's own
pass criteria agree - "a series of black squares whose lower-left
corner aligns with the centre of the corresponding small, pale
blue square" for each subtest alike - as does the third row's
label, which reads "horiz-adv-x=1000 but ignored". The file is
`status="accepted"`, its capture is the harness's ground truth,
and both read the attribute one way: a declaration that moves
nothing.

So `appendGlyph` scales font units by the em and flips y, full
stop - the ox/oy parameters are gone from its signature and from
its one font-units call site - and `SvgFont` keeps the pair as a
parse record: `parseFont` still reads the attributes, and
placement never asks for them. The new unittest draws one square
glyph from a font declaring `horiz-origin-x="50"` and
`horiz-origin-y="25"` and from the same font without them, pixel
for pixel identical, the ink pinned to the pen's five columns and
five rows above the baseline. In the gate 05-t falls 1,462 to 126
- the only mover, since every other row's origin is the default
zero - and the total comes down to 2,631,915 over 526 rows, no
verdict changed.

Step 67 is measurement, not pixels. The two animate-dom rows
answer for themselves once rendered: their diffs are columns of
solid squares - the `getStartTime()` and `ElementTimeControl`
indicators only a script could have drawn - on pages that
otherwise agree but for the revision line. The script-specify
pair ask that a bogus-language script NOT run, which is exactly
what a scriptless engine does, and both renders already paint
"Good, script didn't run." in the green the pass criteria
demand; the captures answer to older revisions instead - the
01-f PNG lays out a "Click on target" line the markup no
longer contains, and 02-f's title is worded differently there.
`pservers-pattern-01-b` (2,198) is the odd one out, and only
in kind: its pattern rects, fill tile and stroke tile alike,
land pixel for pixel, and every pixel of its remainder is an
Arial caption, host-glyph debt like every other Arial row.
Five rows to the deferred list; the gate came back
byte-identical - 526 rows, 2,631,915 AE, no verdict moved.

Step 68 is the first change outside svg/, and it is a plain
reading of §11.6.3 against our own rule. The joiner in the
shared stroker - `MiterJoiner` in
`src/graphics/core/stroke_detail/joiner.d` - culled on half
the spec's ratio: it took the spike to be 1 / (2 sin(sweep/2))
widths deep and beveled below 2 asin(0.5/ml), about 14 degrees
at the default limit. The spec states the ratio outright -
"miter length (distance between the outer tip and the inner
corner of the miter) to stroke-width ... 1 / sin ( theta / 2 )"
- and works the very cutoff we measure: "a limit of 4.0
converts them for theta less than approximately 29 degrees".
The captures were spec-literate all along. At the 28-degree V
of `shapes-polyline-02-t` at (35, 150), stroke-width 8, the
reference's ink stops at the vertex row y=150; the old rule
spiked to y=163, the new one bevels and stops at 150 too. The
polygon-02-t arrowheads triaged with them are 55-80 degree
miters both rules keep - their outline-only diff was always
the recorded stroker convention, and it stays.

`painting-stroke-07-t` confirms from the other side: its
description computes its shape's cutoff as 18.028 and its six
panels step `stroke-miterlimit` 20, 18.1, 17.9, 17, 4, 1
across that value. The old rule kept spikes at 17.9 and 17
that the capture bevels; the new one lands all six right and
the row falls 933 to 619. The joiner's unittests pin both
sides of 29 degrees at the default limit; the 1.15-degree
fold-back pair still bevels at limit 30 and keeps its point
at 200 - by the spec's ratio a 100-width spike.

In the gate nine rows fall and one - `filters-example-01-b`,
one blurred pixel - rises: `painting-stroke-07-t` 933 -> 619,
`shapes-polyline-02-t` 946 -> 771, `shapes-polyline-01-t`
663 -> 635, `text-altglyph-01-b` 1,787 -> 1,749,
`pservers-grad-08-b` 1,223 -> 1,200, and four rows by a point
or two. The total comes down to 2,631,334 over 526 rows, no
verdict changed. What remains of the movers is the recorded
half-pixel outline convention and caption text: the rest of
the stroked shapes family, `shapes-polygon-02-t` included,
sits at that ceiling, measured this step.

Step 69 started as the band sweep the step-68 lead set out, and
found its engine fix in the first solid blocks the sweep met. In
`painting-control-02-f` both test columns were solid black in our
render against the capture's alternating orange and black bands:
the fixture writes `stroke-dasharray="10px 20px 20px"`, and the
parser fed every token to bare `to!float` - `10px` threw, the
whole list was dropped as invalid, dasharray gone, stroke solid.
§11.4's grammar is a list of `<length>`/`<percentage>` values,
percentages of the normalized viewport diagonal - the very
reference `stroke-dashoffset` next door already used.

The fix parses each entry with `parseLength` under the same
arc-diagonal percentage reference the offset and `stroke-width`
set. The suite holds no other unit-suffixed dash value, so the
blast radius is the one row; the unittests pin the px triple
repeating to six entries and `50%` of a 400x400 diagonal
measuring 200. The audit this invites - each remaining bare
number parse against its property's spec grammar - comes back
clean: opacity, miterlimit and the coordinate lists are bare
`<number>`s by spec, and dasharray was the only length list
hiding behind numbers.

In the gate exactly one row moved: `painting-control-02-f` 762
-> 133, its dashes landing on the reference's places and widths
in both subtests; what is left is a hairline at each dash's butt
cap - the recorded dash-end convention `painting-stroke-06-t`
lives at - and the revision glyph. Total 2,631,334 -> 2,630,705
over 526 rows, no ERROR, no verdict changed.

The sweep itself closed the 300-1,500 band: sixteen rows triaged
by render and diff, fifteen measured at ceiling and recorded
below with their content verified - the marker squares of
`painting-marker-02-f` pixel-exact under crops (row one only -
step 74 reopened the row proper), all three
`color-interpolation` bars of `painting-render-01-b` inside one
LSB (the engine already interpolates in linearRGB), the spirals
of `render-elems-07-t` and `-08-t` outline-doubled edge to edge,
and `styling-pres-02-f`'s fourteen solid squares being script
indicators: black in the markup, green in the capture.

Step 70 swept the 100-300 band - 93 rows, the last stretch of
the gate with no verdict on any of them - and the sweep ran as
scan, not eyeballs. Each row's diff image had its matching
background dilated 1 px inward twice, which eats every hairline
a stroke edge or glyph stem leaves and preserves any solid
region of 100 px or more. The band answered with nothing:
ninety-three rows, zero surviving components - no mispainted
fill, no missing element, no misplaced swatch. The scan's floor
is a 14x14 block, and a row's whole diff budget in the band is
at most 299 pixels, so no real content change the band could
hold hides under it; the detector was calibrated against known
solids, where the script squares of `styling-pres-02-f` light
up fourteen times at 256 px each.

The one flag earned its hand-read: `animate-script-elem-01-b`
diffs to a single 30x30 square at (12, 52) - the fixture's
upper result rect, black in our static render and green in the
capture, the state only its script's probe reaches after a
second of waiting. Step 67's kind of ceiling, recorded with the
band.

Step 71 gave the working image an address. `Raster` had a width
and a height but no origin, so every offscreen was the page and a
source graphic lying outside it never reached a chain - the
deferred list's named fix, closed as named: a raster now carries
`ox, oy`, the device position of its pixel (0,0), and
`rasterFrom`/`bitmapFrom`/`blendPM`/`clipTo` all honour it.
The region arrives first, and where it sticks past the page edge
the offscreen becomes page union region, the union's corner the
raster's origin, with the subtree repainted into it once;
`postTranslate` carries the shift because the CTM may ride a
scale. Inside the chain the primitive boxes stay raster-local and
`toLocal` shifts each device box at the call site, while
feTurbulence's lattice anchor and the light positions get the
origin handed back, so a chain spanning the padding samples the
same noise and the same specular surface as a page-aligned one.
A row whose region fits the page keeps the old page-aligned
buffer untouched: the gate moved exactly one line, and all
forty-three `filters` rows held. `filters-offset-02-b` landed at
87 - the third box's lime square now spans its full shifted
width, and the 87 that remain are the fixture's own 1-px hairline
rings, drawn identically around the two boxes this step never
touched. 526 rows, 2,628,280 AE, that one line -2,425.

Step 72 shipped a different feature from the one its lead named.
The lead chased render.d's own comment - text markers "not
supported (yet)" - but §11.6.1 and the §11.6.3 property tables
attach `marker-start`/`marker-mid`/`marker-end` to path, line,
polyline and polygon alone; the `<text>` attribute summary's
wholesale listing is the spec contradicting itself, SVG 2 dropped
those properties from text, and the references agree - no capture
draws a marker on a text vertex. The comment now records that
finding in place of the phantom gap.

The feature that shipped is the one text feature the suite tests
and the renderer lacked: §10.12's `text-decoration`. The property
table says it does not inherit while the prose makes a decoration
cover the specifying element's content and its descendants until
one specifies its own, so the effective bits - 1 underline,
2 overline, 4 line-through - ride the style copy and only a fresh
specification replaces them. The lines paint with the specifying
element's own fill and stroke, so each specifying element's
resolved style, after its currentColor binding, is snapshotted
into an append-only vector and the bits carry that index; the
use-scope swap tags and restores that vector's url() paints
exactly as it does the style stack's. `blink` parses and draws
nothing - SE does not require viewers to support it, and a static
line for a flashing one would be a lie.

A run's line spans its placed glyphs - the positioning lists and
advances the layout pass committed to - and rides the alphabetic
line the outlines ride; underline and overline land under the
run's fill and stroke, line-through over it. A run on a path
draws none: SE defines no curved decoration and no test decorates
a textPath. A clip-mask pass draws none: §14.3.5 gives the clip
the element's geometry, and a decoration is paint, not geometry.
SE leaves the lines' offset and thickness implementation-defined,
so they are fitted: the underline bar spans -0.040em..+0.045em
about the baseline and the strike bar -0.330em..-0.270em, both on
the named fixture. The captures disagree about the underline -
text-text-03-b's fs32 reference drew it a tenth of an em deeper
below the baseline, the work of a capture font with a lower
underline position - and no single em placement serves both, so
text-deco-01-b, the test written for this property, wins and
03-b pays for the miss: 1,087 -> 1,203. `text-deco-01-b` fell
951 -> 690. 526 rows, 2,628,135 AE, two lines moved: -261 and
+116.

Step 73 laid out §10.7.1's vertical text. `writing-mode` parses
lr-tb/rl-tb/tb-rl/tb-lr and the lr/rl/tb abbreviations, and
`glyph-orientation-vertical` takes auto or an angle; both ride
the inherited style copy like every other property here, so the
suite's habit of setting them on <g> tags spans whole subtrees.
tb-rl turns the line on end: the inline axis becomes y, the cross
axis x, the positioning lists swap roles - x and dx pin a glyph
across its column, y and dy push it down the page - and
text-anchor slides a chunk's whole chain of glyph boxes along y
instead of x.

The placement came back from the captures pixel by pixel. A tb
run's glyphs ride one-em boxes with their top edges at the y
position - dominant-baseline's rise plays no part - and every
glyph, upright or turned, centres its ink box on the vertical
baseline: all of 05-b's ink centres land on the
column's x whatever the side bearings, so advance-box centring
is out by half a side bearing's sum. Upright glyphs stand on
their box's bottom edge and advance exactly one em; turned ones
hang from the top edge, a quarter turn (or the orientation
angle) with §10.5's rotate value added on top as on a path,
advancing by their own advance widths. baseline-shift moves the
glyph across instead of up - +x, which is 06-b's pass text
spelled out: '7' offset slightly right, super right, sub and
-70% left. `auto` stands a glyph upright when its script is one
the tc609 upright table keeps square; the blocks stored here
are Han, kana, Hangul, Yi and the fullwidth punctuation living
among them, which covers every vertical sample the suite has.

The two tb captures disagree about line pitch and the engine
picks a side. 05-b stacks upright Latin a full em apart - its
baselines sit exactly on the y + em grid - while 06-b stacks at
its face's ascent-plus-descent (27.4 at fs24) and, quirkier,
drifts every glyph after the baseline-shifted '7' down the
column, its capture pen having followed the shift. One em wins:
the test written for text-anchor then lands glyph for glyph
(1,196 -> 207), and 06-b pays the difference twice, pitch and
pen drift both left unemulated - 2,533 -> 2,319.

Four known gaps stay open. Decorations draw nothing on a
vertical run: SE rules them along horizontal baselines,
defines no vertical equivalent, and no sample decorates a tb
run. rl-tb - text-intro-10-f - parses and stores but keeps
flowing left-to-right, because SE bundles that mode's inline
reversal with the bidirectional shaping the renderer does not
run; reversing unshaped Arabic only trades one wrong for
another, and 10-f holds its 6,823. SVG font runs, altGlyph runs
and textLength never take the vertical branch - no vertical
sample uses them. And text-intro-03-b stays as transparent as
it was before the step: its font list - 'Arial Unicode MS',
'LucidaSansUnicode', 'MS-Gothic' - names no face this host
carries, so not one glyph is produced and its 164.5 K is the
CJK host-font ceiling entire; the earlier lead's content
budget was a guess at a rendering this suite never draws. 526
rows, 2,626,932 AE, two rows moved: -989 and -214.

Step 74 is marker viewport overflow, and it was chosen by
histogram rather than hunch. Per-colour pixel counts split the
four remaining painting-marker rows into three different animals.
-03-f and -04-f turned out byte-identical in their marker
content: royalblue 832 = 832 in 03-f, 416 = 416 in 04-f, red 0 =
0 in both - the capture never painted the `marker` shorthand's
squares either, so implementing the shorthand would buy nothing.
Their diffs are one-pixel AA fringes where the reference's two
coincident quadratic-curve strokes rasterise as hairline pairs
we merge into one band, plus the two rev-skewed revision labels:
host raster phase, ceiling. -05-f's per-column counts showed
exactly one misaligned column - `overflow="auto"`, unclipped at
819 blue and 800 purple in the capture against our clipped 110
and 324 - and the fixture's own pass criteria pin that column:
"the columns labeled 'visible' and 'auto' show markers without
clipping them". §7.8 hands 'auto' to the user agent; Batik's
answer is visible, and a marker viewport grows no scrollbars in
any engine. The marker clip now skips for visible and auto and
clips for hidden, scroll and no attribute at all (a marker
viewport's UA default is hidden), with a unit test pinning the
five-value matrix. 05-f went 731 -> 232; the residue is the
clipped columns' viewport standing one device pixel short - a
9.6-px viewport maps through canvas `clipRect`'s `.round()` to
nine - and any change to that rounding moves every viewport,
mask and clipPath clip in the suite at once, so it waits.

-02-f, by contrast, got reopened. Step 67 recorded its marker
squares as "pixel-exact under crops", which is true of the first
row and no longer of the rest: the capture paints 810 pure-blue
and 486 green pixels that we do not, because its marker3 and
marker4 contents hang inside a `<g fill="green" stroke="blue"
stroke-width="8">` and §11.6.2 inherits the defining site's
ancestors into marker content while `renderMarker` pushes only
the href chain. And the fixture's hand-expanded "equivalent SVG"
columns disagree with their own marker columns in the capture:
under `scale(8)` with a 2x2 userSpaceOnUse clipPath the capture
draws 16-px squares where we draw 2-px dots. Both halves want
forensics of their own before either wants a fix. Total
2,626,932 -> 2,626,433 over 526 rows, no ERROR, one row moved.

Step 75 - font-weight: the relative keywords and the raw
numeric scale. The lead said §16.3's `font-variant`; the
forensics rerouted it. Nothing about font-variant is missing:
CSS2 §15.2 step 2 lets a family's small-caps-only face answer
a normal-face request, so 203-t's five
`font-variant="small-caps"` ZC faces match as plain faces and
the attribute carries no consequence the suite can observe.
What the capture actually drew, measured stem by stem, was
the two relative rows disagreeing with us: "Blue is bolder"
under a parent normal paints the family's semibold ZCSB
(weight 600) and "Blue is lighter" under a parent bold paints
the regular ZCR (400). Neither row rendered right because
render.d never parsed the keywords at all - `bolder` and
`lighter` fell through to `to!int`, threw, and the inherited
weight stood. The weight-digits column, pixel-exact once the
fix landed, exposed the second bug: numeric weights collapsed
into the engine's five enum buckets before SVG face matching,
and the bucket re-expanded Bold back to 700 - a family with
faces at 300/400/600/700/800 answered a 600 request with its
700 face.

The fix carries the raw number down the cascade in a new
`Style.rawWeight`, re-derives the five buckets from it so the
host TrueType path cannot shift, and hands the number to
`matchFace` directly; its existing CSS walk prefers an exact
weight, lighter ones below 400, and 400-first in the middle.
The keywords step the inherited number by 200 - bolder +200
capped at 900, lighter -200 floored at 100 - and children
inherit the calculated weight, not the keyword, exactly as
CSS2 §15.6 words it. That ladder plus the face walk (a
calculated 500 prefers the 400 face) is the only rule that
fits both captured cells: CSS2 (1998) §15.6's table paints
700 for bolder-at-400, a face the digit column gives 4-5 px
stems against the capture's 3-4, and CSS2.1 paints 600 for
lighter-at-700 where the capture's 2 px is the regular face.

The gate proved the rule: bolder-at-400 onto the 600 face
took the bolder row pixel-exact, lighter-at-700 through 500
took the lighter row pixel-exact, and raw numeric matching
put the whole digits column exact - 203-t 1,891 -> 45, the
residue its rev-skewed label and hairline AA. A full-suite
run moved exactly that one row. The same rows in 02-t, 202-t
and 204-t stayed pixel-identical: those families resolve to
host fallback faces that answer both weight buckets with the
same outlines, so the fix is invisible there; host-font debt
already catalogued. A unittest builds 203-t's five-face
family and pins the cells - exact 600, bolder-at-400 on the
600 face, lighter-at-700 through 500 onto the 400 face,
chained bolder off the calculated number, and both fallback
walks. Full gate: 526 rows, no ERROR, total 2,626,433 ->
2,624,587.

Step 76 - markers: inheritance from the defining site. The
backlog pair split: this step takes §11.6.2; the expansion
column's clip goes to the next one. Per-region colour counts
settled the rule: the capture's marker3 columns paint 243
green fill px each and its marker4 columns 405 blue stroke px
each - exactly the `fill="green" stroke="blue"
stroke-width="8"` of the g the two markers hang under, with
the rects' own `stroke="black"` / `fill="black"` overriding
on top, while the referrer's orange fill and purple 4-wide
stroke stay out of those columns entirely. Marker contents
compute from the marker's own document ancestors - the other
rule from the clipPath/mask subtrees, whose chain-only
seeding (masking-path-12-f) stays.

`renderMarker` walks the cssParent ancestry map from the
marker element up to the pseudo-root and pushes each
ancestor's attrs onto the detached renderer before the href
chain; the map is keyed by arena index, so it knows the
marker's parents wherever the marker was referenced. Only
properties ride in: pushStyle cascades a `transform` onto the
canvas as it goes, so the matrix built for the vertex is put
back once the walk is done, and a defining-site transform
moves nothing. Defining-site `display="none"` is harmless the
same way - display never enters the Style, the element walk
drops subtrees, and the marker walk starts at the marker's
children (07-f unchanged at 0). The gate agreed with the
split: 02-f 1,079 -> 848, and the whole residue is the
expanded columns' clip dots. A unittest pins the rule:
defining-site green fill and blue ring (8-wide scaled by
0.4 through the marker viewBox), the referrer's orange and
purple nowhere inside the box, the rect's own black stroke
beating the inherited blue, and a translate(60,60) on the
defining group moving nothing. Full gate: 526 rows, no ERROR,
total 2,624,587 -> 2,624,356.

Up next - step 77: the other half of `painting-marker-02-f`
(848) and the last thing its 2011 forensics located. Its
hand-expanded "equivalent SVG" columns reference the 2x2 and
4x4 `clipPathUnits="userSpaceOnUse"` clips from inside
`scale(8)` / `scale(4)` groups: §11.1.3 reads userSpaceOnUse
as the user space of the element referencing the clipPath,
the group's own transform included, so the captures clip to
16 device px there while we clip to 2 and 4 - the clip is not
riding the transform at the referencing site. The masking
rows have to be watched while it moves.

## Deferred / accepted ceilings (do not chase)

- `struct-dom` (228 K) / `types-dom` (39 K): SVG DOM and scripting
  end-states — a CLI renderer has no DOM API surface; verdicts stay as-is.
  `struct-dom-07-f` (8.0 K) is one of them: its `onload` script paints the
  three cloned squares green where the file authors them red, so step 50's
  viewport clip moving it 26 AE is a stroke edge on pixels that already
  disagree in colour.
  struct-image-11-b (22 K) belongs here too: the references were captured
  after the W3C checker clicked every `<image>` (`onclick` makeGreen), so
  the correct static (blue) state can never match.
  extend-namespace-01-f (23.6 K) is the same class: its pie chart is built
  at load by ECMAScript from the `bd:` business data (`getElementsByTagNameNS`,
  then `createElementNS` arcs), so the reference is a post-script state no
  static render reaches - the foreign-namespace half of it, ignoring the
  `bd:` elements, is already right.
  paths-dom-02-f (5.5 K) is that class in one cluster: the root carries
  `onload="CreatePath();setTimeout('AnimatePath();', 500);"` and the
  flower it is scored against is the path that script builds, so the
  static markup has no `d` to draw and its 168x194 block is unreachably
  dynamic.
- `conform-viewers` (14 K): references captured after script-driven viewer
  zoom/pan (`onload` handlers, `viewport.zoomAndPan`) — scripting end-states
  again; step 8's viewport sizing did not move them.
- `interact-*`: pointer events / interactivity — out of scope.
  `styling-css-06-b` (7.9 K) is the same wall wearing a CSS name: it is
  the suite's `:visited` / `:hover` / `:focus` test, and its one 269x60
  block is the row of links whose fill depends on browsing history and a
  pointing device - UA state no headless render has.
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
  so the delta is the activation, not the paint. `animate-elem-29-b`
  (10.7 K) is that pair's third member: its 180x180 `#080` square sits at
  `fill-opacity="0"` until the same `<a xlink:href="#fadein">` click
  starts a second `begin="indefinite"` fade, and its reference shows the
  fade frozen at 1 - so the square's whole area counts as a delta here.
  `text-tselect-02-f` (4.2 K) is that class at text size: its two 91x70
  blocks are the `startIndex`/`numChars` selection its `onclick` handlers
  drive through `selectSubString`, over a run of Hebrew letters under a host
  font, and no static state of the file shows it.
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
  `imp-path-01-f` (5.1 K since step 42) is a second member of that class:
  4,748 of its 5,055 is that same y=0..25 band. `text-ws-01-t` (5.3 K),
  `-02-t` (6.4 K), `-03-t` (5.0 K) and `fonts-glyph-03-t` (6.2 K) are that
  band and nothing else: each has exactly one diff cluster, 9,556-9,563 px
  of y=1..22, and what remains of the four rows is 435, 456, 153 and 0 raw
  pixels - their §10.2.1 whitespace and their glyph runs are at their floor.
  `fonts-desc-04-t` (5.0 K) and `fonts-desc-05-t` (5.0 K), measured at step
  57, are that band alone: 9,063 diff pixels of their 9,063 and 9,108, all of
  it x=2..478 y=2..20, so the `<font>` boxes, their `missing-glyph` outlines
  and the `units-per-em` scaling they test are already exact.
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
- struct-use-06-b (30 K) / 07-b (36 K): external-reference
  tests where step 11 renders to spec but the archived references do not.
  06-b's body still carries its own "external use isn't implemented, show
  red rects" fallback *under* the clones, and its reference was captured by
  a UA that showed exactly that fallback, so the correct lime external
  rect now paints over it (+6.8 K at the step-11 rebase); its second clone
  aims at the external `svg-root` itself, whose 450x450 lime square is
  scaled into that `use` element's own 122x122. 04-b left this list at
  step 63: the colors its reference shows - fuchsia, blue, green, gold -
  arrive from that external file's own `xml-stylesheet` PI, and §6.9
  says a user agent applies it. 07-b's nested-`<svg>` fit is already
  handled to §7.7, and its capture is the post-click state: every
  rectangle turned blue by the file's own `onclick` handlers. That makes
  it a member of the script family, like `struct-use-13-f` (6.8 K), whose
  capture is the state its `<script>` builds at load with DOM edits, and
  `struct-svg-01-f` (670), whose red FAIL text sits in the markup and is
  hidden only by the pass script. 06-b's own label
  reads `$Revision: 1.4 $` against the 1.5 file in `suite/`, and step 50's
  viewport clip costs 9 AE there - the outer half of that 122x122 clone's
  stroke, trimmed at the instance's viewport.
- The four scripting rows this list had assumed without ever rendering,
  measured at step 67: `animate-dom-01-f` (1,356) and `animate-dom-02-f`
  (404) are the indicator squares only a script could draw - the
  `getStartTime()` column and the `ElementTimeControl` box - planted on
  pages that otherwise agree but for the `$Revision` line.
  `script-specify-01-f` (963) / `-02-f` (411) ask that a bogus-language
  script NOT run, which is exactly what this engine does - both renders
  paint "Good, script didn't run." in the green the pass criteria ask
  for - but their captures answer to older revisions of the files: the
  01-f PNG lays out a "Click on target" line the current markup no
  longer contains, and 02-f's title is worded differently there. Stale
  captures over an absent scripting model, twice over. Measured the same
  step, `pservers-pattern-01-b` (2,198) is a ceiling of another kind:
  its pattern rects, fill tile and stroke tile alike, land pixel for
  pixel, and every pixel of the remainder is a `font-family="Arial"`
  caption - host-glyph debt like every other Arial row in the suite.
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
  precedence. `styling-pres-04-f` (14.3 K) belongs to that group: its
  reference is byte-identical to pres-05-f's, the same empty page down
  to the md5, so neither capture holds a shape - while 04-f's own
  inline `<style>` asks for the same all-green answer through
  descendant, child and adjacency selectors, and we paint it.
  `styling-pres-03-f` (7.3 K) is the same kind of mismatch one level
  up: the archived capture is of test revision 1.4, whose body element
  is `fill="red"` carrying an inline `fill: none`, so that page is
  white; the SVG in `suite/` is revision 1.3, whose same element says
  `style="fill: green"`, so we paint a 200x100 green rectangle there -
  which is what 1.3 asks, the style attribute outranking the
  presentation attribute (§6.6) - and the row sets our `$Revision:
  1.3 $` label against the capture's `$Revision: 1.4 $`.
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
- `filters-offset-02-b` (87): closed at step 71 by giving the filter
  rasters an origin and padding the scratch past the page edge, as this
  bullet planned; the third box's lime square reaches the chain, and what
  is left of the row is 1-px hairline rings drawn identically around all
  four boxes, two of them untouched.
- Gradient ramps that change colour across a `stop-opacity` change
  (`pservers-grad-13-b` 0.9 K, `-05-b` 0.6 K, `-18-b` 0.7 K): the archived
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
  `text-text-08-b` (15.1 K), triaged at step 42, is the substitution half of
  that floor: 13.7 K of it lies in its four Verdana text bands, 2,002 in the
  y=0..20 band where its 1-unit `test-frame` ring is the half-pixel stroker
  convention recorded under step 27, and 298 at y>=340. Its blue there
  reads `#0000FE80` against the reference's `#0000FF80`, inside the
  compare's fuzz, so the opacity halves themselves cost no AE.
  `filters-color-01-b`'s 2,480, all that is left of it once step 43 put
  its five panels at AE 0, is that same floor: ~1.9 K across its five
  Verdana labels, and ~540 in the frame ring.
- `painting-stroke-06-t` (869) is what steps 47 and 59 left of it, and the
  rest is not a feature - step 59 carries its dash boundaries along with
  the band, 1,208 -> 869. Cropped to its two dash rows, ours and the
  reference put the dashes at the same places and the same widths; what
  is left is the 1-px decision every dash boundary makes under
  `scale(1.8)`, where a 5-unit dash is 9 device pixels wide and a
  2-unit one 3.6 - which is where all of it sits, y=99..117 (the
  `5,2,5,5,2,5` pair) and y=153..171 (`2` with `stroke-dashoffset="2"`).
- The split-frame captures: in `painting-stroke-05-t` (1,855),
  `text-fonts-202-t` (5,360) and `filters-light-02-f` (134,982) the
  1-px `test-frame` is two half-covered pixels, the corner-sampled
  answer step 56 moved away from, and what is left of each row is its
  thin-stroke sweep and the host-font AA around it. Those three pay
  +651, +418 and +53 and five more rows a handful each, the 1,144 AE
  step 56 spends against the 248,745 it recovers - matching both
  captures' conventions at once would be a per-file raster policy.
  Step 59 widens that family: `painting-stroke-05-t` is the test that
  *probes* widths, and there every band is split symmetrically about its
  own centre line and quantized to 1/8 - 64/64 at width 0.5, 255/255 at
  2.1, mass conserved, no half-covered boundary pixel anywhere - so its
  sweep pays +1,120 on top. `masking-path-02-b` (229, +187) splits the
  same way at width 4, full pixels at 48..51 where the shifted band
  half-covers 48 and 52, though its own `test-frame` follows the shifted
  hairline convention like the majority's. Step 60 meets the same split at
  turned and non-uniform CTMs: `paths-data-18-f` (473, +429) integrates
  its 8-device-px band under `scale(8, 2)` as rows 46..53 with no edge
  half-covered at all, and the +64, +65 and +94 that `pservers-grad-17-b`,
  `pservers-grad-20-b` and `filters-light-02-f` pay sit on quarter-turn
  bands the capture leaves where they are. The split recurs *along* a
  stroke rather than across it: at `struct-group-03-t`'s dashed sample at
  x=199 the capture's every dash runs one device pixel longer than ours -
  160..165 against 160..164, 170..172 against 170..171, and so on down,
  with the phase and the pattern identical in both of the test's rows -
  so each dash end carries half a pixel the capture lights and our
  step-reduction does not.
- `render-groups-01-b` (195) is what step 58 left, and all of it is one
  column: 144 raw px at x=435, y=135..278, down the `<image>`'s right
  edge, which lands on 435.6 and is a fill edge, so the band shift
  neither reaches it nor should. Its 1.8-device-px frame and the guide
  lines under the grey rect went with step 59's band.
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
- `masking-path-06-b` (7,584): the suite's only `clip="rect(...)"` row, and its
  reference is Batik's from-each-edge inset rather than the CSS 2.1 §11.1.2
  geometry §14.3.3 imports. There `rect(<top>,<right>,<bottom>,<left>)` are
  offsets from the top and left border edges, all four from one point, so
  `rect(10,10,10,10)` is zero-area and a conformant render paints no image at
  all. Census: we paint 68,317 opaque pixels, the reference 54,772, and the gap
  is exactly the 10-unit border of the two 200x120 image boxes; the spec's
  reading would drop all 48,000 image pixels and put the row near 35 K.
- `filters-composite-03-f` (8,731): arithmetic feComposite, including its
  FillPaint/StrokePaint inputs, is right - the identical and clamped squares
  compare at AE 0. The two that miss are semi-transparent (alpha 0.5 for
  `2F - 1.5F`, 0.6 black for `-0.5F - 0.1`) and each reference pixel is ours
  composited over white: (127,255,127) and (102,102,102), opaque. Flattening
  both sides over white collapses the row to 2,386, the AA of the three guide
  rings; the harness composites nothing, so the alpha gap stays as the AE.
- The paint-server pair in `filters-overview-03-b` (FillPaint 1,452 and
  StrokePaint 2,442, 3,894 of the row's 6,144): ours paints the target's
  paint over the whole region - §15.7.2's "conceptually infinite
  extent" - with the target's bbox as the gradient's basis and the §4.5
  pad past its ends. That reproduces the file's axis and stop list at
  every sample down to t=0.52: over a bbox of y=60..135 its
  `y1="-3%" y2="106%"` is a period of 81.75, and at y=100 the reference
  reads (241,114,146) against our (254,123,123). Past the red stop at
  offset 0.67 the reference turns blue - (0,0,253) from y=120 to y=145 -
  where the file's last stop is `#ffff00` at offset 1.0, so that wrap
  cannot come from the file's own stop list and no `spreadMethod` gives
  it: `pad` and `reflect` agree with ours until t=1 and `repeat` puts
  yellow at the seam. Keep our reading; the pair is the reference's.
- The twins `filters-overview-02-b` (5,633) and `filters-overview-03-b`
  (5,731) are that same pair counted twice: their diff-cluster profiles
  are byte-identical - 10,829 and 5,926 raw pixels in the two 122x102
  boxes at x=317..438, 989 of DRAFT band, one 18x16 revision label and
  four small text clusters - and only the servers differ, `grad1`/`grad2`
  in `userSpaceOnUse` here against `grad1`'s objectBoundingBox there. Our
  FillPaint/StrokePaint rasteriser fills the whole region with that
  server at a near-uniform alpha of ~150, and no reading of the server
  explains the capture: `grad2` runs y=192.75..274.5 with white at 0.33,
  red at 0.67 and yellow at 1.0, while the capture's lower box is flat
  blue straight through y=195..275. Step 52 moved both rows; what is
  left of them is the bullet above, twice.
- `filters-blend-01-b` (7,426) is shape-right and a hair off colour
  everywhere at once: its clusters are the whole 360x294 union of the
  overlapping circles - 36,623 raw pixels, 7,426 of them past the 10%
  fuzz - plus two 119x30 bands, with no edge or extent disagreement
  anywhere, which is what a mode-arithmetic gap looks like; and its PNG
  says `$Revision: 1.7 $` against 1.9 in `suite/`, so the field being
  scored is markup that changed under it.
- Stale captures: the archived PNG is of an *older test revision* than the
  SVG in `suite/`, so the row is scored against markup that no longer
  exists. Reading each montage's own `$Revision:` label sorts the family:
  `conform-viewers-02-f` (7.8 K) 1.2 against 1.6, its page the script-driven
  `viewport.zoomAndPan` state the class note above already covers;
  `masking-path-08-b` (0.7 K) is 1.1 against 1.7, but both of its whole
  squares are gone now - step 53 took the broken-clip one, step 54 the
  `visibility="hidden"` clip child - and what remains is half-pixel edges;
  `color-prof-01-f` (6.8 K) 1.5 against 1.9, DRAFT band included, which also
  retires step 46's "still waits on a profile reader" reading of it;
  `imp-path-01-f` (5.1 K) 1.3 against 1.5; `pservers-pattern-02-f` (4.0 K)
  1.2 against 1.3 - and there an independent lattice built from the 1.3
  markup, 48-unit tiles at objectBoundingBox 0.1 of a 480x480 rect, its
  `viewBox` at 0.48, `patternTransform=rotate(45)` about the origin, blue in
  the two off-diagonal quadrants, agrees with our render over the interior
  to 341 antialiased pixels while the capture sits 10,222 away, so the tile
  phase is the capture's. `filters-image-02-b` (5.5 K) is that drift plus a
  timeline: 1.1 against our 1.9, and both of its boxes hold the *pink*
  squid, the state its `<set attributeName="xlink:href"
  to="../images/pinksquidj.png" begin="2s">` reaches 2 s in - the authored
  state, ours, is the blue one. Its `feImage` box and its `<image>` twin
  land at the reference's place and size, so the fit is right and the
  colour is the capture's. `filters-gauss-01-b` (632 after step 51) is
  the same drift: its PNG says `$Revision: 1.6 $` and `suite/` holds 1.7.
  `text-align-07-t` (6.3 K) drifts the other way - its PNG carries the
  black test frame but *no* DRAFT band at all, while the 1.9 file still
  has the group: 9,556 of its 11,608 raw diff pixels are that empty red
  strip. The rest is hairline placement - the 1-px guide lines are
  opaque on one row in the capture and split 127/127 over two in ours,
  the same question the step-56 lead takes up.

- Step 69's 300-1,500 sweep measured its twelve ceiling rows, and
  the captions own most of them: `filters-comptran-01-b` (1,413),
  `coords-units-01-b` (785) and `painting-render-01-b` (371) put
  the entire diff in text rows - the filter outputs, the unit
  squares and all three `color-interpolation` bars match, the
  linearRGB ramp to within one LSB (`5D00F2` against `5E00F2`),
  so only the caption glyphs move. `text-align-01-b` (841) and
  `-05-b` (1,196), `struct-cond-02-t` (319) and `text-text-12-t`
  (1,383) join the host-glyph floor with their anchors and
  conditional branches landed right: doubled letter shapes at
  matching extents.
- `text-align-08-b` (10,407) is that floor one level deeper - the
  fixture is status="issue" and its capture is not reproducible from
  the resources it ships. The test pins §10.9.2's script baselines,
  and our render is spec-exact against the suite's own `Tribase.svg`:
  rect 60x84 px at font-size 120, advance 60, all glyphs on the
  alphabetic line. The capture shows the *baselines* right - rect
  bottom on the alphabetic guide, the CJK ideograph's base on the
  fuchsia ideographic line, the Devanagari hanging from the green
  guide - but reads Tribase through Batik/AWT's SVG-Tiny font path
  and draws the same three shapes at unreproducible metrics: rect
  77x104 px, triangles 69 wide x 126 tall, per-glyph advances 73-78
  px instead of 60. No single scale fits those shapes to Tribase's
  outlines (the capture's own 120/75/30 size groups are mutually
  inconsistent too), and the advance drift leaves every glyph 18-45
  px off horizontally, so implementing the script baselines on
  Tribase's real numbers would still miss the capture - only
  emulating the Batik reader's quirks would land it. Its per-region
  split is catalogued: the DRAFT band is ~8.5 K (this capture has
  *no* band at all, so that half is the negative-reference class),
  the revision label 833, and the glyph block 4,984.
- `styling-pres-02-f` (703) is step 67's script kind: its
  fourteen indicator rects sit black in the markup - "black if
  the sub-test did not run" - and green in the capture, and
  every text label matches.
- `painting-marker-03-f` (1,429) and `-04-f` (1,408) closed at step 74
  as raster-phase twins: their marker content matches the captures to
  the pixel (royalblue 832 = 832, 416 = 416, red 0 = 0 - neither engine
  paints the `marker` shorthand), and what diffs is hairline pairs
  along coincident quadratic-curve stroke edges where the capture
  doubles its own strokes, plus the rev-skewed label rows.
  `painting-marker-05-f` (232) is residue only: its clipped columns'
  marker viewports stand one device pixel short, 9.6 rounding to 9
  through canvas `clipRect`, and that rounding is shared by every
  viewport, mask and clipPath clip in the engine.
- The rest is verified content at the stroker's edge:
  `painting-marker-02-f`'s first row places every marker pixel-exact
  under crops, squares and `refX` centring identical - step 76 settled
  its inheritance half and closed the marker columns; the 848 that is
  left rides the clipPath feature in Up next;
  `render-elems-07-t` (802) and `-08-t` (746), static-render tests with
  no timeline excuse, diff to the whole spiral outline doubled at a
  pixel;
  `linking-a-05-t` (572) is 04-t's family - arrow outlines plus
  revision glyph; and `struct-image-19-f` (682) and
  `conform-viewers-01-t` (670) are DRAFT bands over doubled
  outlines. `masking-path-07-b` (1,038) is caption debt three
  times over: its revision row - same `1.11` string both sides -
  is 458 AE of glyph drift by itself, with the leaf and circle
  clip results and the dashed guides exact to the edge.

- The 100-300 band scanned whole at step 70 - 93 rows, every one
  hairline residue of the settled families (frame-ring splits,
  dash-end halves, caption glyph specks), no solid diff region
  anywhere in the band. `animate-script-elem-01-b` (113) is
  lone-flagged by the scan and is the script-indicator family
  again: its upper result square sits black in the static
  markup and green in the capture, which only a second of
  script running turns.

## Backlog (small, opportunistic)

- Not the filters' colour space, their arithmetic: `filter.d` keeps the §15.2
  linearRGB working space already - `rasterFrom` decodes, `bitmapFrom` encodes,
  `color-interpolation-filters="sRGB"` flips the flag at `makeFilter` - and
  what looked like arithmetic in `filters-conv-03-f`'s 308x77 band was a parse
  failure, which step 35 closed. What is left of that row is two script panels
  (4,516 of it) plus 334 of sharpening the bird itself, unexamined - step 36
  moved the convolve's edge box and that 334 did not blink.
