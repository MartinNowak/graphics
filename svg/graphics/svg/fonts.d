module graphics.svg.fonts;

import std.algorithm, std.ascii, std.conv, std.file, std.math, std.range, std.string, std.utf;
import graphics.core.path;
import graphics.svg.core : addSVGPath;
import graphics.svg.css : resolveHref, sheetFaces;
import graphics.svg.parser;

////////////////////////////////////////////////////////////////////////////////
// SVG fonts (SVG 1.1 ch. 20): the <font>/<font-face>/<glyph>/<hkern> store.
//
// A font is collected once per document - inline <font> elements plus the
// standalone <font-face> references (§20.8.5) that pull a <font> out of an
// external file - and indexed by the lower-cased family name it registers
// under. Glyph outlines are pre-parsed from the `d` mini-language into a
// Path kept in FONT UNITS with y up; the renderer scales, flips and
// translates them per paint, so nothing here knows about user space
// beyond the registration ranges.
////////////////////////////////////////////////////////////////////////////////

/// A closed code point interval; a single character has lo == hi.
struct CharRange
{
    dchar lo, hi;
}

/// One side of an hkern pair (§20.7): the total set of glyphs is the
/// UNION of the characters named by u1/u2 (CSS2 ranges and `?`
/// wildcards included) and the glyphs named by g1/g2.
struct KernSet
{
    CharRange[] chars;
    string[] names; // glyph-name values
}

struct SvgKern
{
    KernSet first, second;
    float k; // font units; positive tightens the inter-glyph space
}

struct SvgGlyph
{
    Path d;       // font units, y up (empty when `d` is absent)
    bool hasD;
    float advX;
    // Vertical metrics (§20.4). Parsed with NaN standing for absent and
    // replaced by the parent font's settled defaults at the end of
    // parseFont, so callers see a settled value either way.
    float vertAdvY = float.nan;
    float vertOriginX = float.nan;
    float vertOriginY = float.nan;
    string id;    // id: what an altGlyph href names (§10.14.1)
    string name;  // glyph-name
    dchar[] uni;  // decoded `unicode` sequence; empty -> name-only glyph
}

struct SvgFont
{
    // font element (§20.3).
    float defaultAdv;      // horiz-adv-x: the glyph advance default
    float originX, originY; // horiz-origin-x/y: recorded, never a
                            // placement offset (see parseFont)
    // Vertical defaults (§20.3), settled by parseFont from their
    // absent spellings: vert-adv-y defaults to one em, vert-origin-x
    // to half the effective horiz-adv-x, vert-origin-y to the ascent.
    float vertAdvY = float.nan;
    float vertOriginX = float.nan;
    float vertOriginY = float.nan;

    // the face slot this font registers into (CSS font matching):
    // numeric CSS weight (400 normal, 700 bold) and 0 roman, 1 italic,
    // 2 oblique.
    int weight = 400;
    int faceStyle;
    // §16.2's variant axis: bit 0 normal, bit 1 small-caps. The
    // font-face attribute (and the @font-face descriptor) permits a
    // comma list naming both spellings, and a face answers a request
    // only when its list names that variant; absent, normal.
    int faceVariant = 1;
    // font-face metrics (§20.4), font units. ascent/descent anchor the
    // derived baseline rows; the four alignment attributes override them.
    float upem = 1000;
    float ascent, descent;
    float alphabetic;
    float ideographic, hanging, mathematical, xHeight;
    bool hasIdeographic, hasHanging, hasMathematical, hasXHeight;
    // §20.8.3's leftover face metrics: the three decoration band pairs
    // (the band's ideal position and thickness in font units, y up)
    // and the vertical baseline quartet - offsets relative to the
    // glyph's vert-origin-x, the line the vertical walk hangs the
    // slot on. The grammar is a bare <number> with no initial value,
    // so every row rides its has* flag: a band pair governs only
    // when both halves are spelled, and a vertical mode with no rows
    // keeps today's no-rise placement (§10.9.2's heuristics latitude).
    float underPos, underThk, overPos, overThk, strikePos, strikeThk;
    bool hasUnderPos, hasUnderThk, hasOverPos, hasOverThk,
         hasStrikePos, hasStrikeThk;
    float vAlphabetic, vHanging, vIdeographic, vMathematical;
    bool hasVAlphabetic, hasVHanging, hasVIdeographic, hasVMathematical;

    CharRange[] ranges; // registration range; empty = everything

    SvgGlyph[] glyphs;  // document order (§20.6: first match wins)
    SvgGlyph missing;   // missing-glyph (§20.5)
    bool hasMissing;
    SvgKern[] kerns;    // hkern: pairs for the horizontal modes
    SvgKern[] vkerns;   // vkern: pairs for the vertical modes

