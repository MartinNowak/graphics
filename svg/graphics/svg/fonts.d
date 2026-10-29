module graphics.svg.fonts;

import std.algorithm, std.ascii, std.conv, std.file, std.range, std.string, std.utf;
import graphics.core.path;
import graphics.svg.core : addSVGPath;
import graphics.svg.css : resolveHref;
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
    string name;  // glyph-name
    dchar[] uni;  // decoded `unicode` sequence; empty -> name-only glyph
}

struct SvgFont
{
    // font element (§20.3).
    float defaultAdv;      // horiz-adv-x: the glyph advance default
    float originX, originY; // horiz-origin-x/y: the glyph origin

    // the face slot this font registers into (CSS font matching):
    // numeric CSS weight (400 normal, 700 bold) and 0 roman, 1 italic,
    // 2 oblique.
    int weight = 400;
    int faceStyle;
    // font-face metrics (§20.4), font units. ascent/descent anchor the
    // derived baseline rows; the four alignment attributes override them.
    float upem = 1000;
    float ascent, descent;
    float alphabetic;
    float ideographic, hanging, mathematical, xHeight;
    bool hasIdeographic, hasHanging, hasMathematical, hasXHeight;

    CharRange[] ranges; // registration range; empty = everything

    SvgGlyph[] glyphs;  // document order (§20.6: first match wins)
    SvgGlyph missing;   // missing-glyph (§20.5)
    bool hasMissing;
    SvgKern[] kerns;

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

    /// §20.7: the k value of the first pair entry whose (first, second)
    /// sets contain the two glyphs, or 0.
    float kernK(const(SvgGlyph)* a, const(SvgGlyph)* b) const
    {
        if (a is null || b is null)
            return 0;
        foreach (ref kc; kerns)
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
/// and a later declaration of the same (weight, style) slot replaces the
/// earlier one. External font files follow the <image>/@import rules:
/// plain paths resolved against `baseDir` (css.resolveHref), each file
/// parsed at most once.
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
                if (o.weight == f.weight && o.faceStyle == f.faceStyle)
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
                if (auto h = find(href, '#'))
                {
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
                // the referencing face's own weight/style name the slot
                // the referenced font registers into.
                found.weight = cssWeight(getAttr(e, "font-weight"));
                found.faceStyle = cssStyle(getAttr(e, "font-style"));
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
    return reg;
}

/// CSS font matching, CSS2.1 §15.5 + CSS3 Fonts §5.2 reduced to the
/// slots SVG 1.1 faces can occupy: exact (weight, style) wins; weights
/// then search downward (<400 wants lighter first), upward (>500 wants
/// heavier first) or 400-first (middle); a roman request never borrows
/// a slanted face, and italic/oblique satisfy each other.
SvgFont* matchFace(SvgFont*[] faces, int weight, int style)
{
    SvgFont* best;
    int bestScore = int.max;
    foreach (f; faces)
    {
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

////////////////////////////////////////////////////////////////////////////////

/// Read one <font> subtree: face metrics, pre-parsed glyph outlines and
/// kern pairs. Outlines stay in font units (y up); §20.5 gives
/// missing-glyph the same attribute meanings as a glyph.
private SvgFont* parseFont(ref immutable(Element)[] nodes, size_t idx)
{
    auto f = new SvgFont;
    ref immutable(Element) fe = nodes[idx];
    f.defaultAdv = num(fe, "horiz-adv-x");
    f.originX = num(fe, "horiz-origin-x");
    f.originY = num(fe, "horiz-origin-y");

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
            f.alphabetic = num(c, "alphabetic");
            f.weight = cssWeight(getAttr(c, "font-weight"));
            f.faceStyle = cssStyle(getAttr(c, "font-style"));
            f.hasIdeographic = optNum(c, "ideographic", f.ideographic);
            f.hasHanging = optNum(c, "hanging", f.hanging);
            f.hasMathematical = optNum(c, "mathematical", f.mathematical);
            f.hasXHeight = optNum(c, "x-height", f.xHeight);
            break;

        case "glyph", "missing-glyph":
            SvgGlyph g;
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
            break; // vertical pairs are moot without vertical text

        default:
            break;
        }
    }
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

/// The parser stores attribute values verbatim, but the suite's font
/// fixtures name characters with XML entities (&quot; &amp; &#160;), so
/// the `unicode` attribute gets the entity treatment here.
private dchar[] decodeUni(string raw)
{
    dchar[] uni;
    try
        foreach (dchar ch; entityDecode(raw))
            uni ~= ch;
    catch (UTFException) {}
    return uni;
}

private string entityDecode(string s)
{
    string res;
    size_t i;
    while (i < s.length)
    {
        if (s[i] != '&')
        {
            res ~= s[i++];
            continue;
        }
        size_t j = i + 1;
        while (j < s.length && s[j] != ';' && j - i < 12)
            ++j;
        if (j >= s.length || s[j] != ';')
        {
            res ~= s[i++];
            continue;
        }
        immutable name = s[i + 1 .. j];
        switch (name)
        {
        case "amp":  res ~= '&';  break;
        case "lt":   res ~= '<';  break;
        case "gt":   res ~= '>';  break;
        case "quot": res ~= '"';  break;
        case "apos": res ~= '\''; break;
        default:
            if (name.length > 1 && name[0] == '#')
            {
                try
                {
                    immutable long cp = name.length > 2
                        && (name[1] == 'x' || name[1] == 'X')
                        ? parseHex!long(name[2 .. $]) : to!long(name[1 .. $]);
                    if (cp >= 0 && cp <= 0x10FFFF)
                        res ~= cast(dchar) cp;
                    else
                        res ~= s[i .. j + 1];
                }
                catch (ConvException) { res ~= s[i .. j + 1]; }
            }
            else
                res ~= s[i .. j + 1]; // unknown: keep it verbatim
            break;
        }
        i = j + 1;
    }
    return res;
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
    assert(f.kernK(f.select("AA", 0, used), f.select("AA", 1, used)) == -100,
        "u1 char x g2 glyph-name pair");
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
    assert(f.kernK(g1, g2) == 123, "char range + char range pair");
    g1 = f.select("34", 0, used); g2 = f.select("34", 1, used);
    assert(f.kernK(g1, g2) == 123, "same entry matches the glyph-name pair");
    g1 = f.select("13", 0, used); g2 = f.select("13", 1, used);
    assert(f.kernK(g1, g2) == 123, "'13' also matches both side sets");
    g1 = f.select("14", 0, used); g2 = f.select("14", 1, used);
    assert(f.kernK(g1, g2) == 123);
    g1 = f.select("41", 0, used); g2 = f.select("41", 1, used);
    assert(f.kernK(g1, g2) == 123, "u1 is the digit wildcard: '4' fits it too");
    g1 = f.select("45", 0, used); g2 = f.select("45", 1, used);
    assert(f.kernK(g1, g2) == 0, "'5' misses u2's 31-34 range: the pair is"
        ~ " asymmetric, and first/second never swap");
}