    bool covers(dchar ch) const
    {
        if (ranges.empty)
            return true;
        foreach (ref r; ranges)
            if (r.lo <= ch && ch <= r.hi)
                return true;
        return false;
    }

    /// §20.6: the first glyph whose `unicode` sequence matches the text
    /// at `i` (a two-char "SS" ligature beats the plain "S" only when
    /// defined earlier, so the scan is straight through the array).
    /// Falls back to the missing glyph; `consumed` is the number of BYTES
    /// the caller must advance.
    SvgGlyph* select(string text, size_t i, out size_t consumed)
    {
        foreach (ref g; glyphs)
            if (g.uni.length && matchesSeq(text, i, g.uni, consumed))
                return &g;
        size_t j = i;
        if (j < text.length)
            decode(text, j); // skip the one code point we cannot map
        consumed = j - i;
        return hasMissing ? &missing : null;
    }

    /// The glyph carrying this `id`, §10.14.1's other way in: an altGlyph
    /// href names the glyph element instead of a character, so a glyph with
    /// no `unicode` of its own - the shape an alt set exists for - is still
    /// reachable. Document order again, first match wins.
    SvgGlyph* byId(string id)
    {
        if (id.empty)
            return null;
        foreach (ref g; glyphs)
            if (g.id.length && g.id == id)
                return &g;
        return null;
    }

    /// §20.7: the k value of the first pair entry whose (first, second)
    /// sets contain the two glyphs, or 0. hkern answers the pair in the
    /// horizontal modes and vkern in the vertical ones; which table the
    /// caller reads is all `vertical` selects.
    float kernK(const(SvgGlyph)* a, const(SvgGlyph)* b, bool vertical) const
    {
        if (a is null || b is null)
            return 0;
        const(SvgKern)[] tab = vertical ? vkerns : kerns;
        foreach (ref kc; tab)
            if (inSet(kc.first, a) && inSet(kc.second, b))
                return kc.k;
        return 0;
    }

    static private bool matchesSeq(string text, size_t i, const dchar[] uni,
                                   out size_t consumed)
    {
        size_t j = i;
        foreach (ch; uni)
        {
            if (j >= text.length || decode(text, j) != ch)
                return false;
        }
        consumed = j - i;
        return true;
    }

    static private bool inSet(ref const KernSet set, const(SvgGlyph)* g)
    {
        foreach (name; set.names)
            if (g.name.length && g.name == name)
                return true;
        if (g.uni.length == 1) // character sets address single-char glyphs
            foreach (ref r; set.chars)
                if (r.lo <= g.uni[0] && g.uni[0] <= r.hi)
                    return true;
        return false;
    }
}

/// Every <font> element and every standalone <font-face> reference in the
/// document, in document order, grouped by the lower-cased family name:
/// a family holds its faces (normal/bold/italic) in declaration order,
/// and a later declaration of the same (weight, style, variant) slot
/// replaces the earlier one. External font files follow the <image>/@import rules:
/// plain paths resolved against `baseDir` (css.resolveHref), each file
/// parsed at most once. CSS @font-face rules ride the same road: their
/// descriptor names the family, and their src URI picks the <font>.
SvgFont*[][string] collectFonts(Document doc, string baseDir)
{
    SvgFont*[][string] reg;
    Document[string] loaded; // font file path -> parsed arena

    void put(string family, string range, SvgFont* f)
    {
        immutable key = toLower(strip(family));
        if (key.length && f !is null)
        {
            f.ranges = parseRanges(range);
            ref faces = reg.require(key, null); // construct-if-absent
            foreach (i, o; faces)
                if (o.weight == f.weight && o.faceStyle == f.faceStyle
                    && o.faceVariant == f.faceVariant)
                {
                    faces[i] = f; // same face slot: last declaration wins
                    return;
                }
            faces ~= f;
        }
    }

    // The fragment picks the <font id>; with no fragment, the file's
    // first <font>.
    SvgFont* fromFaceDoc(immutable(Element)[] nodes, size_t[string] ids,
                         string frag)
    {
        if (frag.length)
        {
            auto p = frag in ids;
            return p !is null && nodes[*p].name == "font"
                ? parseFont(nodes, *p) : null;
        }
        foreach (i, ref e; nodes)
            if (e.name == "font")
                return parseFont(nodes, i);
        return null;
    }

    void walk(size_t idx)
    {
        ref immutable(Element) e = doc.nodes[idx];
        switch (e.name)
        {
        case "font":
        {
            // Inline font: its own font-face names the family and (if
            // given) the registration range.
            string fam, range;
            foreach (ch; e.children)
            {
                ref immutable(Element) c = doc.nodes[ch];
                if (c.name == "font-face")
                {
                    if (auto p = "font-family" in c.attrs) fam = *p;
                    if (auto p = "unicode-range" in c.attrs) range = *p;
                    break;
                }
            }
            if (fam.length)
                put(fam, range, parseFont(doc.nodes, idx));
            return; // a font's subtree holds no other font markup
        }

        case "font-face":
        {
            // Only a face that ships its own font-face-src references a
            // font; a face inside a <font> went with the case above.
            size_t fs = Document.unknown;
            foreach (ch; e.children)
                if (doc.nodes[ch].name == "font-face-src") { fs = ch; break; }
            if (fs == Document.unknown)
                return;

            string fam, range;
            if (auto p = "font-family" in e.attrs) fam = *p;
            if (auto p = "unicode-range" in e.attrs) range = *p;

            SvgFont* found;
            foreach (uc; doc.nodes[fs].children) // sources, in order
            {
                ref immutable(Element) u = doc.nodes[uc];
                if (u.name != "font-face-uri")
                    continue;
                auto hp = "xlink:href" in u.attrs;
                if (hp is null)
                    hp = "href" in u.attrs;
                if (hp is null)
                    continue;

                string href = *hp, frag;
                auto h = find(href, '#');
                if (!h.empty) // a miss is an empty slice, and slices are
                {             // truthy even empty: test it, never `if (h)`
                    frag = h[1 .. $];
                    href = href[0 .. cast(ptrdiff_t)(h.ptr - href.ptr)];
                }
                if (href.empty) // same-document #id
                {
                    immutable t = doc.byId(frag);
                    if (t != Document.unknown && doc.nodes[t].name == "font")
                        found = parseFont(doc.nodes, t);
                }
                else if (auto path = resolveHref(baseDir, href))
                {
                    if (auto p = path in loaded)
                        found = fromFaceDoc(p.nodes, p.ids, frag);
                    else if (exists(path))
                    {
                        try
                        {
                            auto ext = parseSVG(readText(path));
                            loaded[path] = ext;
                            found = fromFaceDoc(ext.nodes, ext.ids, frag);
                        }
                        catch (Exception) {}
                    }
                }
                if (found !is null)
                    break; // first successful source wins (§20.8.4)
            }
            if (found !is null)
            {
                // the referencing face's own weight/style/variant name
                // the slot the referenced font registers into.
                found.weight = cssWeight(getAttr(e, "font-weight"));
                found.faceStyle = cssStyle(getAttr(e, "font-style"));
                found.faceVariant = cssVariant(getAttr(e, "font-variant"));
                put(fam, range, found);
            }
            return;
        }

        default:
            foreach (ch; e.children)
                walk(ch);
        }
    }

    walk(0); // the document pseudo-root

    // CSS @font-face rules (CSS 2.1 §5.5): the descriptor names the
    // family, and the font element it points at may carry no name of
    // its own, as the suite's fonts-elem-07-b writes one. The src URI
    // picks the <font> exactly the way a font-face-uri does - bare
    // fragment names this document's, a path loads a file - sharing
    // the loaded-file cache; a src that names no readable SVG font
    // (local(), a .ttf) contributes nothing. The descriptor's weight,
    // style and variant name the slot, and a face registered later
    // replaces an element's face of the same slot, last declaration
    // winning.
    foreach (fc; sheetFaces(doc, baseDir))
    {
        // A slice's truth is non-null, not non-empty, and `find` miss
        // is an empty slice at the end - so the found-test is spelled
        // out. (A bare `if (auto h = find(...))` is always true.)
        string href = fc.url, frag;
        auto h = find(href, '#');
        if (!h.empty)
        {
            frag = h[1 .. $];
            href = href[0 .. cast(ptrdiff_t)(h.ptr - href.ptr)];
        }

        SvgFont* found;
        if (href.empty) // same-document #id
        {
            immutable t = doc.byId(frag);
            if (t != Document.unknown && doc.nodes[t].name == "font")
                found = parseFont(doc.nodes, t);
        }
        else if (auto path = resolveHref(baseDir, href))
        {
            if (auto p = path in loaded)
                found = fromFaceDoc(p.nodes, p.ids, frag);
            else if (exists(path))
            {
                try
                {
                    auto ext = parseSVG(readText(path));
                    loaded[path] = ext;
                    found = fromFaceDoc(ext.nodes, ext.ids, frag);
                }
                catch (Exception) {} // not XML: a binary font, unreadable here
            }
        }
        if (found is null)
            continue;
        found.weight = cssWeight(fc.weight);
        found.faceStyle = cssStyle(fc.style);
        found.faceVariant = cssVariant(fc.variant);
        put(fc.family, "", found);
    }

    return reg;
}

/// CSS font matching, CSS2.1 §15.5 + CSS3 Fonts §5.2 reduced to the
/// slots SVG 1.1 faces can occupy: exact (weight, style) wins; weights
/// then search downward (<400 wants lighter first), upward (>500 wants
/// heavier first) or 400-first (middle); a roman request never borrows
/// a slanted face, and italic/oblique satisfy each other. The variant
/// axis (§16.2) filters rather than ranks: a face answers only a
/// request its own list names, so a family holding only the other
/// variant declines the whole family - on it fonts-desc-02-t's list
/// rows fall to the next name, and with no next name, to the fallback.
SvgFont* matchFace(SvgFont*[] faces, int weight, int style,
                   int variant = 1)
{
    SvgFont* best;
    int bestScore = int.max;
    foreach (f; faces)
    {
        if (!(f.faceVariant & variant))
            continue; // the axis is a filter, not a preference
        immutable s = styleRank(style, f.faceStyle) * 4096
                    + weightRank(weight, f.weight);
        if (s < bestScore) // ties: document order wins
        {
            bestScore = s;
            best = f;
        }
    }
    return best;
}

private int weightRank(int want, int w)
{
    if (want < 400)
        return w <= want ? want - w : 1000 + (w - want);
    if (want > 500)
        return w >= want ? w - want : 1000 + (want - w);
    return w <= 400 ? 400 - w : 1000 + (w - 500); // 400, then 500, 600...
}

private int styleRank(int want, int s)
{
    if (s == want)
        return 0;
    if (want != 0 && s != 0)
        return 1; // italic <-> oblique
    return want == 0 ? 2 : 1; // roman never borrows a slanted face
}

/// The font-face `font-weight` attribute: "normal"/"bold" or 100..900.
private int cssWeight(string v)
{
    if (v == "bold")
        return 700;
    if (v.empty || v == "normal" || v == "regular")
        return 400;
    try
    {
        immutable w = to!int(strip(v));
        return w >= 100 && w <= 900 ? w : 400;
    }
    catch (ConvException)
        return 400;
}

private int cssStyle(string v)
{
    return v == "italic" ? 1 : v == "oblique" ? 2 : 0;
}

/// The font-face `font-variant` attribute and the @font-face descriptor
/// of the same name (§16.2's list syntax): normal is bit 0, small-caps
/// bit 1, and a comma list naming both lets one face answer either
/// request. Absent, or nothing the grammar allows, is normal.
private int cssVariant(string v)
{
    int m;
    foreach (t; splitter(v, ','))
    {
        immutable head = strip(t);
        if (head == "small-caps")
            m |= 2;
        else if (head == "normal")
            m |= 1;
    }
    return m ? m : 1;
}

////////////////////////////////////////////////////////////////////////////////

/// Read one <font> subtree: face metrics, pre-parsed glyph outlines,
/// kern pairs and settled vertical metrics. Outlines stay in font
/// units (y up); §20.5 gives missing-glyph the same attribute meanings
/// as a glyph.
private SvgFont* parseFont(ref immutable(Element)[] nodes, size_t idx)
{
    auto f = new SvgFont;
    ref immutable(Element) fe = nodes[idx];
    f.defaultAdv = num(fe, "horiz-adv-x");
    // The accepted `fonts-elem-05-t` demands each outline's corner on
    // the pen whatever origin the font declares - its own third label
    // reads "horiz-origin-x=1000 but ignored" - so the pair is kept as
    // a declaration the engine records but never displaces outlines by.
    f.originX = num(fe, "horiz-origin-x");
    f.originY = num(fe, "horiz-origin-y");
    // §20.3: an absent vertical spelling stays absent until the face's
    // own metrics are in, and settles to the spec's fallback at the end.
    f.vertAdvY = num(fe, "vert-adv-y", float.nan);
    f.vertOriginX = num(fe, "vert-origin-x", float.nan);
    f.vertOriginY = num(fe, "vert-origin-y", float.nan);

    foreach (ch; fe.children)
    {
        ref immutable(Element) c = nodes[ch];
        switch (c.name)
        {
        case "font-face":
            f.upem = num(c, "units-per-em", 1000);
            if (f.upem <= 0)
                f.upem = 1000;
            f.ascent = num(c, "ascent");
            f.descent = num(c, "descent");
            f.faceVariant = cssVariant(getAttr(c, "font-variant"));
            f.alphabetic = num(c, "alphabetic");
            f.weight = cssWeight(getAttr(c, "font-weight"));
            f.faceStyle = cssStyle(getAttr(c, "font-style"));
            // The fourth CSS2 registration descriptor, font-stretch,
            // stays unread: every spelling in the suite reads
            // font-stretch="normal", so a matching axis over faces
            // that all say the same thing selects nothing - recorded
            // as the ceiling, and the property side is parsed and
            // carried (Style.stretch).
            f.hasIdeographic = optNum(c, "ideographic", f.ideographic);
            f.hasHanging = optNum(c, "hanging", f.hanging);
            f.hasMathematical = optNum(c, "mathematical", f.mathematical);
            f.hasXHeight = optNum(c, "x-height", f.xHeight);
            // §20.8.3: the band pairs and the v-* quartet. Numbers are
            // taken verbatim into the store; the consumption sites
            // (paintDecoLine, svgVerticalBaselineHeight) decide what an
            // absent or half-spelled row falls back to.
            f.hasUnderPos = optNum(c, "underline-position", f.underPos);
            f.hasUnderThk = optNum(c, "underline-thickness", f.underThk);
            f.hasOverPos = optNum(c, "overline-position", f.overPos);
            f.hasOverThk = optNum(c, "overline-thickness", f.overThk);
            f.hasStrikePos = optNum(c, "strikethrough-position",
                                    f.strikePos);
            f.hasStrikeThk = optNum(c, "strikethrough-thickness",
                                    f.strikeThk);
            f.hasVAlphabetic = optNum(c, "v-alphabetic", f.vAlphabetic);
            f.hasVHanging = optNum(c, "v-hanging", f.vHanging);
            f.hasVIdeographic = optNum(c, "v-ideographic",
                                       f.vIdeographic);
            f.hasVMathematical = optNum(c, "v-mathematical",
                                        f.vMathematical);
            break;

        case "glyph", "missing-glyph":
            SvgGlyph g;
            if (auto p = "id" in c.attrs) g.id = *p;
            if (auto p = "glyph-name" in c.attrs) g.name = *p;
            if (auto p = "unicode" in c.attrs) g.uni = decodeUni(*p);
            if (auto p = "d" in c.attrs)
            {
                try
                {
                    addSVGPath(g.d, *p);
                    g.hasD = true;
                }
                catch (Exception) {} // a bad outline draws nothing
            }
            // §20.4: a glyph's default advance is the font's.
            g.advX = num(c, "horiz-adv-x", f.defaultAdv);
            // §20.4 vertical: absent means the font's own value, which
            // by now (font-face parsed first, font attrs before the loop)
            // is itself either declared or still NaN for the end-of-parse
            // settle to fill.
            g.vertAdvY = num(c, "vert-adv-y", f.vertAdvY);
            g.vertOriginX = num(c, "vert-origin-x", f.vertOriginX);
            g.vertOriginY = num(c, "vert-origin-y", f.vertOriginY);
            if (c.name == "missing-glyph")
            {
                f.missing = g;
                f.hasMissing = true;
            }
            else
                f.glyphs ~= g;
            break;

        case "hkern":
            SvgKern kc;
            kc.first = parseSet(getAttr(c, "u1"), getAttr(c, "g1"));
            kc.second = parseSet(getAttr(c, "u2"), getAttr(c, "g2"));
            kc.k = num(c, "k");
            f.kerns ~= kc;
            break;

        case "vkern":
            // §20.7: same pair spelling as hkern, read only by the
            // vertical writing modes.
            SvgKern kv;
            kv.first = parseSet(getAttr(c, "u1"), getAttr(c, "g1"));
            kv.second = parseSet(getAttr(c, "u2"), getAttr(c, "g2"));
            kv.k = num(c, "k");
            f.vkerns ~= kv;
            break;

        default:
            break;
        }
    }

    // §20.3/§20.4: settle the absent chain. The font's own defaults
    // are one em for vert-adv-y, half the declared horiz-adv-x for
    // vert-origin-x and the face's ascent for vert-origin-y - font
    // units like everything else in the store; a glyph (or the
    // missing-glyph) that took the NaN forward falls to these.
    if (isNaN(f.vertAdvY))
        f.vertAdvY = f.upem;
    if (isNaN(f.vertOriginX))
        f.vertOriginX = 0.5f * f.defaultAdv;
    if (isNaN(f.vertOriginY))
        f.vertOriginY = f.ascent;
    void settle(ref SvgGlyph g)
    {
        if (isNaN(g.vertAdvY))
            g.vertAdvY = f.vertAdvY;
        if (isNaN(g.vertOriginX))
            g.vertOriginX = f.vertOriginX;
        if (isNaN(g.vertOriginY))
            g.vertOriginY = f.vertOriginY;
    }
    foreach (ref g; f.glyphs)
        settle(g);
    if (f.hasMissing)
        settle(f.missing);
    return f;
}

/// One kern side: u-list (code points, CSS2 `U+hex-hex` ranges and the
/// `U+hex?` wildcard spelling) UNION the g-list of glyph-names.
private KernSet parseSet(string u, string g)
{
    KernSet set;
    if (u.length)
        set.chars = parseRanges(u);
    if (g.length)
        foreach (nm; splitter(g, ','))
        {
            immutable name = strip(nm);
            if (name.length)
                set.names ~= name;
        }
    return set;
}

/// The CSS2 §15.3.3 range list: "U+41", "U+41-5A", "U+003?" (wildcards
/// are for the kern attributes; unicode-range never uses them, but
/// parsing both spellings once is simpler than splitting hairs). Bare
/// atoms are literal characters (they carry a sequence, usually one).
private CharRange[] parseRanges(string v)
{
    CharRange[] list;
    foreach (atom; splitter(v, ','))
    {
        immutable a = strip(atom);
        if (a.empty)
            continue;
        if (a.length > 2 && (a[0] == 'U' || a[0] == 'u') && a[1] == '+')
        {
            string rest = a[2 .. $];
            immutable dash = indexOf(rest, '-');
            if (dash > 0)
                pushRange(list, rest[0 .. dash], rest[dash + 1 .. $]);
            else if (canFind(rest, '?'))
            {
                string lo, hi;
                foreach (h; rest)
                {
                    lo ~= h == '?' ? '0' : h;
                    hi ~= h == '?' ? 'f' : h;
                }
                pushRange(list, lo, hi);
            }
            else
                pushRange(list, rest, rest);
        }
        else
        {
            try
                foreach (dchar ch; a)
                    list ~= CharRange(ch, ch);
            catch (UTFException) {}
        }
    }
    return list;
}

private void pushRange(ref CharRange[] list, string loS, string hiS)
{
    if (!loS.length || loS.length > 6 || hiS.length > 6)
        return;
    try
    {
        immutable lo = parseHex!long(loS), hi = parseHex!long(hiS);
        if (lo >= 0 && lo <= hi && hi <= 0x10FFFF)
            list ~= CharRange(cast(dchar) lo, cast(dchar) hi);
    }
    catch (ConvException) {} // stray '?', junk digits: skip the atom
}

private T parseHex(T)(string s)
{
    return parse!T(s, 16);
}

/// The characters a glyph answers to. The `unicode` attribute is an attribute
/// value, so its XML references (XML §4.1) were resolved when the node was
/// built - §20.4 says outright that a glyph's characters are often written as
/// character references, and the suite's font fixtures name `"` with `&#x22;`
/// and `&` with `&amp;`. What is left here is to read the value as code
/// points; a value that is not valid UTF-8 names nothing.
private dchar[] decodeUni(string raw)
{
    dchar[] uni;
    try
        foreach (dchar ch; raw)
            uni ~= ch;
    catch (UTFException) {}
    return uni;
}

private string getAttr(ref immutable(Element) e, string name)
{
    auto p = name in e.attrs;
    return p ? *p : null;
}

private float num(ref immutable(Element) e, string name, float def = 0)
{
    auto p = name in e.attrs;
    if (p is null)
        return def;
    try
        return to!float(*p);
    catch (ConvException)
        return def;
}

private bool optNum(ref immutable(Element) e, string name, out float v)
{
    auto p = name in e.attrs;
    if (p is null)
        return false;
    try
    {
        v = to!float(*p);
        return true;
    }
    catch (ConvException)
        return false;
}

////////////////////////////////////////////////////////////////////////////////

unittest
{
    // Two faces of one family plus a same-slot redeclaration: the bold
    // slot answers bold/italic requests, a roman request stays roman,
    // and the last normal-roman font wins its slot.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs>
          <font id="R"><font-face font-family="Pair" font-weight="normal"/>
            <glyph glyph-name="rm" unicode="A" d="M0 0L10 0Z"/></font>
          <font id="B"><font-face font-family="Pair" font-weight="bold"
                                  font-style="italic"/>
            <glyph glyph-name="bd" unicode="A" d="M0 0L20 0Z"/></font>
          <font id="R2"><font-face font-family="Pair"/>
            <glyph glyph-name="late" unicode="A" d="M0 0L30 0Z"/></font>
        </defs></svg>`);
    auto fonts = collectFonts(doc, "");
    assert(fonts["pair"].length == 2, "the third font replaces, not joins");

    auto f = matchFace(fonts["pair"], 400, 0);
    assert(f.glyphs[0].name == "late" && f.weight == 400,
        "last declaration owns the normal-roman slot");
    f = matchFace(fonts["pair"], 700, 1);
    assert(f.weight == 700 && f.faceStyle == 1, "exact slot match");
    f = matchFace(fonts["pair"], 600, 1);
    assert(f.weight == 700, "600 italic borrows the nearest heavier slant");
    f = matchFace(fonts["pair"], 700, 0);
    assert(f.weight == 400 && f.faceStyle == 0,
        "roman never borrows the slanted face even wanting bold");
}

unittest
{
    // §16.2's variant axis: normal and small-caps faces of one family
    // hold separate slots, a request takes only a face whose list
    // names that variant, and a comma-list face answers either way.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs>
          <font id="N"><font-face font-family="Var"/>
            <glyph glyph-name="lo" unicode="A" d="M0 0L10 0Z"/></font>
          <font id="S"><font-face font-family="Var"
                                  font-variant="small-caps"/>
            <glyph glyph-name="hi" unicode="A" d="M0 0L20 0Z"/></font>
          <font id="B"><font-face font-family="Both"
                                  font-variant="normal, small-caps"/>
            <glyph glyph-name="bi" unicode="A" d="M0 0L30 0Z"/></font>
        </defs></svg>`);
    auto fonts = collectFonts(doc, "");
    assert(fonts["var"].length == 2, "the variant axis splits the slot");

    assert(matchFace(fonts["var"], 400, 0).glyphs[0].name == "lo",
        "a plain request takes the normal face");
    assert(matchFace(fonts["var"], 400, 0, 2).glyphs[0].name == "hi",
        "a small-caps request takes the small-caps face");
    assert(matchFace(fonts["both"], 400, 0).glyphs[0].name == "bi"
        && matchFace(fonts["both"], 400, 0, 2).glyphs[0].name == "bi",
        "a comma-list face answers either request");
    assert(matchFace(fonts["var"], 400, 0, 4) is null,
        "a variant the axis cannot name takes nothing");
}

unittest
{
    // A minimal inline font: the family registers, covers everything,
    // and selects the single glyph with its advance.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs><font id="F" horiz-adv-x="500" horiz-origin-y="200">
          <font-face font-family="Testy" units-per-em="1000"
                     ascent="800" descent="-200" unicode-range="U+41-42"/>
          <glyph unicode="A" glyph-name="a1" horiz-adv-x="600"
                 d="M0 0L600 0L600 700L0 700Z"/>
          <glyph unicode="&amp;" glyph-name="amp"/>
          <hkern u1="A" g2="a1" k="-100"/>
        </font></defs></svg>`);
    auto fonts = collectFonts(doc, "");
    assert("testy" in fonts, "family registers (entity-free name)");
    auto f = fonts["testy"][0];
    assert(f.upem == 1000 && f.defaultAdv == 500 && f.originY == 200);
    assert(f.glyphs.length == 2 && f.missing.hasD == false);
    assert(f.covers('A') && f.covers('B') && !f.covers('C'));
    assert(!f.covers('&'), "registration range, not the glyph list, is what"
        ~ " covers() answers - out-of-range chars fall back to the host face");

    size_t used;
    auto g = f.select("AB", 0, used);
    assert(used == 1 && g.name == "a1" && g.advX == 600);
    g = f.select("AB", 1, used);
    assert(used == 1 && g is null, "'B' is in range but undefined and the"
        ~ " font has no missing-glyph: nothing to draw, still one char consumed");
    g = f.select("&", 0, used);
    assert(g.name == "amp", "entity-named glyph selects by its decoded char");
    assert(f.kernK(f.select("AA", 0, used), f.select("AA", 1, used), false) == -100,
        "u1 char x g2 glyph-name pair");
}

unittest
{
    // §20.3/§20.4's vertical defaults and §20.7's vkern table. The
    // first font spells nothing vertical: vert-adv-y settles to one
    // em, vert-origin-x to half the font's own horiz-adv-x (not the
    // glyph's), vert-origin-y to the face's ascent, and a glyph - or
    // the missing-glyph - with no vertical attributes inherits
    // exactly those numbers. The second font declares the trio at
    // the font level and two of the three at the glyph level: the
    // glyph keeps the font's vert-origin-x and replaces the rest.
    // Its vkern answers only the vertical read of the pair table.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs><font id="A" horiz-adv-x="500">
          <font-face font-family="Vda" units-per-em="1000"
                     ascent="800" descent="-200"/>
          <glyph unicode="a" glyph-name="a1" horiz-adv-x="600"
                 d="M0 0L100 0L100 100L0 100Z"/>
          <missing-glyph d="M0 0Z"/>
        </font>
        <font id="B" horiz-adv-x="500" vert-adv-y="1200"
              vert-origin-x="100" vert-origin-y="900">
          <font-face font-family="Vdb" units-per-em="1000"
                     ascent="800" descent="-200"/>
          <glyph unicode="b" glyph-name="b1" vert-adv-y="300"
                 vert-origin-y="100" d="M0 0L100 0Z"/>
          <vkern u1="b" u2="b" k="7"/>
        </font></defs></svg>`);
    auto fonts = collectFonts(doc, "");
    size_t used;

    auto a = fonts["vda"][0];
    assert(a.vertAdvY == 1000 && a.vertOriginX == 250 && a.vertOriginY == 800,
        "one em, half the font's horiz-adv-x and the ascent stand in");
    auto ga = a.select("a", 0, used);
    assert(ga.vertAdvY == 1000 && ga.vertOriginX == 250 && ga.vertOriginY == 800,
        "the glyph inherits the settled chain, its own horiz-adv-x"
        ~ " notwithstanding");
    assert(a.missing.vertAdvY == 1000 && a.missing.vertOriginX == 250
        && a.missing.vertOriginY == 800, "missing-glyph rides the same chain");

    auto b = fonts["vdb"][0];
    assert(b.vertAdvY == 1200 && b.vertOriginX == 100 && b.vertOriginY == 900,
        "the font's declared trio stands as spelled");
    auto gb = b.select("b", 0, used);
    assert(gb.vertAdvY == 300 && gb.vertOriginY == 100 && gb.vertOriginX == 100,
        "the glyph's own pair wins, vert-origin-x falls to the font's");
    assert(b.kernK(gb, gb, true) == 7, "vkern answers the vertical read");
    assert(b.kernK(gb, gb, false) == 0, "hkern holds nothing for this pair");
}

unittest
{
    // Kern set spellings from fonts-kern-01-t: chars, names, ranges,
    // and a pair that matches through EITHER side set.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs><font horiz-adv-x="224">
          <font-face font-family="kerny" units-per-em="1000"
                     ascent="917" descent="-250"/>
          <glyph unicode="1" glyph-name="gl_1" horiz-adv-x="250"/>
          <glyph unicode="2" glyph-name="gl_2" horiz-adv-x="1500"/>
          <glyph unicode="3" glyph-name="gl_3" horiz-adv-x="250"/>
          <glyph unicode="4" glyph-name="gl_4" horiz-adv-x="1500"/>
          <hkern u1="U+003?" u2="U+0031-0034" g1="gl_3" g2="gl_4" k="123"/>
        </font></defs></svg>`);
    auto fonts = collectFonts(doc, "");
    auto f = fonts["kerny"][0];
    size_t used;
    auto g1 = f.select("12", 0, used), g2 = f.select("12", 1, used);
    assert(f.kernK(g1, g2, false) == 123, "char range + char range pair");
    g1 = f.select("34", 0, used); g2 = f.select("34", 1, used);
    assert(f.kernK(g1, g2, false) == 123, "same entry matches the glyph-name pair");
    g1 = f.select("13", 0, used); g2 = f.select("13", 1, used);
    assert(f.kernK(g1, g2, false) == 123, "'13' also matches both side sets");
    g1 = f.select("14", 0, used); g2 = f.select("14", 1, used);
    assert(f.kernK(g1, g2, false) == 123);
    g1 = f.select("41", 0, used); g2 = f.select("41", 1, used);
    assert(f.kernK(g1, g2, false) == 123, "u1 is the digit wildcard: '4' fits it too");
    g1 = f.select("45", 0, used); g2 = f.select("45", 1, used);
    assert(f.kernK(g1, g2, false) == 0, "'5' misses u2's 31-34 range: the pair is"
        ~ " asymmetric, and first/second never swap");
}

unittest
{
    // CSS @font-face into the store, in the shape fonts-elem-07-b
    // writes: the font element is anonymous - its font-face names no
    // family - and only the rule names it, points at it by id, and
    // picks the slot its weight descriptor names. A local()-only
    // source names a system face, which the host matcher already
    // answers to by name, and registers nothing here.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <defs>
          <style><![CDATA[
            @font-face { font-family: 'Test Comic'; src: local("Serif"),
                         url("#IF") format("svg"); font-weight: bold }
            @font-face { font-family: NopeFace; src: local("Serif") }
          ]]></style>
          <font id="IF" horiz-adv-x="959"><font-face units-per-em="2048"
               ascent="1800" descent="-266"/>
            <glyph unicode="A" glyph-name="A" horiz-adv-x="1200"
                   d="M0 0L1200 0L1200 1400L0 1400Z"/>
          </font>
        </defs></svg>`);
    auto fonts = collectFonts(doc, "");
    assert("if" !in fonts && "nopeface" !in fonts,
        "the anonymous element names nothing, local() fetches nothing");
    assert("test comic" in fonts);
    auto f = matchFace(fonts["test comic"], 700, 0);
    assert(f.defaultAdv == 959 && f.upem == 2048);
    size_t used;
    auto g = f.select("A", 0, used);
    assert(g !is null && g.name == "A",
        "the descriptor's family is the road to the glyphs");
}
