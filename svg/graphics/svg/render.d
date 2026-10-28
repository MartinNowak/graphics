module graphics.svg.render;

import std.algorithm, std.ascii, std.base64, std.conv, std.exception, std.math, std.range, std.string;
import core.bitop : bswap;
import gamut;
import graphics;
import graphics.core.fonthost;
import graphics.core.glyph;
import graphics.core.matrix;
import graphics.core.patheffect;
import graphics.core.path_detail.path_measure;
import graphics.core.pmcolor : PMColor, alphaMul, alphaScale, invAlphaScale;
import graphics.core.shader : Shader, ColorShader, MappingShader;
import graphics.svg.color;
import graphics.svg.core;
import graphics.svg.filter;
import graphics.svg.gradient;
import graphics.svg.parser;
import graphics.svg.pattern;
import graphics.svg.pserver;

// ASCII case-insensitive comparison for SVG keywords (exact length).
private bool equalCase(string a, string b)
{
    if (a.length != b.length)
        return false;
    foreach (i, ch; a)
        if (std.ascii.toLower(ch) != std.ascii.toLower(b[i]))
            return false;
    return true;
}

// The `url(#frag) [fallback]` paint value (SVG 1.1 §13.2). Only local
// #frag references are supported. Returns false for anything that is not
// a url reference at all - the caller then parses an ordinary paint.
private bool urlPaint(string v, out string id, out Color fallback, out bool hasFallback)
{
    v = strip(v);
    if (v.length < 7 || !equalCase(v[0 .. 4], "url("))
        return false;
    auto close = indexOf(v, ')');
    if (close < 0)
        return false;
    auto frag = strip(v[4 .. close]);
    if (frag.length < 2 || frag[0] != '#')
        return false; // external documents / empty fragments: unsupported
    id = frag[1 .. $];
    fallback = Color(0);
    hasFallback = false;
    auto rest = strip(v[close + 1 .. $]);
    if (!rest.empty)
    {
        Color c;
        if (!parsePaint(rest, c))
            return false; // malformed fallback: the attribute is ignored
        fallback = c;
        hasFallback = true;
    }
    return true;
}

// Context for resolving `<length>` values: percentages are relative to the
// current viewport (which axis depends on the property), em/ex to the
// current font-size.
struct LengthCtx
{
    float vpW = 100.0f, vpH = 100.0f;
    float fontSize = 16.0f;
    float pctRef = 100.0f; // set by the caller per property axis
}

// Which viewport dimension a percentage resolves against (SVG 1.1,
// "Units"): x-ish lengths the width, y-ish the height, r/stroke-width the
// normalized diagonal.
enum RefAxis
{
    width,
    height,
    diagonal,
}

float arcDiagonal(in LengthCtx lc)
{
    return sqrt((lc.vpW ^^ 2 + lc.vpH ^^ 2) / 2.0f);
}

// Strict SVG <number> scan (optionally scientific). Deliberately does not
// consume a bare trailing 'e' so unit suffixes like "2em"/"1ex" survive.
private float parseNum(ref string s)
{
    import std.exception : enforce;
    size_t i;
    if (i < s.length && (s[i] == '+' || s[i] == '-'))
        ++i;
    bool seen;
    while (i < s.length && s[i] >= '0' && s[i] <= '9')
        ++i, seen = true;
    if (i < s.length && s[i] == '.')
    {
        ++i;
        while (i < s.length && s[i] >= '0' && s[i] <= '9')
            ++i, seen = true;
    }
    enforce(seen, "expected an SVG <number>");
    if (i < s.length && (s[i] | 0x20) == 'e')
    {
        size_t j = i + 1;
        if (j < s.length && (s[j] == '+' || s[j] == '-'))
            ++j;
        immutable digits = j;
        while (j < s.length && s[j] >= '0' && s[j] <= '9')
            ++j;
        if (j > digits)
            i = j; // a real exponent, not an "em"/"ex" unit
    }
    immutable res = to!float(s[0 .. i]);
    s = s[i .. $];
    return res;
}

unittest
{
    import std.exception : assertThrown;
    string s = "2.5e2px";
    assert(parseNum(s) == 250 && s == "px");
    s = "2em";
    assert(parseNum(s) == 2 && s == "em");
    s = "-1.5e-3";
    assert(isClose(parseNum(s), -1.5e-3f, 1e-9f) && s.empty);
    assertThrown(parseNum(s = "em"));
}

float parseLength(string s, const(LengthCtx) lc = LengthCtx.init)
{
    auto res = parseNum(s);
    s = strip(s);
    enum dpi = 72;
    switch (toLower(s))
    {
    case "", "px": break;
    case "cm": res *= dpi * (1.0 / 2.54); break;
    case "in": res *= dpi; break;
    case "mm": res *= dpi * (1.0 / 25.4); break;
    case "pt": res *= dpi * (1.0 / 72.0); break;
    case "pc": res *= dpi * (12.0 / 72.0); break;
    case "em": res *= lc.fontSize; break;
    case "ex": res *= 0.5f * lc.fontSize; break; // x-height is roughly half an em
    case "%": res = res * lc.pctRef / 100; break;
    // unitless value: user space, i.e. px
    default: break;
    }
    return res;
}

// `<length>` lookup from an attribute map: absent -> def.
float convLen(in string[string] a, string key, float def, LengthCtx lc, RefAxis axis)
{
    if (auto p = key in a)
    {
        auto c = lc;
        c.pctRef = axis == RefAxis.width ? c.vpW
                 : axis == RefAxis.height ? c.vpH
                 : arcDiagonal(c);
        try
            return parseLength(*p, c);
        catch (Exception)
            return def; // invalid <length>: ignore the attribute
    }
    return def;
}

// Collapse whitespace runs to a single space and trim both ends
// (SVG xml:space="default").
string normalizeText(string s)
{
    string res;
    bool space = false;
    foreach (c; s)
    {
        if (isWhite(c))
            space = true;
        else
        {
            if (space)
                res ~= ' ';
            space = false;
            res ~= c;
        }
    }
    return res;
}

// Parse a viewBox value: "min-x min-y width height", whitespace/comma separated.
void parseViewBox(ref float[4] vb, string s)
{
    foreach (ref v; vb)
    {
        while (!s.empty && (s[0] == ',' || isWhite(s[0])))
            s = s[1 .. $];
        v = std.conv.parse!float(s);
    }
    while (!s.empty && (s[0] == ',' || isWhite(s[0])))
        s = s[1 .. $];
    enforce(s.empty, "invalid viewBox: "~s);
}

// preserveAspectRatio: alignment + meet/slice/none.
struct PAR
{
    int alignX = 1, alignY = 1; // 0 = Min, 1 = Mid, 2 = Max
    bool stretch;               // "none": fill the viewport, aspect be damned
    bool meet = true;           // meet (smallest covers) vs slice (largest does)
}

PAR parsePAR(string s)
{
    PAR p;
    foreach (tok; splitter(replace(strip(s), ',', ' ')))
    {
        if (tok == "none")
            p.stretch = true;
        else if (tok == "meet")
            p.meet = true;
        else if (tok == "slice")
            p.meet = false;
        else if (tok.length == 8 && tok[0] == 'x' && tok[4] == 'Y') // xMinYMid...
        {
            switch (tok[1 .. 4])
            {
            case "Min": p.alignX = 0; break;
            case "Mid": p.alignX = 1; break;
            case "Max": p.alignX = 2; break;
            default: break;
            }
            switch (tok[5 .. 8])
            {
            case "Min": p.alignY = 0; break;
            case "Mid": p.alignY = 1; break;
            case "Max": p.alignY = 2; break;
            default: break;
            }
        }
        // "defer" (SVG2) and junk: keep the defaults
    }
    return p;
}

// Matrix mapping the viewBox rect into a viewport of size w x h at the origin.
Matrix viewFit(const(float)[4] vb, float w, float h, PAR par)
{
    Matrix m;
    if (par.stretch)
    {
        m[0][0] = w / vb[2];
        m[1][1] = h / vb[3];
        m[0][2] = -vb[0] * m[0][0];
        m[1][2] = -vb[1] * m[1][1];
        return m;
    }

    immutable s = par.meet ? min(w / vb[2], h / vb[3]) : max(w / vb[2], h / vb[3]);
    immutable ox = par.alignX == 0 ? 0.0f
                 : par.alignX == 2 ? w - vb[2] * s
                 : (w - vb[2] * s) * 0.5f;
    immutable oy = par.alignY == 0 ? 0.0f
                 : par.alignY == 2 ? h - vb[3] * s
                 : (h - vb[3] * s) * 0.5f;
    m[0][0] = s;
    m[1][1] = s;
    m[0][2] = ox - vb[0] * s;
    m[1][2] = oy - vb[1] * s;
    return m;
}

// Unit tangent vector; (0, 0) when the segment is degenerate - marker
// placement reads that as the zero-length case (§11.4.1).
private FPoint unit(FPoint v)
{
    immutable l = sqrt(v.x * v.x + v.y * v.y);
    return l > 0 ? FPoint(v.x / l, v.y / l) : FPoint(0, 0);
}

// §9.8 image sampler: browsers filter scaled images bilinearly, and
// nearest (plain BitmapShader) both stair-steps upscales and misses
// the browsers' half-pixel registration: the blitter asks for shader
// points at integer device indices (pixel centers), while the browser
// samples at natural coord (x+0.5-t)/s. u = pt + 0.5/s - 0.5 rebases
// one convention into the other (and is the identity at s=1, so 1:1
// placement stays pixel exact). Interpolation happens on premultiplied
// channels; the bitmap's own pixels are straight and premultiply once
// per neighbour read.
class ImageShader : MappingShader
{
    this(Bitmap src, float sx, float sy)
    {
        this.src = src;
        this.sx = sx;
        this.sy = sy;
    }

    override @property bool opaque() const
    {
        return src.opaque;
    }

    override void getRange(float x, float y, PMColor[] data)
    {
        mapLine!(colorAt)(this, x, y, data);
    }

    // Premultiplied pair lerp; weights {256-w, w} sum to 256 so the
    // shift is exact at both endpoints (the gradient lerp's {255-w,
    // w} pair would darken a full-strength blend by one), and the
    // result is assembled channel-wise so no implicit Color->PMColor
    // constructor can premultiply the linear combination a second time.
    static PMColor lerp(in PMColor a, in PMColor b, float u)
    {
        immutable w = cast(uint) clamp(round(u * 256), 0.0f, 256.0f);
        Color px;
        px.r = cast(ubyte) (((256 - w) * a.r + w * b.r) >> 8);
        px.g = cast(ubyte) (((256 - w) * a.g + w * b.g) >> 8);
        px.b = cast(ubyte) (((256 - w) * a.b + w * b.b) >> 8);
        px.a = cast(ubyte) (((256 - w) * a.a + w * b.a) >> 8);
        PMColor res;
        res._color = px;
        return res;
    }

    static PMColor colorAt(ImageShader sh, in FPoint pt)
    {
        immutable u = pt.x + 0.5f / sh.sx - 0.5f;
        immutable v = pt.y + 0.5f / sh.sy - 0.5f;
        if (u < -0.5f || v < -0.5f || u > sh.src.width - 0.5f
            || v > sh.src.height - 0.5f)
            return PMColor(Color(0));

        immutable i0 = to!int(floor(u)), j0 = to!int(floor(v));
        immutable fu = u - i0, fv = v - j0;
        // clamp (replicate) at the edges, as browsers do within the
        // half-texel border the weights reach
        immutable iw = to!int(sh.src.width) - 1, ih = to!int(sh.src.height) - 1;
        immutable ic = clamp(i0, 0, iw), jc = clamp(j0, 0, ih);
        immutable i1 = min(i0 + 1, iw), j1 = min(j0 + 1, ih);

        auto top = lerp(PMColor(sh.src.getLine!Color(jc)[ic]),
            PMColor(sh.src.getLine!Color(jc)[i1]), fu);
        auto bot = lerp(PMColor(sh.src.getLine!Color(j1)[ic]),
            PMColor(sh.src.getLine!Color(j1)[i1]), fu);
        return lerp(top, bot, fv);
    }

    Bitmap src;
    float sx, sy;
}

// §5.1.2 URL plumbing for <image>: only plain filesystem paths are in
// play. resolveHref returns null for an empty href, a same-document
// fragment (an <image> cannot paint an inline element) and any URL
// scheme (http:, data:, ... - no network, and no file: pretence);
// otherwise the path joined onto `base` with ./.. segments collapsed.
private string resolveHref(string base, string href)
{
    if (href.empty || href[0] == '#')
        return null;
    if (auto h = find(href, '#')) // drop the #fragment
        href = href[0 .. cast(ptrdiff_t)(h.ptr - href.ptr)];
    if (href.empty)
        return null;

    // letters [+alnum.-]* before a ':' = a URL scheme. Everything but
    // data: needs a network we don't have; data: (04-t embeds both a
    // JPEG and a PNG) is handled by loadSVGImage.
    immutable c = indexOf(href, ':');
    if (c > 0 && isAlpha(href[0]))
    {
        bool scheme = true;
        foreach (ch; href[1 .. c])
            if (!(isAlphaNum(ch) || ch == '+' || ch == '-' || ch == '.'))
                scheme = false;
        if (scheme)
            return href[0 .. c] == "data" ? href : null;
    }

    string path = href[0] == '/' ? href : (base.length ? base ~ href : href);
    string[] segs;
    foreach (seg; splitter(path, '/'))
    {
        if (seg.empty || seg == ".")
            continue;
        if (seg == "..")
        {
            if (segs.length && segs[$ - 1] != "..")
                segs.length = segs.length - 1;
            else if (path[0] != '/')
                segs ~= ".."; // escape of a relative base
            continue;
        }
        segs ~= seg;
    }
    string r = segs.join("/");
    if (path[0] == '/')
        r = "/" ~ r;
    return r.empty ? "." : r;
}

// xml:base resolution: the value becomes the subtree's base directory.
private string baseJoin(string base, string v)
{
    if (auto r = resolveHref(base, v))
        return r ~ (r[$ - 1] == '/' ? "" : "/");
    return base;
}

// Loaded images keyed by resolved path. Bitmaps keep their straight
// (non-premultiplied) ARGB, as loaded: the drawing path is an
// ImageShader, which premultiplies each sampled pixel once when it
// converts the slot to a PMColor. Premultiplying at load time would
// scale translucent pixels by (a+1) twice (the suite's tRNS and
// greyscale-alpha PNGs decode wrong then). Failed loads cache the
// empty Bitmap so broken references stay cheap, and suite tests
// reference the same image dozens of times, so the cache is
// process-lifetime.
// data: URLs (§7.4: href is a URI, and the suite embeds a JPEG and a
// PNG this way) are the only scheme we can honour without a network.
// Only base64 payloads are in play; the bytes go to gamut (the codec
// behind guip.Bitmap.load) and the decoded pixels are copied into a
// GC buffer the Bitmap owns, exactly as Bitmap.load now does.
private Bitmap loadDataURL(string url)
{
    auto semi = indexOf(url, ';');
    enforce(semi > 0 && url.length > semi + 8
        && url[semi + 1 .. semi + 8] == "base64,",
        "only base64 data: URLs load");

    Bitmap bmp;
    Image image;
    enforce(image.loadFromMemory(Base64.decode(url[semi + 8 .. $]),
        LOAD_RGB | LOAD_ALPHA | LOAD_8BIT | LOAD_NO_PREMUL
        | LAYOUT_GAPLESS | LAYOUT_VERT_STRAIGHT),
        "undecodable data: image");

    bmp.setConfig(Bitmap.Config.ARGB_8888, to!uint(image.width()),
        to!uint(image.height()));
    auto px = image.allPixelsAtOnce();
    enforce(px.length == bmp.buffer.length,
        "multi-layer image not supported");
    bmp.buffer[] = px;
    foreach (ref e; cast(uint[]) bmp.buffer)
    {
        version (LittleEndian)
            e = bswap(e);
        e = (e << 24) | (e >> 8); // 0xRRGGBBAA -> 0xAARRGGBB
    }
    return bmp;
}

private Bitmap loadSVGImage(string path)
{
    static Bitmap[string] cache;
    if (auto hit = path in cache)
        return *hit;
    Bitmap img;
    try
        img = path.length > 5 && path[0 .. 5] == "data:"
            ? loadDataURL(path)
            : Bitmap.load(path);
    catch (Exception)
        img = Bitmap(); // missing, undecodable, or SVG-as-image (later)
    return cache[path] = img;
}

// A decoded Bitmap into filter working space (feImage §15.18): the
// straight ARGB premultiplies into floats, colour through the sRGB
// decode curve when the chain works in linearRGB (alpha is linear
// either way, §15.2).
private Raster bitmapRaster(in Bitmap b, bool linearRGB)
{
    immutable clut = srgbDecodeLUT();
    Raster r = Raster(to!int(b.width), to!int(b.height));
    foreach (y; 0 .. b.height)
    {
        auto row = b.getLine!Color(y);
        foreach (x; 0 .. row.length)
        {
            immutable Color c = row[x];
            immutable float a = c.a / 255.0f;
            immutable p = (cast(size_t) y * r.w + x) * 4;
            r.px[p + 0] = (linearRGB ? clut[c.r] : c.r / 255.0f) * a;
            r.px[p + 1] = (linearRGB ? clut[c.g] : c.g / 255.0f) * a;
            r.px[p + 2] = (linearRGB ? clut[c.b] : c.b / 255.0f) * a;
            r.px[p + 3] = a;
        }
    }
    return r;
}

// Parse `stroke-dasharray`: null means "none" or invalid (the attribute is
// then ignored). SVG: an odd count of entries is repeated to an even one;
// a list that sums to zero renders like none; negative values are an error.
float[] parseDash(string v)
{
    v = strip(v);
    if (v.empty || equalCase(v, "none"))
        return null;

    float[] res;
    foreach (tok; splitter(replace(v, ',', ' ')))
    {
        float x;
        try
            x = to!float(tok);
        catch (ConvException)
            return null;
        if (x < 0)
            return null;
        res ~= x;
    }
    if (res.empty || res.reduce!((a, b) => a + b) <= 0)
        return null;
    if (res.length & 1)
        res ~= res.dup;
    return res;
}

// The path-measuring machinery only walks explicit segments; the implicit
// closing line of a closed subpath has no segment, so expand closes into
// explicit lines before dashing a path.
Path expandedCloses(in Path path)
{
    Path res;
    FPoint start=void, cur=void;
    foreach (verb, pts; path)
    {
        final switch (verb)
        {
        case Path.Verb.Move:
            start = cur = pts[0];
            res.moveTo(cur);
            break;
        case Path.Verb.Line:
            cur = pts[1];
            res.lineTo(cur);
            break;
        case Path.Verb.Quad:
            res.quadTo(pts[1], pts[2]);
            cur = pts[2];
            break;
        case Path.Verb.Cubic:
            res.cubicTo(pts[1], pts[2], pts[3]);
            cur = pts[3];
            break;
        case Path.Verb.Close:
            if (cur != start)
                res.lineTo(start);
            cur = start;
            break;
        }
    }
    return res;
}

// Exact-length stroke-dasharray/stroke-dashoffset along `path`: unlike the
// library's dashPath (which rescales the pattern to fit the path an exact
// number of times), the SVG pattern repeats at its given length and the
// offset picks up mid-pattern at the path start.
Path svgDash(in Path path, in float[] intervals, float offset)
{
    immutable L = reduce!"a+b"(0.0f, intervals);
    assert(L > 0 && intervals.length && !(intervals.length & 1));

    auto meas = PathMeasure(expandedCloses(path));
    immutable total = meas.length;
    if (total <= 0)
        return Path.init;

    immutable n = intervals.length;

    // Locate the pattern interval covering the pattern position of the path
    // start (stroke-dashoffset), skipping forward to the next dash interval.
    float p = offset % L;
    if (p < 0)
        p += L;
    size_t idx;
    float len = intervals[0];
    while (p >= len)
    {
        p -= len;
        idx = (idx + 1) % n;
        len = intervals[idx];
    }
    float pos = 0;
    if (idx & 1) // we start inside a gap
    {
        pos += len - p;
        idx = (idx + 1) % n;
    }

    Path res;
    bool first = true;
    while (pos < total)
    {
        immutable seg = first ? intervals[idx] - p : intervals[idx];
        first = false;
        if ((idx & 1) == 0 && seg > 0)
            meas.appendRangeToPath(pos, min(pos + seg, total), res);
        pos += seg;
        idx = (idx + 1) % n;
    }
    return res;
}

// Paints a parsed `Document` (see graphics.svg.parser).
//
// The walk visits the arena in document order — exactly what the old
// streaming SAX traversal did, node for node — but over arena indices, so
// the whole tree (including everything inside <defs>) is known before the
// first pixel lands and forward references can resolve through
// `Document.byId`.
private struct Renderer
{
    Document doc;
    Bitmap bmp;
    Canvas canvas;
    Appender!(Style[]) styles;
    Path path;
    float zoom;
    bool inRoot; // latches at the first <svg> element; nodes before it are inert

    // The text run being accumulated inside a <text>/<tspan>.
    bool inText;
    FPoint textPos;
    string textBuf;
    float lastAdvance;

    // Current viewport in user units (reference for percentages) and the
    // saved stack for nested <svg> viewports.
    float vpW=1000, vpH=1000;
    FSize[] savedViewports;
    uint viewportDepth;

    // The `use` targets currently being expanded - the recursion path.
    // A reference already on the path is a cycle (struct-use-12-f);
    // the instance renders nothing (an error in the spec).
    size_t[] useStack;

    // Nesting depth of pattern tile rasterisation (a pattern whose
    // content itself paint-fills a pattern). Deep chains - including
    // cycles - stop rendering the inner server.
    int patternDepth;

    // clip-path state: clipMode means this renderer is painting a clip
    // mask (clipPath children contribute opaque filled geometry only);
    // clipDepth caps clip-path references nested inside clipPath
    // content.
    bool clipMode;
    int clipDepth;

    // Painting <marker> content: §11.4 keeps markers out of marker
    // content (no recursion), so flushPath skips them while set.
    bool markerMode;

    // filterDepth caps filter-on-filter nesting: each level's offscreen
    // scratch is nested in its parent's, and reference cycles (a
    // filtered subtree that re-references its own filter via <use>)
    // stop at the cap and paint unfiltered.
    int filterDepth;

    // During a filtered subtree's paint this tracks the union of all
    // painted geometry bboxes (user space) - the objectBoundingBox
    // basis for filter regions and primitive subregions, which the
    // spec defines on *geometry*, not painted coverage (AA pixels
    // would inflate it).
    bool bboxTrack;
    FRect bboxAccum;

    // Directory of the source document (trailing '/'), the default base
    // for relative <image> hrefs; "" means the process cwd.
    string docBase;

    static struct Style
    {
        bool transform;
        Color cstroke, cfill=Color.Black;
        float strokeWidth=1, opacity=1, fillOpacity=1, strokeOpacity=1;

        // Paint model: `none` becomes a zero-alpha color (never painted);
        // currentColor is resolved at paint time from the `color` property.
        Color curColor=Color.Black;
        bool fillIsCurrent, strokeIsCurrent;
        bool visible=true; // visibility

        // Paint servers: fill/stroke="url(#id)" with the optional
        // `) fallback` paint (SVG 1.1 §13.2). A non-empty id replaces the
        // plain color; an unresolvable server paints the fallback or
        // nothing at all.
        string fillUrl, strokeUrl;
        Color fillFallback, strokeFallback;
        bool hasFillFallback, hasStrokeFallback;

        // Inherited fill rule (SVG 1.1 11.2.4) and, for clip paths, its
        // clip-path counterpart clip-rule (§14.4): the winding rule the
        // referenced <clipPath>'s children fill under.
        Path.FillRule fillRule = Path.FillRule.NonZero;
        Path.FillRule clipRule = Path.FillRule.NonZero;

        // clip-path="url(#id)" (§14.3). A broken reference - unknown id,
        // non-clipPath target, cycle - means the element is NOT rendered
        // (unlike paint servers, which fall back). The list accumulates
        // the chain of clip-paths declared on ancestors: the CSS
        // property *replaces* on each element, but rendering-wise every
        // ancestor group is clipped as a whole, and a paint buried in
        // those groups carries all of their masks - none of which a
        // deeper clip-path or even clip-path="none" can escape. Binary
        // masks commute, so accumulating and intersecting them is
        // exact.
        string[] clipUrls;

        // mask="url(#id)" (§14.1): same accumulation chain as clipUrls -
        // mask values are per-pixel scalars on premultiplied pixels, so
        // stacking them multiplies exactly and order never matters.
        string[] maskUrls;

        // marker-start/mid/end (§11.4). Unlike clip/mask these are
        // ordinary inherited properties: a value replaces (not chains)
        // the inherited one and "none" cancels it. Empty = no marker.
        string markerStart, markerMid, markerEnd;

        // xml:base (§5.1.2): inherited base for relative URLs. Only
        // <image> reaches outside the document, so only <image> hrefs
        // consume it. Empty = the document's own directory.
        string baseUrl;

        // Stroke geometry.
        CapStyle caps;
        JoinStyle joins;
        float miterLimit=4;
        float[] dash;      // null/empty: solid stroke
        float dashOffset;

        // Text attributes, inherited like the paint attributes.
        string family;
        float fontSize=16f;
        TypeFace.Weight weight=TypeFace.Weight.Normal;
        TypeFace.Slant slant=TypeFace.Slant.Roman;
        TextPaint.TextAlign anchor=TextPaint.TextAlign.Left;
    }

    LengthCtx lengthCtx()
    {
        LengthCtx lc;
        lc.vpW = vpW;
        lc.vpH = vpH;
        lc.fontSize = styles.length ? styles.data.back.fontSize : 16.0f;
        return lc;
    }

    // Set up the canvas and the viewport zoom (viewBox -> canvas).
    void setupRoot(in string[string] a)
    {
        // viewBox="min-x min-y width height"; when missing, user space
        // maps 1:1 to the canvas (user units are px), so the viewBox
        // defaults to the canvas dims.
        float[4] vb = [0.0f, 0.0f, 1000.0f, 1000.0f];
        const hasVB = "viewBox" in a;
        if (hasVB)
        {
            parseViewBox(vb, *("viewBox" in a));
            enforce(vb[2] > 0 && vb[3] > 0, "invalid viewBox");
        }

        // width/height are <length>s; at the root a percentage resolves
        // against the viewBox ("the user space") - "100%" is the whole
        // document, which is what every W3C test asks for.
        LengthCtx lc;
        lc.vpW = vb[2];
        lc.vpH = vb[3];
        immutable wpx = convLen(a, "width", vb[2], lc, RefAxis.width);
        immutable hpx = convLen(a, "height", vb[3], lc, RefAxis.height);
        enforce(wpx > 0 && hpx > 0, "root <svg> needs a positive width and height");
        if (!hasVB)
        {
            vb[2] = wpx;
            vb[3] = hpx;
        }

        immutable width = wpx * zoom;
        immutable height = hpx * zoom;

        bmp = Bitmap(Bitmap.Config.ARGB_8888, to!uint(round(width)), to!uint(round(height)));
        canvas = new Canvas(bmp);

        canvas.matrix = viewFit(vb, width, height,
            parsePAR(a.get("preserveAspectRatio", "xMidYMid meet")));

        vpW = vb[2];
        vpH = vb[3];
    }

    Style pushStyle(in string[string] attr)
    {
        // Default-construct the base style so every field gets its member
        // initializer (font defaults included).
        Style style = styles.length ? styles.data.back : Style();
        style.transform = false;

        auto lc = lengthCtx(); // percentages/em against the *parent* context

        void apply(string k, string v)
        {
            switch (k)
            {
            case "stroke-width":
                lc.pctRef = arcDiagonal(lc);
                try
                    style.strokeWidth = parseLength(v, lc);
                catch (Exception) {} // inherit/garbage: keep the inherited value
                break;

            case "fill":
            {
                string id;
                Color fb;
                bool hasFb;
                if (urlPaint(v, id, fb, hasFb))
                {
                    style.fillUrl = id;
                    style.fillFallback = fb;
                    style.hasFillFallback = hasFb;
                    break;
                }
                if (equalCase(v, "currentColor"))
                    style.fillIsCurrent = true;
                else
                {
                    Color c;
                    if (parsePaint(v, c))
                    {
                        style.cfill = c;
                        style.fillUrl = null; // a plain paint replaces the server
                    }
                }
                break;
            }

            case "stroke":
            {
                string id;
                Color fb;
                bool hasFb;
                if (urlPaint(v, id, fb, hasFb))
                {
                    style.strokeUrl = id;
                    style.strokeFallback = fb;
                    style.hasStrokeFallback = hasFb;
                    break;
                }
                if (equalCase(v, "currentColor"))
                    style.strokeIsCurrent = true;
                else
                {
                    Color c;
                    if (parsePaint(v, c))
                    {
                        style.cstroke = c;
                        style.strokeUrl = null;
                    }
                }
                break;
            }

            case "color":
            {
                // The currentColor base; `inherit` = do nothing (the
                // parent style is already inherited).
                Color c;
                if (parsePaint(v, c))
                    style.curColor = c;
                break;
            }

            case "fill-rule":
                switch (toLower(v))
                {
                case "evenodd":
                    style.fillRule = Path.FillRule.EvenOdd;
                    break;
                case "nonzero":
                    style.fillRule = Path.FillRule.NonZero;
                    break;
                default: // "inherit" and friends: keep the parent value
                    break;
                }
                break;

            case "clip-rule":
                switch (toLower(v))
                {
                case "evenodd":
                    style.clipRule = Path.FillRule.EvenOdd;
                    break;
                case "nonzero":
                    style.clipRule = Path.FillRule.NonZero;
                    break;
                default: // "inherit" and friends: keep the parent value
                    break;
                }
                break;

            case "clip-path":
                // url(#id) or none (§14.3): a url joins the inherited
                // ancestor masks (see Style.clipUrls); "none" merely
                // omits this element's own mask, and a malformed value
                // drops the declaration. No fallback paint is allowed
                // on this property, so urlPaint's trailing paint - if
                // any - is ignored.
                string id;
                Color fb;
                bool hfb;
                if (urlPaint(v, id, fb, hfb))
                    style.clipUrls = style.clipUrls ~ id;
                break;

            case "mask":
                // url(#id) or none (§14.1): the url joins the ancestor
                // mask chain (see Style.maskUrls); like clip-path there
                // is no fallback paint, so urlPaint's trailing paint -
                // if any - is ignored, and a malformed value drops the
                // declaration.
                {
                    string mid;
                    Color mfb;
                    bool mhfb;
                    if (urlPaint(v, mid, mfb, mhfb))
                        style.maskUrls = style.maskUrls ~ mid;
                }
                break;

            case "marker-start", "marker-mid", "marker-end":
                // §11.4: ordinary inherited properties, not a chain -
                // the value replaces whatever was inherited and "none"
                // cancels it; a malformed value drops the declaration.
                // The `marker` shorthand is deliberately absent: it is
                // CSS-only, not a presentation attribute (04-f's top
                // row must have no markers at all).
                {
                    string mid;
                    Color mfb;
                    bool mhfb;
                    if (equalCase(strip(v), "none"))
                    {
                        if (k == "marker-start")
                            style.markerStart = "";
                        if (k == "marker-mid")
                            style.markerMid = "";
                        if (k == "marker-end")
                            style.markerEnd = "";
                    }
                    else if (urlPaint(v, mid, mfb, mhfb))
                    {
                        if (k == "marker-start")
                            style.markerStart = mid;
                        if (k == "marker-mid")
                            style.markerMid = mid;
                        if (k == "marker-end")
                            style.markerEnd = mid;
                    }
                }
                break;

            case "xml:base":
                // §5.1.2: the subtree's base for relative URLs - kept
                // as a normalised prefix ending in '/'; a malformed
                // value keeps the inherited base.
                style.baseUrl = baseJoin(style.baseUrl.length
                    ? style.baseUrl : docBase, v);
                break;

            case "visibility":
                switch (toLower(v))
                {
                case "hidden", "collapse":
                    style.visible = false;
                    break;
                case "visible":
                    style.visible = true;
                    break;
                default: // "inherit" and friends: keep the parent value
                    break;
                }
                break;

            case "display":
                // Handled by the element walk as a whole-subtree skip;
                // here it only has to not poison the style.
                break;

            case "stroke-linecap":
                switch (toLower(v))
                {
                case "round": style.caps = CapStyle.Round; break;
                case "square": style.caps = CapStyle.Square; break;
                default: style.caps = CapStyle.Butt; break;
                }
                break;

            case "stroke-linejoin":
                switch (toLower(v))
                {
                case "round": style.joins = JoinStyle.Round; break;
                case "bevel": style.joins = JoinStyle.Bevel; break;
                default: style.joins = JoinStyle.Miter; break;
                }
                break;

            case "stroke-miterlimit":
                try
                    style.miterLimit = to!float(v);
                catch (ConvException) {}
                break;

            case "stroke-dasharray":
                style.dash = parseDash(v);
                break;

            case "stroke-dashoffset":
                lc.pctRef = arcDiagonal(lc);
                try
                    style.dashOffset = parseLength(v, lc);
                catch (Exception) {}
                break;

            case "opacity":
                style.opacity = to!float(v);
                break;

            case "fill-opacity":
                style.fillOpacity = to!float(v);
                break;

            case "stroke-opacity":
                style.strokeOpacity = to!float(v);
                break;

            case "font-family":
            {
                // First of the comma-separated list; surrounding
                // whitespace and quotes stripped.
                auto fam = strip(splitter(v, ',').front);
                fam = strip(fam, "\"'");
                if (fam.length)
                    style.family = fam;
                break;
            }

            case "font-size":
                // A percentage is relative to the parent font-size; em
                // likewise (lc.fontSize is still the parent's).
                lc.pctRef = style.fontSize;
                try
                    style.fontSize = parseLength(v, lc);
                catch (Exception) {} // inherit/garbage: keep the inherited size
                break;

            case "font-weight":
            {
                if (v == "bold")
                    style.weight = TypeFace.Weight.Bold;
                else if (v == "normal" || v == "regular")
                    style.weight = TypeFace.Weight.Normal;
                else
                {
                    // numeric 100..900
                    int w;
                    try
                        w = to!int(strip(v));
                    catch (Exception)
                        break; // inherit/garbage: keep the inherited weight
                    style.weight =
                        w <= 200 ? TypeFace.Weight.Thin :
                        w <= 300 ? TypeFace.Weight.Light :
                        w <= 500 ? TypeFace.Weight.Normal :
                        w <= 700 ? TypeFace.Weight.Bold :
                                   TypeFace.Weight.Heavy;
                }
                break;
            }

            case "font-style":
                switch (v)
                {
                case "italic":
                    style.slant = TypeFace.Slant.Italic;
                    break;
                case "oblique":
                    style.slant = TypeFace.Slant.Oblique;
                    break;
                default:
                    style.slant = TypeFace.Slant.Roman;
                    break;
                }
                break;

            case "text-anchor":
                switch (v)
                {
                case "middle":
                    style.anchor = TextPaint.TextAlign.Center;
                    break;
                case "end":
                    style.anchor = TextPaint.TextAlign.Right;
                    break;
                default:
                    style.anchor = TextPaint.TextAlign.Left;
                    break;
                }
                break;

            case "transform":
                style.transform = true;
                canvas.save();
                if (!transformSVG(canvas.matrix, v))
                    style.visible = false; // all-zero matrix: not rendered
                break;

            default:
                break;
            }
        }

        foreach(k, v; attr)
        {
            if (k != "style")
                apply(k, v);
            else
            {
                foreach(elem; splitter(v, ';'))
                {
                    auto p = findSplit(elem, ":");
                    apply(strip(p[0]), strip(p[2]));
                }
            }
        }

        styles ~= style;
        return style;
    }

    void popStyle()
    {
        if (styles.data.back.transform)
            canvas.restore();
        styles.shrinkTo(styles.length - 1);
    }

    // One side's Paint (fill or stroke) from the style. A paint server
    // (fill/stroke url) replaces the plain color; a server that cannot be
    // built - unknown id, gradient error - falls back to the documented
    // `url(...) paint` fallback or paints nothing. The effective alpha
    // (opacity x fill/stroke-opacity) folds into plain colors and into
    // the gradient stops at build time.
    Paint resolvePaint(bool isFill, in Style s, float alpha, in FRect bbox)
    {
        immutable url = isFill ? s.fillUrl : s.strokeUrl;
        if (url.length)
        {
            // Dispatch by the referenced element's kind: gradients and
            // patterns are separate servers (§13.2/§14.2); anything else
            // - or a broken reference - is a server error.
            Shader sh;
            immutable tgt = doc.byId(url);
            if (tgt != Document.unknown && doc.nodes[tgt].name == "pattern")
                sh = patternPaint(url, bbox, alpha);
            else
                sh = makeGradient(doc, url, bbox, vpW, vpH, s.curColor, alpha);
            if (sh !is null)
            {
                Paint p;
                p.shader = sh;
                return p;
            }
            Color fb = Color(0);
            if (isFill ? s.hasFillFallback : s.hasStrokeFallback)
                fb = isFill ? s.fillFallback : s.strokeFallback;
            fb.a = to!ubyte(round(fb.a * clamp(alpha, 0f, 1f)));
            return Paint(fb);
        }
        Color c = isFill ? (s.fillIsCurrent ? s.curColor : s.cfill)
            : (s.strokeIsCurrent ? s.curColor : s.cstroke);
        c.a = to!ubyte(round(c.a * clamp(alpha, 0f, 1f)));
        return Paint(c);
    }

    // §14.2: rasterise the pattern content once into a tile bitmap, then
    // tile it in the shader. Resolution follows the paint's device scale:
    // an unscaled paint rasterises 1:1 and tiles exactly; `patternTransform`
    // (rotations included) is sampled through the shader. Paint opacity
    // folds into the tile pixels, mirroring the gradient stops.
    Shader patternPaint(in string id, in FRect bbox, float paintAlpha)
    {
        PatternServer ps;
        if (!patternResolve(doc, id, bbox, vpW, vpH, ps))
            return null;

        if (ps.W <= 0.0f || ps.H <= 0.0f) // reachable only with a viewBox
            return new ColorShader(Color(0)); // "invisible" tile: a valid
                                              // server painting no area, so
                                              // the fallback stays unused
                                              // (pservers-pattern-09-f #3)

        if (patternDepth >= 8)
            return null; // deep/cyclic pattern nesting: paint nothing

        // Device px per pattern coord unit: sqrt|det| of the linear part of
        // CTM·patternTransform (the CTM already carries the root zoom).
        Matrix full = canvas.matrix * ps.pt;
        float s = sqrt(abs(full[0][0] * full[1][1] - full[0][1] * full[1][0]));
        if (!(s > 0.0f))
            return null; // degenerate CTM: nothing lands on the canvas
        s = min(s, 4.0f);
        if (ps.W * s > 1024.0f || ps.H * s > 1024.0f)
            s = 1024.0f / max(ps.W, ps.H);

        int tw = max(to!int(ceil(ps.W * s)), 1);
        int th = max(to!int(ceil(ps.H * s)), 1);

        // Content -> tile rect (0,0,W,H): a viewBox fits through
        // preserveAspectRatio, objectBoundingBox content units scale by
        // the referencing shape's bbox, else content runs in pattern units.
        Matrix cm;
        cm.reset();
        if (auto vbRaw = ps.viewBoxRaw)
        {
            float[4] vb;
            try
                parseViewBox(vb, vbRaw);
            catch (Exception)
                return null; // malformed viewBox: server in error
            if (vb[2] <= 0 || vb[3] <= 0)
                return null;
            cm = viewFit(vb, ps.W, ps.H,
                parsePAR(ps.parRaw.length ? ps.parRaw : "xMidYMid meet"));
        }
        else if (ps.contentBBox)
            cm.setScale(bbox.width, bbox.height);

        Renderer t;
        t.doc = doc;
        t.patternDepth = patternDepth + 1;
        t.bmp = Bitmap(Bitmap.Config.ARGB_8888, tw, th);
        t.canvas = new Canvas(t.bmp);
        t.inRoot = true; // skip setupRoot: the tile canvas is set up here
        t.vpW = ps.W;
        t.vpH = ps.H;
        Matrix sc;
        sc.setScale(s, s);
        t.canvas.matrix = sc * cm;

        // Presentation attributes on the chain act as the content's
        // inheritance context (href ancestors first, self last).
        foreach_reverse (ref e; ps.chain)
            t.pushStyle(e.attrs);
        foreach (ch; ps.content)
            t.renderChild(ch);

        immutable pa = to!ubyte(round(clamp(paintAlpha, 0f, 1f) * 255));
        PMColor[][] rows;
        rows.length = th;
        foreach (y; 0 .. th)
        {
            rows[y] = t.bmp.getLine!PMColor(y)[0 .. tw].dup;
            if (pa < 255)
                foreach (ref px; rows[y])
                    px = alphaMul(px, alphaScale(pa));
        }
        return new PatternShader(rows, ps.X, ps.Y, ps.W, ps.H, s, ps.pt.inverted);
    }

    // clip-path and mask (SVG 1.1 §14.3, §14.1): rasterise this paint
    // into a full-canvas scratch, multiply every referenced <clipPath>'s
    // coverage (Style.clipUrls) and every <mask>'s value (Style.maskUrls)
    // into it, then sprite-composite the result. The engine has no path
    // boolean ops, so clipping is offscreen compositing at the SVG
    // layer. A broken reference (unknown id, wrong target kind, cycle)
    // drops the paint entirely - §14.3.1 renders the element not at
    // all, no fallback (masking-path-08-b's `url(#unknown)`; the same
    // nonexistent-reference rule covers `mask`) - and so does an empty
    // layer: empty clipPath, all children display:none, or
    // objectBoundingBox units against a degenerate bbox.
    void maskedPaint(in Style s, Paint fillP, Paint strokeP,
        bool doFill, bool doStroke, in Path stroked, bool doMarkers = false)
    {
        if (clipDepth >= 8)
            return; // clip/mask nested inside clipPath/mask content

        immutable bbox = path.bounds; // objectBoundingBox units basis
        auto scratch = Bitmap(Bitmap.Config.ARGB_8888, bmp.width, bmp.height);
        scratch.eraseColor(Color(0));
        Canvas oc = new Canvas(scratch);
        oc.matrix = canvas.matrix;
        if (doFill)
        {
            path.fillRule = clipMode ? s.clipRule : s.fillRule;
            oc.drawPath(path, fillP);
        }
        if (doStroke)
            oc.drawPath(stroked, strokeP);
        // Markers belong to the element's paint, so the element's
        // clip/mask applies to them too (§11.4).
        if (doMarkers)
            drawMarkers(s, oc, scratch);

        foreach (clipId; s.clipUrls)
            if (!clipMultiply(clipId, scratch, bbox))
                return; // broken reference or empty clip: not rendered
        foreach (maskId; s.maskUrls)
            if (!maskMultiply(maskId, scratch, bbox))
                return; // broken reference or empty mask: not rendered

        bool any;
        foreach (y; 0 .. bmp.height)
            foreach (ref px; scratch.getLine!PMColor(y))
                any |= px.a != 0;
        if (!any)
            return;

        blendPM(scratch);
    }

    // Composite a full-canvas scratch over the device with standard PM
    // src-over. Not canvas.drawBitmap: the sprite blit premultiplies its
    // source while blending (S32A_Opaque_BlitRow32), i.e. it wants a
    // straight-ARGB buffer, and scratch is already premultiplied - its own
    // alpha would scale twice. scratch is exactly as big as bmp, so the
    // viewport clip is a no-op and a plain blend matches it.
    void blendPM(in Bitmap scratch)
    {
        foreach (y; 0 .. bmp.height)
        {
            auto d = bmp.getLine!PMColor(y);
            foreach (x, ref px; scratch.getLine!PMColor(y))
            {
                if (px.a == 255)
                    d[x]._color = px;
                else if (px.a)
                    d[x]._color = px + alphaMul(d[x], invAlphaScale(px.a));
            }
        }
    }

    // Rasterise the clipPath `id` as a mask (same user-space CTM as the
    // paint) and multiply its coverage into `scratch`. Returns false on
    // a broken reference or an empty mask - either way the painted
    // element is not rendered.
    bool clipMultiply(in string id, ref Bitmap scratch, in FRect bbox)
    {
        immutable idx = doc.byId(id);
        if (idx == Document.unknown)
            return false;
        bool invalid;
        const string[] clipKinds = ["clipPath"];
        auto chain = hrefChain(doc, idx, invalid, clipKinds);
        if (invalid || chain.empty || chain[0].name != "clipPath")
            return false;

        // clipPathUnits="objectBoundingBox" (§14.3.1) puts the children
        // in fractions of the painted geometry's bbox, mapped along the
        // element's own user axes - the same §7.11 supplemental matrix
        // paint servers get. A degenerate bbox makes the clip empty.
        auto maskBmp = Bitmap(Bitmap.Config.ARGB_8888, bmp.width, bmp.height);
        maskBmp.eraseColor(Color(0));
        Renderer m;
        m.doc = doc;
        m.bmp = maskBmp;
        m.canvas = new Canvas(maskBmp);
        m.inRoot = true;
        m.clipMode = true;
        m.clipDepth = clipDepth + 1;
        m.vpW = vpW;
        m.vpH = vpH;
        m.docBase = docBase; // <image> hrefs inside subtrees resolve as
        // they would in the main document (04-b's mask contains one)
        m.canvas.matrix = canvas.matrix;
        if (auto u = strAttr(chain, "clipPathUnits"))
            if (toLower(u) == "objectboundingbox")
            {
                if (bbox.width <= 0 || bbox.height <= 0)
                    return false;
                Matrix bb;
                bb.reset();
                bb[0][0] = bbox.width;
                bb[1][1] = bbox.height;
                bb[0][2] = bbox.left;
                bb[1][2] = bbox.top;
                m.canvas.matrix = canvas.matrix * bb;
            }

        // Inheritance: the clipPath subtree sees the chain's own
        // presentation attributes and nothing from the referencing
        // element's ancestors - starting the fresh style stack at the
        // chain is exactly masking-path-12-f's non-inheritance rule
        // (and keeps an inherited clip-path out of the mask itself).
        // href ancestors first, self last; content rides along from the
        // first chain element that provides children.
        foreach_reverse (ref e; chain)
            m.pushStyle(e.attrs);
        foreach (ref e; chain)
            if (e.children.length)
            {
                foreach (ch; e.children)
                    m.renderChild(ch);
                break;
            }

        bool any;
        foreach (y; 0 .. bmp.height)
        {
            auto r = scratch.getLine!PMColor(y);
            auto k = maskBmp.getLine!PMColor(y);
            foreach (x, ref px; r)
            {
                // (assign _color, not px: the implicit PMColor(Color)
                // constructor would premultiply the pixel twice)
                px._color = alphaMul(px, alphaScale(k[x].a));
                any |= px.a != 0;
            }
        }
        return any;
    }

    // Rasterise the <mask> `id` (§14.1) with normal paint semantics -
    // unlike a clipPath's opaque geometry, everything the children
    // paint (colour, gradients, opacity) shapes the mask - and multiply
    // its per-pixel value into `scratch`. The value is the Rec.709
    // luminance, or plain alpha under maskType="alpha". PMColor stores
    // premultiplied, so the weighted channel sum already equals
    // luminance x alpha. The mask region (maskUnits frame, defaults
    // -10%,-10%,120%,120%) bounds where anything can show: referrer
    // pixels whose user-space centres fall outside it multiply by zero.
    bool maskMultiply(in string id, ref Bitmap scratch, in FRect bbox)
    {
        immutable idx = doc.byId(id);
        if (idx == Document.unknown)
            return false;
        bool invalid;
        const string[] maskKinds = ["mask"];
        auto chain = hrefChain(doc, idx, invalid, maskKinds);
        if (invalid || chain.empty || chain[0].name != "mask")
            return false;

        immutable bboxUnits =
            !equalCase(strAttr(chain, "maskUnits"), "userspaceonuse");
        if (bboxUnits && (bbox.width <= 0 || bbox.height <= 0))
            return false; // degenerate bbox: empty region, not rendered

        // The region attributes as fractions (objectBoundingBox) or
        // lengths (userSpaceOnUse); a trailing % scales by the unit
        // either way, and defaults are -10%,-10%,120%,120%.
        float region(string name, float deflt, float unit)
        {
            float v = deflt;
            bool pct;
            if (auto raw = strAttr(chain, name))
            {
                try
                {
                    auto t = strip(raw);
                    if (t.length > 1 && t[$-1] == '%')
                    {
                        pct = true;
                        v = to!float(t[0 .. $-1]);
                    }
                    else
                        v = to!float(t);
                }
                catch (ConvException)
                    v = deflt;
            }
            return pct ? v / 100.0f * unit : (bboxUnits ? v * unit : v);
        }

        immutable wx = bboxUnits ? bbox.width : vpW;
        immutable wy = bboxUnits ? bbox.height : vpH;
        immutable rx = region("x", -0.10f, wx) + (bboxUnits ? bbox.left : 0.0f);
        immutable ry = region("y", -0.10f, wy) + (bboxUnits ? bbox.top : 0.0f);
        immutable rw = region("width", 1.20f, wx);
        immutable rh = region("height", 1.20f, wy);
        if (!(rw > 0) || !(rh > 0))
            return false; // negative or malformed extent: invalid
        immutable FRect reg = FRect(rx, ry, rx + rw, ry + rh);

        // Mask content renders under the plain pipeline (no clipMode):
        // paint, opacity, gradients all matter.
        auto maskBmp = Bitmap(Bitmap.Config.ARGB_8888, bmp.width, bmp.height);
        maskBmp.eraseColor(Color(0));
        Renderer m;
        m.doc = doc;
        m.bmp = maskBmp;
        m.canvas = new Canvas(maskBmp);
        m.inRoot = true;
        m.clipDepth = clipDepth + 1;
        m.vpW = vpW;
        m.vpH = vpH;
        m.docBase = docBase; // <image> hrefs inside subtrees resolve as
        // they would in the main document (04-b's mask contains one)
        m.canvas.matrix = canvas.matrix;

        // maskContentUnits="objectBoundingBox": children live in
        // fractions of the paint bbox - the same supplemental matrix
        // as clipPathUnits (§14.2).
        if (auto u = strAttr(chain, "maskContentUnits"))
            if (toLower(u) == "objectboundingbox")
            {
                Matrix bb;
                bb.reset();
                bb[0][0] = bbox.width;
                bb[1][1] = bbox.height;
                bb[0][2] = bbox.left;
                bb[1][2] = bbox.top;
                m.canvas.matrix = canvas.matrix * bb;
            }

        // Inheritance follows masking-path-12-f just like clipPath: the
        // chain's own attributes only, never the referrer's ancestors -
        // which also keeps an inherited mask out of the mask itself.
        // href ancestors first, self last; content from the first chain
        // element that provides children.
        foreach_reverse (ref e; chain)
            m.pushStyle(e.attrs);
        foreach (ref e; chain)
            if (e.children.length)
            {
                foreach (ch; e.children)
                    m.renderChild(ch);
                break;
            }

        // Multiply in the mask value, testing region membership through
        // the inverse CTM so a transformed mask region stays exact.
        immutable alphaType = equalCase(strAttr(chain, "maskType"), "alpha");
        immutable inv = canvas.matrix.inverted;
        bool any;
        foreach (y; 0 .. bmp.height)
        {
            auto r = scratch.getLine!PMColor(y);
            auto k = maskBmp.getLine!PMColor(y);
            foreach (x, ref px; r)
            {
                // Outside the mask region the value is zero; a bare
                // `float v;` would seed it with float.init - NaN.
                float v = 0f;
                immutable dx = x + 0.5f, dy = y + 0.5f;
                immutable ux = inv[0][0] * dx + inv[0][1] * dy + inv[0][2];
                immutable uy = inv[1][0] * dx + inv[1][1] * dy + inv[1][2];
                if (ux >= reg.left && ux < reg.right
                    && uy >= reg.top && uy < reg.bottom)
                {
                    immutable kx = k[x];
                    v = alphaType
                        ? kx.a / 255.0f
                        : (0.2126f*kx.r + 0.7152f*kx.g + 0.0722f*kx.b) / 255.0f;
                }
                // Mutate _color directly: `px = <Color expression>`
                // would fire PMColor's implicit this(Color) constructor
                // and premultiply the already-premultiplied pixel
                // twice (alphaScale(255) == 256 hides this on opaque
                // clip masks, but not on a soft mask's AA ramp).
                px._color = alphaMul(px,
                    alphaScale(to!ubyte(round(clamp(v, 0f, 1f) * 255))));
                any |= px.a != 0;
            }
        }
        return any;
    }

    // SVG 1.1 §11.4: markers decorate the vertices of a stroked or
    // filled path.
    // Walk the path with plain iteration (not the fill pass): the closing
    // edge of a `Z` arrives as the explicit Line it is followed by the
    // Close verb, so junctions and tangents mirror the document's own
    // vertices - the rasteriser's implicit closure must not invent
    // marker geometry. Vertex rule per subpath: start at the first
    // junction, mid at interior junctions, end at the last; a moveto is
    // only ever a start/end junction, and a subpath without a segment
    // (a lone moveto) gets nothing.
    void drawMarkers(in Style s, Canvas target, Bitmap dev)
    {
        struct Junction
        {
            FPoint p;
            FPoint tin, tout; // unit tangents, zero on a degenerate edge
        }

        Junction[][] subs;
        foreach (ref Path.Verb v, ref FPoint[] p; path)
        {
            final switch (v)
            {
            case Path.Verb.Move:
                subs.length += 1;
                subs[$ - 1] ~= Junction(p[0], FPoint(0, 0), FPoint(0, 0));
                break;
            case Path.Verb.Line: // pts = [from, to]
                immutable t = unit(p[1] - p[0]);
                subs[$ - 1][$ - 1].tout = t;
                subs[$ - 1] ~= Junction(p[1], t, FPoint(0, 0));
                break;
            case Path.Verb.Quad: // pts = [from, ctrl, to]
                subs[$ - 1][$ - 1].tout = unit(p[1] - p[0]);
                subs[$ - 1] ~= Junction(p[2], unit(p[2] - p[1]), FPoint(0, 0));
                break;
            case Path.Verb.Cubic: // pts = [from, c1, c2, to]
                subs[$ - 1][$ - 1].tout = unit(p[1] - p[0]);
                subs[$ - 1] ~= Junction(p[3], unit(p[3] - p[2]), FPoint(0, 0));
                break;
            case Path.Verb.Close:
                break; // closing edge already arrived as its Line
            }
        }

        foreach (ref sub; subs)
            if (sub.length > 1) // a segment is needed to hang markers on
                foreach (i, ref jn; sub)
                {
                    bool isStart;
                    string url;
                    FPoint dir;
                    if (i == 0)
                    {
                        isStart = true;
                        url = s.markerStart;
                        dir = jn.tout;
                    }
                    else if (i == sub.length - 1)
                    {
                        url = s.markerEnd;
                        dir = jn.tin;
                    }
                    else
                    {
                        url = s.markerMid;
                        dir = unit(jn.tin + jn.tout); // tangent bisector
                        if (dir.x == 0 && dir.y == 0)
                            dir = jn.tout; // cusp reversal: no bisector
                    }
                    if (url.empty)
                        continue;
                    // Zero-length edge: with butt caps the stroke paints
                    // no dot, so its start/end markers stay hidden too;
                    // round/square caps paint them at zero orientation.
                    if (dir.x == 0 && dir.y == 0 && s.caps == CapStyle.Butt)
                        continue;
                    renderMarker(url, jn.p, dir, isStart, s, target, dev);
                }
    }

    // Paint one marker at a vertex. Its coordinate system: translate to
    // the vertex, rotate per `orient` (default 0 - fixed; auto/auto-
    // start-reverse follow the path direction), scale by stroke-width
    // unless markerUnits="userSpaceOnUse", map through viewBox, then
    // position so that (refX, refY) - in viewBox space when there is a
    // viewBox, marker space otherwise - lands on the vertex. Inheritance
    // follows the clipPath/mask subtree rule (masking-path-12-f): the
    // chain's own attributes, nothing from the referrer's ancestors.
    void renderMarker(in string url, in FPoint at, in FPoint dir,
        bool isStart, in Style s, Canvas target, Bitmap dev)
    {
        immutable idx = doc.byId(url);
        if (idx == Document.unknown)
            return; // broken reference paints nothing
        bool invalid;
        const string[] markerKinds = ["marker"];
        auto chain = hrefChain(doc, idx, invalid, markerKinds);
        if (invalid || chain.empty || chain[0].name != "marker")
            return;

        immutable swUnits =
            !equalCase(strAttr(chain, "markerUnits"), "userspaceonuse");

        auto lc = lengthCtx();
        float mlen(string raw, float deflt, float pctRef)
        {
            lc.pctRef = pctRef;
            try
                return parseLength(raw, lc);
            catch (Exception)
                return deflt;
        }

        auto raw = strAttr(chain, "markerWidth");
        immutable mw = raw.length ? mlen(raw, 3.0f, vpW) : 3.0f;
        raw = strAttr(chain, "markerHeight");
        immutable mh = raw.length ? mlen(raw, 3.0f, vpH) : 3.0f;
        if (!(mw > 0) || !(mh > 0))
            return; // negative viewport: error, marker not rendered

        raw = strAttr(chain, "refX");
        immutable rx = raw.length ? mlen(raw, 0.0f, vpW) : 0.0f;
        raw = strAttr(chain, "refY");
        immutable ry = raw.length ? mlen(raw, 0.0f, vpH) : 0.0f;

        // orient: default 0 - and the local must start at 0, since a
        // bare `float angle;` seeds float.init (NaN) and NaN != 0 turns
        // the default into a rotate-by-NaN matrix.
        float angle = 0.0f;
        if (auto o = strAttr(chain, "orient"))
        {
            if (equalCase(o, "auto"))
                angle = atan2(dir.y, dir.x) * 180.0f / PI;
            else if (equalCase(o, "auto-start-reverse")) // SVG 2, cheap
                angle = atan2(dir.y, dir.x) * 180.0f / PI +
                    (isStart ? 180.0f : 0.0f);
            else
                try
                    angle = to!float(strip(o));
                catch (ConvException)
                    angle = 0.0f; // malformed orient: treat as 0
        }

        Renderer m;
        m.doc = doc;
        m.bmp = dev;
        m.canvas = new Canvas(dev);
        m.inRoot = true;
        m.markerMode = true; // §11.4: no markers on marker content
        m.clipDepth = clipDepth + 1;
        m.vpW = vpW;
        m.vpH = vpH;
        m.docBase = docBase; // <image> hrefs inside subtrees resolve as
        // they would in the main document (04-b's mask contains one)

        Matrix mm;
        mm.reset();
        Matrix t;
        t.reset();
        t.setTranslate(at.x, at.y);
        mm = mm * t;
        if (angle != 0.0f)
        {
            Matrix r;
            r.reset();
            r.setRotate(angle); // degrees, clockwise (y is down)
            mm = mm * r;
        }
        if (swUnits && s.strokeWidth != 1.0f)
        {
            Matrix q;
            q.reset();
            q.setScale(s.strokeWidth, s.strokeWidth);
            mm = mm * q;
        }
        Matrix vf;
        vf.reset();
        FPoint vref = FPoint(rx, ry);
        if (auto vbRaw = strAttr(chain, "viewBox"))
        {
            float[4] vb;
            try
            {
                parseViewBox(vb, vbRaw);
                if (vb[2] > 0 && vb[3] > 0)
                {
                    auto parRaw = strAttr(chain, "preserveAspectRatio");
                    vf = viewFit(vb, mw, mh,
                        parsePAR(parRaw.length ? parRaw : "xMidYMid meet"));
                    // refX/refY live in the viewBox space, and aligning
                    // them with the vertex absorbs the viewport
                    // translation: a content point lands at
                    // Vb(c) - Vb(ref) around the vertex (exactly the
                    // test suite's own expansion, painting-marker-
                    // 06-f's translate(8) scale(0.2) translate(-ref)).
                    vref = FPoint(vf[0][0] * rx + vf[0][1] * ry + vf[0][2],
                                  vf[1][0] * rx + vf[1][1] * ry + vf[1][2]);
                }
            }
            catch (Exception) {} // malformed viewBox: attribute ignored
        }
        t.reset();
        t.setTranslate(-vref.x, -vref.y);
        mm = mm * t;
        m.canvas.matrix = target.matrix * mm; // marker viewport space

        // overflow: hidden is the default for a marker viewport, so
        // content is clipped to the viewport rect. Clipping happens in
        // viewport space, before the viewBox mapping is folded into
        // the matrix - no inverse-viewBox arithmetic needed. Engine
        // clips are device-space AABBs: exact for axis-aligned
        // viewports (07-f's oversized triangle), a bounding box for
        // rotated ones - and a no-op for content that fits its
        // viewport, which is all of the suite's rotated markers.
        // overflow="visible" skips the clip.
        if (!equalCase(strAttr(chain, "overflow"), "visible"))
            m.canvas.clipRect(IRect(0, 0, to!int(min(mw, 1_000_000.0f)),
                to!int(min(mh, 1_000_000.0f))));

        mm = mm * vf;
        m.canvas.matrix = target.matrix * mm; // content space

        foreach_reverse (ref e; chain)
            m.pushStyle(e.attrs);
        foreach (ref e; chain)
            if (e.children.length)
            {
                foreach (ch; e.children)
                    m.renderChild(ch);
                break;
            }
    }

    // Paint the current `path` with the style resolved from `attr`: fill
    // first, then the stroke over it (SVG paint order).
    void flushPath(in string[string] attr)
    {
        const s = pushStyle(attr);
        scope (exit) popStyle();

        // Effective paint alpha: the group `opacity` multiplies the
        // per-paint opacity (fill-opacity/stroke-opacity) and the
        // color's own alpha.
        immutable op = clamp(s.opacity, 0f, 1f);
        immutable bbox = path.bounds; // objectBoundingBox paint-server basis
        if (bboxTrack)
            bboxAccum = unionBox(bboxAccum, bbox); // filter region basis (§15.5)
        Paint fillP = resolvePaint(true, s, op * clamp(s.fillOpacity, 0f, 1f), bbox);
        Paint strokeP = resolvePaint(false, s, op * clamp(s.strokeOpacity, 0f, 1f), bbox);

        auto doFill = s.visible && (fillP.shader !is null || fillP.color.a != 0);
        auto doStroke = s.visible
            && (strokeP.shader !is null || strokeP.color.a != 0) && s.strokeWidth > 0;

        if (clipMode)
        {
            // Painting a clip mask: a <clipPath> child contributes its
            // filled outline fully opaque - fill/stroke paint and the
            // opacity properties are all irrelevant, and so is
            // visibility (masking-path-08-b). display:none children
            // never get here; renderChild drops those.
            doFill = true;
            doStroke = false;
            fillP = Paint(Color.Black);
        }

        Path stroked;
        if (doStroke)
        {
            if (s.dash.length)
            {
                auto dashed = svgDash(path, s.dash, s.dashOffset);
                stroked = strokePath(dashed, s.strokeWidth, s.caps, s.joins, s.miterLimit);
            }
            else
                stroked = strokePath(path, s.strokeWidth, s.caps, s.joins, s.miterLimit);
        }

        if (doFill || doStroke)
        {
            // Markers paint at vertices when the element is stroked OR
            // filled (§11.4.1) - painting-marker-07-f's fill-only paths
            // carry markers; marker content itself never nests markers.
            // Text markers are not supported (yet).
            immutable doMarkers = (doFill || doStroke) && !markerMode
                && (s.markerStart.length || s.markerMid.length
                    || s.markerEnd.length);
            if (s.clipUrls.length || s.maskUrls.length)
                maskedPaint(s, fillP, strokeP, doFill, doStroke, stroked,
                    doMarkers);
            else
            {
                if (doFill)
                {
                    // Subpaths are implicitly closed at raster time
                    // (Path.applyFilled); no path.close() needed here.
                    // path.reset() does not clear fillRule, so assign
                    // per flush; clip masks fill under clip-rule (§14.4).
                    path.fillRule = clipMode ? s.clipRule : s.fillRule;
                    canvas.drawPath(path, fillP);
                }
                if (doStroke)
                    canvas.drawPath(stroked, strokeP);
                if (doMarkers)
                    drawMarkers(s, canvas, bmp);
            }
        }
        path.reset();
    }

    // Render the accumulated text run with the style currently on top
    // of the style stack: the glyph outlines are built into `path` and
    // reuse the stroke/fill pipeline of `flushPath`, so
    // fill="none" stroke="..." text works.
    void flushText()
    {
        if (styles.empty)
            return;
        const s = styles.data.back;

        lastAdvance = 0.0f;
        if (textBuf.empty)
        {
            path.reset();
            return;
        }

        // Resolve the face from the (inherited) family/weight/slant.
        // (findFace's variadic template can't deduce qualified
        // `immutable` enums, so copy them to plain locals first.)
        TypeFace.Weight w = s.weight;
        TypeFace.Slant sl = s.slant;
        string fam = s.family;
        TypeFace face = fam.length
            ? TypeFace.findFace(w, sl, fam)
            : TypeFace.findFace(w, sl);
        auto cache = getGlyphCache(face, s.fontSize);

        // text-anchor: offset the baseline origin by the run width.
        FPoint at = textPos;
        lastAdvance = measureText(textBuf, cache);
        switch (s.anchor)
        {
        case TextPaint.TextAlign.Center:
            at.x -= 0.5 * lastAdvance;
            break;
        case TextPaint.TextAlign.Right:
            at.x -= lastAdvance;
            break;
        default:
            break;
        }

        // Build the glyph outlines at their running baseline positions.
        path.reset();
        FPoint pos = at;
        foreach (gl; cache.glyphStream(textBuf,
                Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path))
        {
            Matrix m;
            m.setTranslate(pos.x, pos.y);
            gl.path.apply((ref Path.Verb v, ref FPoint[] pts)
            {
                m.mapPoints(pts);
                final switch (v)
                {
                case Path.Verb.Move:
                    path.moveTo(pts[0]);
                    break;
                case Path.Verb.Line:
                    path.lineTo(pts[1]);
                    break;
                case Path.Verb.Quad:
                    path.quadTo(pts[1], pts[2]);
                    break;
                case Path.Verb.Cubic:
                    path.cubicTo(pts[1], pts[2], pts[3]);
                    break;
                case Path.Verb.Close:
                    path.close();
                    break;
                }
                return 0;
            });
            pos += gl.advance;
        }

        // Same effective-opacity compositing as flushPath; glyph outlines
        // keep the non-zero winding rule.
        immutable op = clamp(s.opacity, 0f, 1f);
        immutable bbox = path.bounds; // objectBoundingBox paint-server basis
        if (bboxTrack)
            bboxAccum = unionBox(bboxAccum, bbox); // filter region basis (§15.5)
        Paint fillP = resolvePaint(true, s, op * clamp(s.fillOpacity, 0f, 1f), bbox);
        Paint strokeP = resolvePaint(false, s, op * clamp(s.strokeOpacity, 0f, 1f), bbox);

        auto doFill = s.visible && (fillP.shader !is null || fillP.color.a != 0);
        auto doStroke = s.visible
            && (strokeP.shader !is null || strokeP.color.a != 0) && s.strokeWidth > 0;

        if (clipMode)
        {
            // Clip mask: text contributes its glyph outlines, opaque
            // (masking-path-04-b clips with <text> inside the clipPath).
            doFill = true;
            doStroke = false;
            fillP = Paint(Color.Black);
        }

        Path stroked;
        if (doStroke)
        {
            if (s.dash.length)
            {
                auto dashed = svgDash(path, s.dash, s.dashOffset);
                stroked = strokePath(dashed, s.strokeWidth, s.caps, s.joins, s.miterLimit);
            }
            else
                stroked = strokePath(path, s.strokeWidth, s.caps, s.joins, s.miterLimit);
        }

        if (doFill || doStroke)
        {
            if (s.clipUrls.length || s.maskUrls.length)
                maskedPaint(s, fillP, strokeP, doFill, doStroke, stroked);
            else
            {
                if (doFill)
                {
                    // Glyph outlines carry explicit Close verbs; the fill
                    // closure (applyFilled) covers any straggler subpath.
                    // Pin the rule to non-zero on purpose (the comment
                    // above this block is right): convention-directed
                    // TrueType/CFF outlines fill the same under both
                    // rules, and `path` is shared with flushPath whose
                    // fillRule assignment above would otherwise leak
                    // into text. Clip mask: clip-rule governs instead.
                    path.fillRule = clipMode ? s.clipRule : Path.FillRule.NonZero;
                    canvas.drawPath(path, fillP);
                }
                if (doStroke)
                    canvas.drawPath(stroked, strokeP);
            }
        }
        path.reset();
        textBuf = "";
    }

    // Build the path for a shape and flush it with its style.
    // §9.8 <image>: the href names a raster file resolved against the
    // element's xml:base chain (falling back to the document's own
    // directory). x/y place a viewport of width x height (defaulting
    // to the image's natural size); the image maps into it exactly as
    // a viewBox="0 0 nw nh" with the element's preserveAspectRatio
    // (default xMidYMid meet). An empty or fragment href, an
    // unsupported URL scheme, a zero/negative viewport and an
    // undecodable or missing file all render nothing.
    void imageElement(in string[string] a)
    {
        const s = pushStyle(a);
        scope (exit) popStyle();
        if (!s.visible)
            return;

        immutable path = resolveHref(s.baseUrl.length ? s.baseUrl : docBase,
            a.get("href", a.get("xlink:href", "")));
        if (path is null)
            return;
        auto img = loadSVGImage(path);
        if (img.config == Bitmap.Config.NoConfig)
            return; // broken reference: §9.8 renders nothing

        immutable float nw = img.width, nh = img.height;
        auto lc = lengthCtx();
        immutable x = a.convLen("x", 0.0f, lc, RefAxis.width);
        immutable y = a.convLen("y", 0.0f, lc, RefAxis.height);
        immutable w = a.convLen("width", nw, lc, RefAxis.width);
        immutable h = a.convLen("height", nh, lc, RefAxis.height);
        if (!(w > 0) || !(h > 0))
            return;

        float[4] vb = [0, 0, nw, nh];
        immutable fit = viewFit(vb, w, h,
            parsePAR(a.get("preserveAspectRatio", "")));

        // Paint only the overlap of viewport and image in natural-px
        // space: that intersection IS the viewport clip "slice"
        // overflow needs, exact even at fractional sizes (viewFit is
        // axis-aligned, so the inverse per axis is just the division).
        immutable sx = fit[0][0], sy = fit[1][1];
        FRect vis = FRect(-fit[0][2] / sx, -fit[1][2] / sy,
            (w - fit[0][2]) / sx, (h - fit[1][2]) / sy);
        if (!vis.intersect(FRect(0, 0, nw, nh)))
            return;

        // The filter region basis is the element's geometry bbox in user
        // space: for <image> that is the viewport rect (§7.8), not the
        // natural-pixel box the shader path below draws into.
        if (bboxTrack)
            bboxAccum = unionBox(bboxAccum, FRect(x, y, x + w, y + h)); // §15.5

        canvas.save();
        scope (exit) canvas.restore();
        Matrix t;
        t.reset();
        t.setTranslate(x, y);
        canvas.matrix = canvas.matrix * t * fit;

        // Paint color is ignored on the shader path (and gradients
        // fold opacity at build time): fold `opacity` into a
        // throwaway copy. The pixels are straight ARGB, so scaling
        // the stored alpha is exactly right - the shader then
        // premultiplies with the scaled alpha once.
        Bitmap drawn = img;
        immutable alpha = clamp(s.opacity, 0f, 1f);
        if (alpha < 1f)
        {
            drawn = Bitmap(Bitmap.Config.ARGB_8888, img.width, img.height);
            immutable sc = alphaScale(to!ubyte(round(alpha * 255)));
            foreach (py; 0 .. img.height)
            {
                auto row = img.getLine!Color(py);
                auto dst = drawn.getLine!Color(py);
                foreach (i; 0 .. row.length)
                {
                    dst[i] = row[i];
                    dst[i].a = alphaMul(row[i].a, sc);
                }
            }
        }

        Paint p;
        p.shader = new ImageShader(drawn, sx, sy);
        Path q;
        q.addRect(vis);
        canvas.drawPath(q, p);
    }

    void shape(string tag, in string[string] a)
    {
        auto lc = lengthCtx();
        switch (tag)
        {
        case "rect":
            {
                auto pt = FPoint(a.convLen("x", 0.0f, lc, RefAxis.width),
                                 a.convLen("y", 0.0f, lc, RefAxis.height));
                auto sz = FSize(a.convLen("width", 0.0f, lc, RefAxis.width),
                                a.convLen("height", 0.0f, lc, RefAxis.height));
                enforce(sz.width >= 0 && sz.height >= 0);
                auto rx = a.convLen("rx", 0.0f, lc, RefAxis.width);
                auto ry = a.convLen("ry", 0.0f, lc, RefAxis.height);
                enforce(rx >= 0 && ry >= 0);
                if (rx == 0) rx = ry;
                else if (ry == 0) ry = rx;
                rx = min(rx, 0.5 * sz.width);
                ry = min(ry, 0.5 * sz.height);
                if (!sz.empty)
                {
                    path.addRoundRect(FRect(pt, sz), rx, ry);
                    flushPath(a);
                }
            }
            break;

        case "circle":
            {
                immutable pt = FPoint(a.convLen("cx", 0.0f, lc, RefAxis.width),
                                      a.convLen("cy", 0.0f, lc, RefAxis.height));
                immutable r = a.convLen("r", 0.0f, lc, RefAxis.diagonal);
                enforce(r >= 0);
                if (r > 0)
                {
                    path.addOval(FRect(pt - r, pt + r));
                    flushPath(a);
                }
            }
            break;

        case "ellipse":
            {
                immutable pt = FPoint(a.convLen("cx", 0.0f, lc, RefAxis.width),
                                      a.convLen("cy", 0.0f, lc, RefAxis.height));
                immutable rad = FSize(a.convLen("rx", 0.0f, lc, RefAxis.width),
                                      a.convLen("ry", 0.0f, lc, RefAxis.height));
                enforce(rad.width >= 0 && rad.height >= 0);
                if (!rad.empty)
                {
                    path.addOval(FRect(pt - rad, pt + rad));
                    flushPath(a);
                }
            }
            break;

        case "line":
            {
                immutable p0 = FPoint(a.convLen("x1", 0.0f, lc, RefAxis.width),
                                      a.convLen("y1", 0.0f, lc, RefAxis.height));
                immutable p1 = FPoint(a.convLen("x2", 0.0f, lc, RefAxis.width),
                                      a.convLen("y2", 0.0f, lc, RefAxis.height));

                // Zero-length lines are never emitted: they add nothing to
                // fills, and the wavelet stroker asserts on degenerate
                // round-cap subpaths. (Browsers paint round/square-cap
                // zero-length segments as dots; TODO.)
                if (p0 != p1)
                {
                    path.moveTo(p0);
                    path.lineTo(p1);
                    flushPath(a);
                }
            }
            break;

        case "polyline":
            {
                string s = a.get("points", "");
                try path.addSVGPolyLine(s);
                catch (Exception e2) {}
                flushPath(a);
            }
            break;

        case "polygon":
            {
                string s = a.get("points", "");
                try path.addSVGPolyLine(s);
                catch (Exception e2) {}
                path.close();
                flushPath(a);
            }
            break;

        case "path":
            {
                string s = a.get("d", "");
                try path.addSVGPath(s);
                catch (Exception e2) {}
                flushPath(a);
            }
            break;

        case "image":
            // An <image> inside <clipPath> is not a valid clip child
            // (§14.3: only shapes, text and <use> count): it paints
            // nothing and contributes nothing to the clip mask.
            if (!clipMode)
                imageElement(a);
            break;

        default:
            // <switch> and any other container markup
            break;
        }
    }

    // Push a nested <svg> viewport: x/y/width/height place the viewport,
    // viewBox + preserveAspectRatio map user space into it.
    void openViewport(in string[string] a)
    {
        pushStyle(a); // presentation attrs (incl. transform) wrap the viewport

        auto lc = lengthCtx(); // against the *parent* viewport
        immutable x = a.convLen("x", 0.0f, lc, RefAxis.width);
        immutable y = a.convLen("y", 0.0f, lc, RefAxis.height);
        immutable w = a.convLen("width", vpW, lc, RefAxis.width);
        immutable h = a.convLen("height", vpH, lc, RefAxis.height);
        enforce(w > 0 && h > 0, "nested <svg> needs a positive width and height");

        float[4] vb = [0.0f, 0.0f, w, h];
        if (auto p = "viewBox" in a)
        {
            parseViewBox(vb, *p);
            enforce(vb[2] > 0 && vb[3] > 0, "invalid viewBox");
        }

        canvas.save();
        canvas.matrix = canvas.matrix.preTranslate(x, y);
        canvas.matrix = canvas.matrix * viewFit(vb, w, h,
            parsePAR(a.get("preserveAspectRatio", "xMidYMid meet")));

        savedViewports ~= FSize(vpW, vpH);
        vpW = vb[2];
        vpH = vb[3];
        ++viewportDepth;
    }

    void closeViewport()
    {
        canvas.restore();
        popStyle();
        vpW = savedViewports[$-1].width;
        vpH = savedViewports[$-1].height;
        savedViewports = savedViewports[0 .. $-1];
        --viewportDepth;
    }

    // Elements whose entire content is reference material: registered in
    // the arena and the id registry, but never painted directly (clip
    // paths, gradients, markers ...), plus non-graphical and deferred-
    // profile markup.
    static bool isNonRendering(string tag)
    {
        return tag == "defs" || tag == "clipPath" || tag == "mask" ||
               tag == "pattern" || tag == "marker" || tag == "filter" ||
               tag == "symbol" || tag == "font" || tag == "font-face" ||
               tag == "glyph" || tag == "missing-glyph" ||
               tag == "altGlyphDef" || tag == "color-profile" ||
               tag == "cursor" || tag == "view" || tag == "script" ||
               tag == "style" || tag == "foreignObject";
    }

    // Returns true if the element opens a style (<g>, <text>, <tspan>, <svg>).
    bool element(string tag, in string[string] a)
    {
        switch (tag)
        {
        case "g", "a": // <a> is a plain styled container for rendering
            pushStyle(a);
            return true;

        case "svg":
            openViewport(a);
            return true;

        case "text":
            inText = true;
            textBuf = "";
            {
                // x/y (default 0/0), optionally shifted by dx/dy.
                auto lc = lengthCtx();
                textPos = FPoint(a.convLen("x", 0.0f, lc, RefAxis.width) +
                                 a.convLen("dx", 0.0f, lc, RefAxis.width),
                                 a.convLen("y", 0.0f, lc, RefAxis.height) +
                                 a.convLen("dy", 0.0f, lc, RefAxis.height));
            }
            pushStyle(a);
            return true;

        case "tspan":
            if (inText && !textBuf.empty)
            {
                // Flush the run accumulated in the enclosing element
                // (the style on top of the stack is that element's) and
                // advance the text position past it.
                flushText();
                textPos.x += lastAdvance;
            }
            // x/y (when present) reset the position absolutely; dx/dy
            // always offset it relative to the current position.
            {
                auto lc = lengthCtx();
                if ("x" in a)
                    textPos.x = a.convLen("x", 0.0f, lc, RefAxis.width);
                if ("y" in a)
                    textPos.y = a.convLen("y", 0.0f, lc, RefAxis.height);
                textPos.x += a.convLen("dx", 0.0f, lc, RefAxis.width);
                textPos.y += a.convLen("dy", 0.0f, lc, RefAxis.height);
            }
            pushStyle(a);
            return true;

        default:
            shape(tag, a);
            return false;
        }
    }

    // The element closed after its subtree was visited (the old
    // onElementEnd). An empty element takes the same path right after
    // `element`: with no children there is nothing to flush, and
    // flushText's empty-run short-circuit absorbs the <text></text> vs
    // <text/> difference.
    void closeElement(string tag)
    {
        switch (tag)
        {
        case "svg":
            if (viewportDepth) // the root <svg> did not push a viewport
                closeViewport();
            break;

        case "g", "a":
            popStyle();
            break;

        case "text", "tspan":
            if (inText)
            {
                flushText();
                popStyle();  // close the style opened at element start
                if (tag == "text")
                {
                    inText = false;
                    textBuf = "";
                }
                else
                    // the text position advances past a rendered run
                    // (spec: a following run continues after it)
                    textPos.x += lastAdvance;
            }
            else
                popStyle();  // stray tspan: keep the stack balanced
            break;

        default:
            break;
        }
    }

    // `<use>`: paint the referenced element as a deep clone at this spot.
    // The instance inherits from the `<use>` element, not from the source
    // context of the reference - walking the arena at the use site (with a
    // fresh style chain) is exactly that. References resolve through the id
    // registry, so backward and forward hrefs, and uses nested inside other
    // instances, all just work; the one thing a clone must not do is recurse
    // forever, so `useStack` tracks the expansion path and drops cycles.
    void useElement(size_t idx)
    {
        immutable inst = doc.nodes[idx];
        string href = inst.attrs.get("href", inst.attrs.get("xlink:href", ""));
        if (href.length < 2 || href[0] != '#')
            return; // external references (other documents) are not supported
        immutable target = doc.byId(href[1 .. $]);
        if (target == Document.unknown)
            return;
        foreach (t; useStack)
            if (t == target)
                return; // reference cycle: render nothing

        useStack ~= target;
        scope (exit) useStack = useStack[0 .. $ - 1];

        // The use's own attributes (transform included) wrap the instance.
        pushStyle(inst.attrs);
        scope (exit) popStyle();

        // x/y is a translate appended innermost to the transform list,
        // i.e. applied to the instance's content first.
        auto lc = lengthCtx();
        immutable x = inst.attrs.convLen("x", 0.0f, lc, RefAxis.width);
        immutable y = inst.attrs.convLen("y", 0.0f, lc, RefAxis.height);
        canvas.save();
        scope (exit) canvas.restore();
        if (x || y)
            canvas.matrix = canvas.matrix.preTranslate(x, y);

        immutable orig = doc.nodes[target];
        // The original's own attributes travel with the clone: a failing
        // conditional processing test suppresses the instance too
        // (struct-cond-overview-02-f), while one on the original's
        // ancestors does not (struct-cond-overview-05-f - the registry
        // already jumped past the parent).
        if (orig.attrs.get("display", "") == "none" || !conditionsPass(orig.attrs))
            return;

        if (orig.name == "use")
        {
            useElement(target); // an instance of an instance: same machinery
            return;
        }

        if (orig.name == "symbol" || orig.name == "svg")
        {
            // The instance of a <symbol> - or of a referenced <svg>, which
            // behaves as one - is a nested viewport: the use's x/y placed it
            // above (the svg target's own x/y are overridden), its
            // width/height size the box - falling back to the target's
            // width/height attrs, then to 100% of the current viewport -
            // and the target's viewBox + preserveAspectRatio map user
            // space into it.
            float w = inst.attrs.convLen("width", 0.0f, lc, RefAxis.width);
            float h = inst.attrs.convLen("height", 0.0f, lc, RefAxis.height);
            if (w <= 0) w = orig.attrs.convLen("width", vpW, lc, RefAxis.width);
            if (h <= 0) h = orig.attrs.convLen("height", vpH, lc, RefAxis.height);
            if (w <= 0 || h <= 0)
                return;

            float[4] vb = [0.0f, 0.0f, w, h];
            if (auto p = "viewBox" in orig.attrs)
                try
                {
                    parseViewBox(vb, *p);
                    enforce(vb[2] > 0 && vb[3] > 0, "invalid viewBox");
                }
                catch (Exception)
                    vb = [0.0f, 0.0f, w, h];

            pushStyle(orig.attrs); // the symbol's presentation attrs (transform included)
            canvas.save();
            canvas.matrix = canvas.matrix * viewFit(vb, w, h,
                parsePAR(orig.attrs.get("preserveAspectRatio", "xMidYMid meet")));
            savedViewports ~= FSize(vpW, vpH);
            vpW = vb[2];
            vpH = vb[3];
            walk(target); // the symbol's children, as if written at the use site
            vpW = savedViewports[$ - 1].width;
            vpH = savedViewports[$ - 1].height;
            savedViewports = savedViewports[0 .. $ - 1];
            canvas.restore();
            popStyle();
            return;
        }

        // Any other target (shape, g, text...): exactly as if it were
        // written here.
        element(orig.name, orig.attrs);
        walk(target);
        closeElement(orig.name);
    }

    // Conditional processing (SVG 1.1 §6): requiredFeatures,
    // requiredExtensions and systemLanguage guard an element - an element
    // whose test fails is treated as if absent from the document (inside
    // <switch> the same tests pick the one child that renders).

    // The user language this renderer presents: headless, no locale, so
    // the suite's own language is the honest choice.
    enum string userLanguage = "en";

    // The feature strings implemented (SVG 1.1 Annex I names). The list is
    // deliberately honest: only what genuinely paints is claimed, so
    // gradients/patterns/clipping/masking/markers/images/filters/animation
    // and every DOM/SVGDOM string evaluate to false until they land.
    static bool featureOK(string f)
    {
        static immutable string[] ok =
        [
            "http://www.w3.org/TR/SVG11/feature#BasicStructure",
            "http://www.w3.org/TR/SVG11/feature#Structure",
            "http://www.w3.org/TR/SVG11/feature#BasicPaint",
            "http://www.w3.org/TR/SVG11/feature#Paint",
            "http://www.w3.org/TR/SVG11/feature#BasicText",
            "http://www.w3.org/TR/SVG11/feature#BasicTransform",
            "http://www.w3.org/TR/SVG11/feature#BasicViewPort",
            "http://www.w3.org/TR/SVG11/feature#Viewport",
            "http://www.w3.org/TR/SVG11/feature#BasicShape",
            "http://www.w3.org/TR/SVG11/feature#Shape",
            "http://www.w3.org/TR/SVG11/feature#Path",
            "http://www.w3.org/TR/SVG11/feature#ConditionalProcessing",
        ];
        return ok.canFind(f);
    }

    // RFC 3066 language-range match against the user language: the range
    // matches if it equals the tag or is a leading '-'-delimited prefix of it.
    static bool langOK(string range)
    {
        immutable r = toLower(strip(range));
        if (r == "*")
            return true;
        return r == userLanguage
            || (r.length < userLanguage.length
                && userLanguage[0 .. r.length] == r
                && userLanguage[r.length] == '-');
    }

    // All three attributes present must pass. Lists separate entries with
    // whitespace and/or semicolons (SE; the DOM API splits both ways across
    // the era). An empty requiredFeatures list passes vacuously; empty
    // requiredExtensions/systemLanguage lists evaluate to false.
    static bool conditionsPass(in string[string] a)
    {
        if (auto p = "requiredFeatures" in a)
            foreach (f; splitter(replace(replace(strip(*p), ';', ' '), '\t', ' '), " "))
                if (!f.empty && !featureOK(f))
                    return false; // bogus token: this element is not supported

        // requiredExtensions: no extension is claimed, and the spec makes an
        // empty list false too - the attribute always fails if present.
        if ("requiredExtensions" in a)
            return false;

        if (auto p = "systemLanguage" in a)
        {
            bool match;
            foreach (lang; splitter(replace(strip(*p), ';', ' '), " "))
                if (!lang.empty && langOK(lang))
                {
                    match = true;
                    break;
                }
            if (!match) // no listed language matches; empty list never does
                return false;
        }
        return true;
    }

    // Paint one walked-in element: conditional processing, the skip rules
    // for reference material / display="none", the use and switch
    // dispatchers, or the ordinary element+subtree traversal.
    void renderChild(size_t ch)
    {
        auto n = doc.nodes[ch];
        if (!conditionsPass(n.attrs))
            return; // failing test: the element is absent from the document

        // The whole subtree of reference material or display="none"
        // is skipped for painting.
        if (isNonRendering(n.name) || n.attrs.get("display", "") == "none")
        {
            walkSkip(ch);
            return;
        }

        // Filtered paint (§15): the offscreen pass fires ahead of the
        // ordinary dispatch - the filter applies to the whole element,
        // leaf, container, or <use> instance alike. clipMode skips it:
        // clipPath children contribute geometry only, and filters are
        // no part of that reading (§14.3).
        if (!clipMode && "filter" in n.attrs)
            if (filteredElement(ch))
                return;

        paintSubtree(ch);
    }

    // Paint one element and its subtree through the ordinary dispatch.
    void paintSubtree(size_t ch)
    {
        auto n = doc.nodes[ch];
        if (n.name == "use")
        {
            useElement(ch);
            return;
        }
        if (n.name == "switch")
        {
            switchElement(ch);
            return;
        }

        element(n.name, n.attrs);
        walk(ch);
        closeElement(n.name);
    }

    // Filtered paint (§15.1): render the element's subtree into an
    // offscreen scratch, run the <filter>'s primitive chain over that
    // raster, and blend the result back. The offscreen convention
    // matches maskedPaint: a full-canvas buffer, semantically bounded
    // by the filter effects region (§15.5).
    //
    // Returns true when the element's paint was consumed - including
    // when the filter resolves to nothing. A broken reference and a
    // chain that ends up with no executed primitive both yield
    // transparent black and the element disappears entirely (filters-
    // felem-01-b pins this for dangling references, empty filters, and
    // an empty filter with a custom region alike).
    bool filteredElement(size_t ch)
    {
        immutable v = strip(doc.nodes[ch].attrs.get("filter", ""));
        if (v.empty || equalCase(v, "none"))
            return false; // none / invalid value: ordinary painting

        string id;
        Color fb;
        bool hasFb;
        if (!urlPaint(v, id, fb, hasFb))
            return false; // not a funciri: invalid attribute, ignored

        immutable target = doc.byId(id);
        if (target == Document.unknown || doc.nodes[target].name != "filter")
            return true; // broken reference: the element is not rendered

        if (filterDepth >= 4)
            return false; // cycle/depth cap: paint unfiltered

        auto f = makeFilter(doc, target);

        // The element's CTM for region maths: the filter region and the
        // objectBoundingBox basis ride the same matrix that paints the
        // subtree - including the element's own transform. The scratch
        // canvas, however, starts from the plain parent CTM: paintSubtree
        // replays this element's own attributes too, and its style
        // machinery applies the transform attribute once. Double-seeding
        // it here would slide SourceGraphic out of its own region (the
        // filtered <use> in filters-conv-05-f).
        Matrix ctm = canvas.matrix;
        if (auto t = "transform" in doc.nodes[ch].attrs)
            transformSVG(ctm, *t);

        // Render the subtree into the scratch, tracking the painted
        // geometry's bbox (the objectBoundingBox basis).
        auto scratch = Bitmap(Bitmap.Config.ARGB_8888, bmp.width, bmp.height);
        scratch.eraseColor(Color(0));
        auto oc = new Canvas(scratch);
        oc.matrix = canvas.matrix;

        auto oldCanvas = canvas;
        auto oldBmp = bmp;
        immutable oldTrack = bboxTrack;
        immutable oldAccum = bboxAccum;
        FRect local; // this filter's own geometry union
        canvas = oc;
        bmp = scratch;
        bboxTrack = true;
        bboxAccum = FRect(0, 0, 0, 0);
        ++filterDepth;
        scope (exit)
        {
            canvas = oldCanvas;
            bmp = oldBmp;
            bboxTrack = oldTrack;
            bboxAccum = oldTrack ? unionBox(oldAccum, bboxAccum) : oldAccum;
            --filterDepth;
        }
        paintSubtree(ch);
        local = bboxAccum; // (kept for clarity: `local` = this subtree's bbox)

        // The objectBoundingBox basis in device space (corner AABB - the
        // same approximation rotated content accepts from the marker
        // viewport clip). A degenerate geometry bbox makes every
        // objectBoundingBox computation zero-sized, and a zero-width or
        // -height region disables rendering (§15.5) - a filtered stroked
        // line with a zero-area bbox vanishes exactly as the browsers'
        // references show.
        auto src = rasterFrom(scratch, f.linearRGB);
        IBox4 basis;
        if (f.objBB)
        {
            if (local.width <= 0 || local.height <= 0)
                return true;
            basis = bboxToDevice(local, ctm);
        }
        IBox4 region = lengthBox(f.x, f.y, f.width, f.height, f.objBB, basis, ctm);
        if (region.empty)
            return true; // empty effects region: nothing renders (§15.5)

        // §15.5: every offscreen is the intersection with the effects
        // region - so the source enters the chain region-clipped, and
        // primitives that spread (blur) see transparent black beyond it.
        src.clipTo(region);

        auto res = runChain(f, src, region, basis, ctm, doc.nodes[ch].attrs, local);
        res.clipTo(region);
        // Blend back into the real destination: `bmp` still names the
        // scratch here, so point it at the pre-offscreen bitmap first
        // (the scope(exit) restore below then becomes a no-op).
        bmp = oldBmp;
        blendPM(bitmapFrom(res, f.linearRGB));
        return true;
    }

    // Run the primitive chain (§15.3). Inputs resolve by name - the
    // built-ins plus earlier `result`s - and a primitive's implicit
    // input is the previous primitive's output (SourceGraphic before
    // the first one). Unrecognised primitives are ignored (§15.1); a
    // chain that ends up executing nothing yields transparent black.
    Raster runChain(in FilterSpec f, Raster src, in IBox4 region, in IBox4 basis,
                    in Matrix ctm, in string[string] a, in FRect basisUser)
    {
        immutable clut = srgbDecodeLUT(); // flood colors join the working space

        Raster sa = Raster(src.w, src.h); // SourceAlpha: coverage as black (§15.3)
        foreach (i; 0 .. sa.px.length / 4)
            sa.px[i * 4 + 3] = src.px[i * 4 + 3];

        Raster[string] named;
        named["SourceGraphic"] = src;
        named["SourceAlpha"] = sa;
        Raster last = src; // the implicit input chain
        // feTile §15.23 replicates the *input image's* primitive
        // subregion, so the box travels alongside the raster.
        IBox4 lastSub = region;
        IBox4[string] namedSub;
        Raster res = Raster(src.w, src.h); // transparent unless a primitive writes it

        // Lazy inputs: snapshotting the backdrop or painting the
        // element's paint servers is pure cost for simple chains.
        Raster bg, fillP, strokeP;
        bool haveBg = false, haveFill = false, haveStroke = false;

        void initBg()
        {
            if (haveBg)
                return;
            bg = rasterFrom(bmp, f.linearRGB); // live canvas = the backdrop
            bg.clipTo(region); // BackgroundImage is "under the filter
            haveBg = true;    // region" (§15.3)
        }

        Raster input(in string[string] at, string key)
        {
            if (auto p = key in at)
            {
                immutable nm = strip(*p);
                if (auto q = nm in named)
                    return *q;
                if (nm == "BackgroundImage")
                {
                    initBg();
                    return bg;
                }
                if (nm == "BackgroundAlpha")
                {
                    initBg();
                    Raster ba = Raster(bg.w, bg.h);
                    foreach (i; 0 .. ba.px.length / 4)
                        ba.px[i * 4 + 3] = bg.px[i * 4 + 3];
                    return ba;
                }
                if (nm == "FillPaint" || nm == "StrokePaint")
                {
                    immutable isFill = nm == "FillPaint";
                    if (isFill && !haveFill)
                    {
                        fillP = paintServerRaster(true, f, region, ctm, a, basisUser);
                        haveFill = true;
                    }
                    else if (!isFill && !haveStroke)
                    {
                        strokeP = paintServerRaster(false, f, region, ctm, a, basisUser);
                        haveStroke = true;
                    }
                    return isFill ? fillP : strokeP;
                }
                return Raster(src.w, src.h); // dangling result name: transparent
            }
            return last;
        }

        // A primitive <number>/<coordinate>: plain numbers, no units.
        float num(in string[string] at, string key, float def)
        {
            if (auto p = key in at)
                try
                    return to!float(strip(*p));
                catch (ConvException)
                    return def; // invalid: the attribute is ignored
            return def;
        }

        // The currentColor base for flood-color/lighting-color (§15.8.5):
        // the primitive's own parseable `color` attribute when it carries
        // one, else the value inherited at the <filter> element.
        Color primColor(in Element el)
        {
            if (auto p = "color" in el.attrs)
            {
                Color v;
                if (parsePaint(*p, v))
                    return v;
            }
            return f.color;
        }

        // primitiveUnits scaling: objectBoundingBox numbers are fractions
        // of the bbox's device extent; userSpaceOnUse (the default)
        // numbers are user units, riding the CTM's axis scales into raster
        // pixels. Rotated CTMs take magnitudes only - no test pins the
        // direction of an offset or blur along a rotated axis.
        immutable sx = sqrt(ctm[0][0] ^^ 2 + ctm[1][0] ^^ 2);
        immutable sy = sqrt(ctm[0][1] ^^ 2 + ctm[1][1] ^^ 2);
        float scaleX(float v) { return f.primsObjBB ? v * (basis.x1 - basis.x0) : v * sx; }
        float scaleY(float v) { return f.primsObjBB ? v * (basis.y1 - basis.y0) : v * sy; }

        foreach (pi; f.prims)
        {
            immutable e = doc.nodes[pi];
            bool ran = false; // did this primitive contribute?
            // The §15.7.3 hard-clip box; feImage overrides it with its
            // placement rect (which doubles as its subregion).
            IBox4 sub = intersect(primSubregion(e, f, region, basis, ctm), region);
            switch (e.name)
            {
            case "feOffset":
            {
                Raster o;
                offsetShift(o, input(e.attrs, "in"),
                    to!int(round(scaleX(num(e.attrs, "dx", 0)))),
                    to!int(round(scaleY(num(e.attrs, "dy", 0)))));
                res = o;
                ran = true;
                break;
            }

            case "feFlood":
            {
                Color fc; // initial flood-color is black (§15.6.12)
                if (auto p = "flood-color" in e.attrs)
                {
                    Color v;
                    if (parsePaint(*p, v))
                        fc = v;
                    else if (equalCase(strip(*p), "currentColor"))
                        fc = primColor(e);
                    // invalid value: the initial black stands (§15.1)
                }
                float fo = 1.0f;
                if (auto p = "flood-opacity" in e.attrs)
                    try
                        fo = clamp(to!float(strip(*p)), 0.0f, 1.0f);
                    catch (ConvException)
                        {}
                float[4] col;
                col[0] = f.linearRGB ? clut[fc.r] : fc.r / 255.0f;
                col[1] = f.linearRGB ? clut[fc.g] : fc.g / 255.0f;
                col[2] = f.linearRGB ? clut[fc.b] : fc.b / 255.0f;
                col[3] = fc.a / 255.0f * fo; // alpha is linear (§15.2)
                col[0 .. 3] *= col[3]; // store premultiplied
                Raster o = Raster(src.w, src.h);
                flood(o, intersect(primSubregion(e, f, region, basis, ctm), region), col);
                res = o;
                ran = true;
                break;
            }

            case "feComposite":
            {
                CompOp op = CompOp.over;
                if (auto p = "operator" in e.attrs)
                    switch (toLower(strip(*p)))
                    {
                    case "in": op = CompOp.inOp; break;
                    case "out": op = CompOp.outOp; break;
                    case "atop": op = CompOp.atop; break;
                    case "xor": op = CompOp.xorOp; break;
                    case "arithmetic": op = CompOp.arithmetic; break;
                    default: break; // invalid: the initial over
                    }
                float[4] k = [num(e.attrs, "k1", 0), num(e.attrs, "k2", 0),
                              num(e.attrs, "k3", 0), num(e.attrs, "k4", 0)];
                Raster d = Raster(src.w, src.h);
                composite(d, input(e.attrs, "in"), input(e.attrs, "in2"), op, k);
                res = d;
                ran = true;
                break;
            }

            case "feBlend":
            {
                BlendMode mode = BlendMode.normal;
                if (auto p = "mode" in e.attrs)
                    switch (toLower(strip(*p)))
                    {
                    case "multiply": mode = BlendMode.multiply; break;
                    case "screen": mode = BlendMode.screen; break;
                    case "darken": mode = BlendMode.darken; break;
                    case "lighten": mode = BlendMode.lighten; break;
                    default: break; // normal, and unknown modes per §15.4
                    }
                Raster d = Raster(src.w, src.h);
                blend(d, input(e.attrs, "in"), input(e.attrs, "in2"), mode);
                res = d;
                ran = true;
                break;
            }

            case "feMerge":
            {
                Raster acc = Raster(src.w, src.h);
                foreach (cn; e.children)
                {
                    immutable ce = doc.nodes[cn];
                    if (ce.name.empty)
                        continue; // text noise inside the merge list
                    mergeOver(acc, input(ce.attrs, "in"));
                }
                res = acc;
                ran = true;
                break;
            }

            case "feGaussianBlur":
            {
                // stdDeviation is "s [t]"; a lone value blurs both axes.
                float s1 = 0, s2 = 0;
                size_t seen = 0;
                if (auto p = "stdDeviation" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                        if (seen < 2)
                            try
                            {
                                if (seen == 0) s1 = to!float(t);
                                else s2 = to!float(t);
                            }
                            catch (ConvException)
                                {}
                        ++seen;
                if (seen == 1)
                    s2 = s1;
                Raster o;
                gaussianBlur(o, input(e.attrs, "in"), scaleX(s1), scaleY(s2));
                res = o;
                ran = true;
                break;
            }

            case "feColorMatrix":
            {
                // type defaults to "matrix"; values is a whitespace-or-comma
                // separated number list (§15.6.4/15.6.5).
                string type = "matrix";
                if (auto p = "type" in e.attrs)
                    type = toLower(strip(*p));
                float[] vals;
                if (auto p = "values" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                        try
                            vals ~= to!float(t);
                        catch (ConvException)
                            {}
                Raster o;
                colorMatrix(o, input(e.attrs, "in"), cmMatrix(type, vals));
                res = o;
                ran = true;
                break;
            }

            case "feComponentTransfer":
            {
                // The feFuncR/G/B/A children name one channel each; absent
                // channels stay identity (§15.11).
                TransferFunc[4] fn;
                foreach (cn; e.children)
                {
                    immutable ce = doc.nodes[cn];
                    immutable ci = ce.name == "feFuncR" ? 0 : ce.name == "feFuncG" ? 1
                        : ce.name == "feFuncB" ? 2 : ce.name == "feFuncA" ? 3 : -1;
                    if (ci < 0)
                        continue;
                    auto fp = &fn[ci];
                    if (auto p = "type" in ce.attrs)
                    {
                        immutable t = toLower(strip(*p));
                        if (t == "table")
                            fp.kind = TransferFunc.Kind.table;
                        else if (t == "discrete")
                            fp.kind = TransferFunc.Kind.discrete;
                        else if (t == "linear")
                            fp.kind = TransferFunc.Kind.linear;
                        else if (t == "gamma")
                            fp.kind = TransferFunc.Kind.gamma;
                        // anything else, "identity" included: identity
                    }
                    if (auto p = "tableValues" in ce.attrs)
                        foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                            try
                                fp.table ~= to!float(t);
                            catch (ConvException)
                                {}
                    fp.slope = num(ce.attrs, "slope", 1.0f);
                    fp.intercept = num(ce.attrs, "intercept", 0.0f);
                    fp.amplitude = num(ce.attrs, "amplitude", 1.0f);
                    fp.exponent = num(ce.attrs, "exponent", 1.0f);
                    fp.offset = num(ce.attrs, "offset", 0.0f);
                }
                Raster o;
                componentTransfer(o, input(e.attrs, "in"), fn);
                res = o;
                ran = true;
                break;
            }

            case "feConvolveMatrix":
            {
                // order is "<x> [<y>]" of positive integers, default 3;
                // kernelMatrix must hold exactly orderX*orderY numbers.
                // A broken shape (bad count, divisor 0, out-of-range
                // target) leaves the primitive producing transparent
                // black rather than paint.
                int[2] ord = [3, 3]; // [orderX, orderY]
                size_t seen = 0;
                bool bad = false;
                if (auto p = "order" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                    {
                        if (seen < 2)
                        {
                            try
                                ord[cast(int) seen] = to!int(strip(t));
                            catch (ConvException)
                                bad = true;
                            if (ord[cast(int) seen] < 1)
                                bad = true;
                        }
                        ++seen;
                    }
                if (seen == 1)
                    ord[1] = ord[0];

                float[] k;
                if (auto p = "kernelMatrix" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                        try
                            k ~= to!float(t);
                        catch (ConvException)
                            bad = true;
                if (k.length != ord[0] * ord[1])
                    bad = true;

                // divisor defaults to the kernel sum, 1 when that is 0;
                // an explicit 0 is an error.
                float div = 0.0f;
                if (auto p = "divisor" in e.attrs)
                {
                    div = num(e.attrs, "divisor", 0.0f);
                    if (div == 0.0f)
                        bad = true;
                }
                else
                {
                    foreach (v; k)
                        div += v;
                    if (div == 0.0f)
                        div = 1.0f;
                }

                immutable tx = to!int(num(e.attrs, "targetX", ord[0] / 2.0f));
                immutable ty = to!int(num(e.attrs, "targetY", ord[1] / 2.0f));
                if (tx < 0 || tx >= ord[0] || ty < 0 || ty >= ord[1])
                    bad = true;

                ConvEdge em = ConvEdge.duplicate;
                if (auto p = "edgeMode" in e.attrs)
                {
                    immutable v = toLower(strip(*p));
                    if (v == "wrap")
                        em = ConvEdge.wrap;
                    else if (v == "none")
                        em = ConvEdge.none;
                }
                bool pa = false;
                if (auto p = "preserveAlpha" in e.attrs)
                    pa = strip(*p) == "true" || strip(*p) == "1";

                if (!bad)
                {
                    Raster o;
                    convolve(o, input(e.attrs, "in"), k, ord[0], ord[1], tx, ty,
                        div, num(e.attrs, "bias", 0.0f), em, pa);
                    res = o;
                }
                else
                    res = Raster(src.w, src.h); // disabled: transparent
                ran = true;
                break;
            }

            case "feTile":
            {
                // The tiling anchors on the input's subregion: tile
                // (i,j) top/left at its origin + (i·w, j·h) (§15.23).
                // The target is feTile's own subregion, clipped below.
                IBox4 isub = lastSub;
                if (auto p = "in" in e.attrs)
                {
                    immutable nm = strip(*p);
                    if (auto q = nm in namedSub)
                        isub = *q;
                    else
                        isub = region; // SourceAlpha & friends span the region
                }
                Raster o;
                tileRaster(o, input(e.attrs, "in"), isub.x0, isub.y0,
                    isub.x1 - isub.x0, isub.y1 - isub.y0);
                res = o;
                ran = true;
                break;
            }

            case "feImage":
            {
                // The placement rect is the image's fit viewport even
                // where the filter region clips part of it away; the
                // subregion (which the rect doubles as) only enters as
                // the output clip. Missing sides default to
                // 0%/0%/100%/100% of the filter region (§15.18).
                const fr = feImageRect(e, f, region, basis, ctm);
                sub = intersect(IBox4(cast(int) floor(fr.left), cast(int) floor(fr.top),
                    cast(int) ceil(fr.right), cast(int) ceil(fr.bottom)), region);
                Raster o = Raster(src.w, src.h);
                immutable href = e.attrs.get("href", e.attrs.get("xlink:href", ""));
                if (auto path = resolveHref(docBase, href))
                {
                    auto img = loadSVGImage(path);
                    immutable nw = to!float(img.width), nh = to!float(img.height);
                    if (img.config != Bitmap.Config.NoConfig && nw > 0 && nh > 0
                        && !sub.empty)
                    {
                        // preserveAspectRatio works exactly as on
                        // 'image': the natural pixel square fits the
                        // rect-viewport (fit lands in device units).
                        float[4] vb = [0.0f, 0.0f, nw, nh];
                        immutable fit = viewFit(vb, fr.right - fr.left,
                            fr.bottom - fr.top,
                            parsePAR(e.attrs.get("preserveAspectRatio", "")));
                        placeImage(o, bitmapRaster(img, f.linearRGB), fr.left,
                            fr.top, fit[0][0], fit[1][1], fit[0][2], fit[1][2]);
                    }
                }
                res = o;
                ran = true;
                break;
            }

            case "feTurbulence":
            {
                // §15.19/§15.24: baseFrequency "<number> [<number>]"
                // (default 0; negative is an error), numOctaves integer
                // (default 1), seed (default 0, truncated toward zero
                // on the way into the PRNG), type (default turbulence),
                // stitchTiles (default noStitch). The noise has no
                // input at all and fills the primitive subregion.
                float[2] freq = [0.0f, 0.0f];
                size_t seen = 0;
                bool bad = false;
                if (auto p = "baseFrequency" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                    {
                        if (seen < 2)
                        {
                            try
                                freq[cast(int) seen] = to!float(t);
                            catch (ConvException)
                                bad = true;
                            if (freq[cast(int) seen] < 0.0f)
                                bad = true; // negative frequency: error
                        }
                        ++seen;
                    }
                if (seen == 1)
                    freq[1] = freq[0];

                int oct = 1;
                if (auto p = "numOctaves" in e.attrs)
                {
                    try
                        oct = to!int(strip(*p));
                    catch (ConvException)
                        oct = 1; // invalid attribute value: ignored
                    if (oct < 0)
                        bad = true;
                }

                // baseFrequency lives in the primitiveUnits space, so
                // the per-pixel lattice step is freq/scale there: for
                // userSpaceOnUse the raster's absolute device index
                // space over the CTM's axis scales (the absolute
                // anchoring the suite's references show), for
                // objectBoundingBox normalized fractions of the bbox.
                double ax = 0.0, ay = 0.0, x0 = 0.0, y0 = 0.0;
                if (f.primsObjBB)
                {
                    immutable bw = basis.x1 - basis.x0, bh = basis.y1 - basis.y0;
                    if (bw < 1 || bh < 1)
                        bad = true;
                    else
                    {
                        ax = freq[0] / bw;
                        ay = freq[1] / bh;
                        x0 = -cast(double) basis.x0;
                        y0 = -cast(double) basis.y0;
                    }
                }
                else
                {
                    if (sx > 0.0f)
                        ax = freq[0] / sx;
                    if (sy > 0.0f)
                        ay = freq[1] / sy;
                }

                if (!bad && !sub.empty)
                {
                    immutable seed = clamp(num(e.attrs, "seed", 0.0f),
                        -2_147_483_647.0f, 2_147_483_647.0f);
                    Raster o = Raster(src.w, src.h);
                    turbulenceFill(o, sub, cast(long) seed, ax, ay, oct,
                        strip(e.attrs.get("type", "")) == "fractalNoise",
                        strip(e.attrs.get("stitchTiles", "")) == "stitch",
                        x0, y0);
                    res = o;
                }
                else
                    res = Raster(src.w, src.h); // disabled: transparent
                ran = true;
                break;
            }

            case "feDisplacementMap":
            {
                // §15.15: scale is a plain number in primitiveUnits;
                // the selectors are R/G/B/A and default to A - a value
                // that isn't one of those keeps the default.
                int xc = 3, yc = 3;
                if (auto p = "xChannelSelector" in e.attrs)
                {
                    immutable v = toUpper(strip(*p));
                    if (v == "R")
                        xc = 0;
                    else if (v == "G")
                        xc = 1;
                    else if (v == "B")
                        xc = 2;
                }
                if (auto p = "yChannelSelector" in e.attrs)
                {
                    immutable v = toUpper(strip(*p));
                    if (v == "R")
                        yc = 0;
                    else if (v == "G")
                        yc = 1;
                    else if (v == "B")
                        yc = 2;
                }
                const scX = scaleX(num(e.attrs, "scale", 0.0f));
                const scY = scaleY(num(e.attrs, "scale", 0.0f));
                Raster o;
                displaceMap(o, input(e.attrs, "in"), input(e.attrs, "in2"),
                    scX, scY, xc, yc);
                res = o;
                ran = true;
                break;
            }

            case "feMorphology":
            {
                // §15.20: operator (default erode) and radius
                // "<number> [<number>]" (default 0 - which disables the
                // primitive to transparent black; negative is an
                // error). The whole-pixel window takes the ceiling of
                // the radius.
                float[2] rad = [0.0f, 0.0f];
                size_t seen = 0;
                bool bad = false;
                if (auto p = "radius" in e.attrs)
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                    {
                        if (seen < 2)
                        {
                            try
                                rad[cast(int) seen] = to!float(t);
                            catch (ConvException)
                                bad = true;
                            if (rad[cast(int) seen] < 0.0f)
                                bad = true;
                        }
                        ++seen;
                    }
                if (seen == 1)
                    rad[1] = rad[0];

                if (!bad)
                {
                    Raster o;
                    morphology(o, input(e.attrs, "in"), to!int(ceil(rad[0])),
                        to!int(ceil(rad[1])),
                        strip(e.attrs.get("operator", "")) == "dilate");
                    res = o;
                }
                else
                    res = Raster(src.w, src.h); // disabled: transparent
                ran = true;
                break;
            }

            case "feDiffuseLighting":
            case "feSpecularLighting":
            {
                // §15.14/§15.22: the input's alpha is a height map, and
                // the light is the primitive's single light-source child
                // (§15.8.2-4). surfaceScale is a bare number that never
                // rides the primitiveUnits scale - the objectBoundingBox/
                // userSpaceOnUse twins of filters-light-03-f both say 5
                // and render identically. Light *positions* do ride it:
                // 03-f's oBB z fractions are exactly z / sqrt((w²+h²)/2),
                // the root-mean-square of the bbox sides.
                const bool spec = e.name == "feSpecularLighting";

                Light lit;
                foreach (cn; e.children)
                {
                    immutable lc = doc.nodes[cn];
                    if (lc.name == "feDistantLight")
                    {
                        lit.kind = 0;
                        lit.azimuth = num(lc.attrs, "azimuth", 0.0f);
                        lit.elevation = num(lc.attrs, "elevation", 0.0f);
                        break;
                    }
                    if (lc.name == "fePointLight")
                    {
                        lit.kind = 1;
                        lit.x = num(lc.attrs, "x", 0.0f);
                        lit.y = num(lc.attrs, "y", 0.0f);
                        lit.z = num(lc.attrs, "z", 0.0f);
                        break;
                    }
                    if (lc.name == "feSpotLight")
                    {
                        lit.kind = 2;
                        lit.x = num(lc.attrs, "x", 0.0f);
                        lit.y = num(lc.attrs, "y", 0.0f);
                        lit.z = num(lc.attrs, "z", 0.0f);
                        lit.pointsAtX = num(lc.attrs, "pointsAtX", 0.0f);
                        lit.pointsAtY = num(lc.attrs, "pointsAtY", 0.0f);
                        lit.pointsAtZ = num(lc.attrs, "pointsAtZ", 0.0f);
                        lit.specularExponent = num(lc.attrs, "specularExponent", 1.0f);
                        if (auto p = "limitingConeAngle" in lc.attrs)
                        {
                            try
                                lit.limitingConeAngle = to!float(strip(*p));
                            catch (ConvException)
                                {} // invalid: no limit, like the attribute being absent
                        }
                        break;
                    }
                }

                if (lit.kind) // distant lights carry no position
                {
                    FPoint toDev(float vx, float vy)
                    {
                        if (f.primsObjBB && !basis.empty)
                            return FPoint(basis.x0 + vx * (basis.x1 - basis.x0),
                                          basis.y0 + vy * (basis.y1 - basis.y0));
                        FPoint[1] p = [FPoint(vx, vy)];
                        ctm.mapPoints(p[]);
                        return p[0];
                    }
                    float scaleZ(float v)
                    {
                        if (f.primsObjBB && !basis.empty)
                        {
                            immutable float bw = basis.x1 - basis.x0, bh = basis.y1 - basis.y0;
                            return v * sqrt((bw * bw + bh * bh) / 2.0f);
                        }
                        return v * sqrt(sx * sy); // §15.8.3: one z unit = one x/y unit
                    }

                    immutable p = toDev(lit.x, lit.y);
                    lit.x = p.x;
                    lit.y = p.y;
                    lit.z = scaleZ(lit.z);
                    if (lit.kind == 2)
                    {
                        immutable q = toDev(lit.pointsAtX, lit.pointsAtY);
                        lit.pointsAtX = q.x;
                        lit.pointsAtY = q.y;
                        lit.pointsAtZ = scaleZ(lit.pointsAtZ);
                    }
                }

                // kernelUnitLength (§15.14): the default is one pixel of
                // the source image and does not ride primitiveUnits; the
                // spec-parsed pair does, and zero or negative is an error
                // that leaves the default standing.
                int kx = 1, ky = 1;
                if (auto p = "kernelUnitLength" in e.attrs)
                {
                    float[2] v = [1.0f, 1.0f];
                    size_t seen = 0;
                    bool bad = false;
                    foreach (t; splitter(replace(strip(*p), ",", " "), " "))
                    {
                        if (seen < 2)
                        {
                            try
                                v[cast(int) seen] = to!float(t);
                            catch (ConvException)
                                bad = true;
                            if (v[cast(int) seen] <= 0.0f)
                                bad = true;
                        }
                        ++seen;
                    }
                    if (seen == 1)
                        v[1] = v[0];
                    if (!bad)
                    {
                        kx = max(1, to!int(round(scaleX(v[0]))));
                        ky = max(1, to!int(round(scaleY(v[1]))));
                    }
                }

                Color lcol = Color.White; // lighting-color initial (§15.8.5)
                if (auto p = "lighting-color" in e.attrs)
                {
                    Color v;
                    if (parsePaint(*p, v))
                        lcol = v;
                    else if (equalCase(strip(*p), "currentColor"))
                        lcol = primColor(e);
                    // invalid: the initial white stands (§15.1)
                }
                float[3] lrgb;
                lrgb[0] = f.linearRGB ? clut[lcol.r] : lcol.r / 255.0f;
                lrgb[1] = f.linearRGB ? clut[lcol.g] : lcol.g / 255.0f;
                lrgb[2] = f.linearRGB ? clut[lcol.b] : lcol.b / 255.0f;

                Raster o;
                // surfaceScale is a bare number: the oBB/userSpace twins of
                // filters-light-03-f both carry surfaceScale="5" and render
                // identically, so it never rides the primitiveUnits scale -
                // and 02-f at scale(4) shows it never rides the CTM either.
                lighting(o, input(e.attrs, "in"), lit, spec,
                    num(e.attrs, "surfaceScale", 1.0f),
                    num(e.attrs, spec ? "specularConstant" : "diffuseConstant", 1.0f),
                    num(e.attrs, "specularExponent", 1.0f), lrgb, kx, ky, sub);
                res = o;
                ran = true;
                break;
            }

            default:
                break; // unrecognised primitive: ignored (§15.1)
            }

            // Only a primitive that ran feeds the implicit input chain and
            // claims a `result` name. The subregion hard-clips every result
            // (§15.7.3), always within the filter region.
            if (ran)
            {
                res.clipTo(sub);
                last = res;
                lastSub = sub;
                if (auto r = "result" in e.attrs)
                {
                    named[strip(*r)] = res;
                    namedSub[strip(*r)] = sub;
                }
            }
        }
        return res;
    }

    // FillPaint/StrokePaint inputs (§15.3): the referencing element's
    // paint server as a continuous-tone image - literally painting the
    // region rect with that paint under the element's CTM, so gradients,
    // patterns, and plain colors resolve exactly as they would when the
    // element itself paints.
    Raster paintServerRaster(bool isFill, in FilterSpec f, in IBox4 region,
                             in Matrix ctm, in string[string] a, in FRect basisUser)
    {
        // A singular CTM maps nothing anywhere: transparent input.
        immutable det = ctm[0][0] * ctm[1][1] - ctm[0][1] * ctm[1][0];
        if (det == 0.0f)
            return Raster(cast(int) bmp.width, cast(int) bmp.height);

        const s = pushStyle(a);
        scope (exit) popStyle();
        immutable op = clamp(s.opacity, 0.0f, 1.0f)
            * (isFill ? clamp(s.fillOpacity, 0.0f, 1.0f) : clamp(s.strokeOpacity, 0.0f, 1.0f));
        auto paint = resolvePaint(isFill, s, op, basisUser);

        // A user-space rect covering the region: the region's corners
        // map back through the inverse CTM, so the quad stays a full
        // region cover under rotation.
        auto inv = ctm.inverted;
        FPoint[4] pts = [FPoint(region.x0, region.y0), FPoint(region.x1, region.y0),
                         FPoint(region.x0, region.y1), FPoint(region.x1, region.y1)];
        inv.mapPoints(pts[]);
        immutable rx0 = min(min(pts[0].x, pts[1].x), min(pts[2].x, pts[3].x));
        immutable rx1 = max(max(pts[0].x, pts[1].x), max(pts[2].x, pts[3].x));
        immutable ry0 = min(min(pts[0].y, pts[1].y), min(pts[2].y, pts[3].y));
        immutable ry1 = max(max(pts[0].y, pts[1].y), max(pts[2].y, pts[3].y));

        Path rp;
        rp.reset();
        rp.moveTo(FPoint(rx0, ry0));
        rp.lineTo(FPoint(rx1, ry0));
        rp.lineTo(FPoint(rx1, ry1));
        rp.lineTo(FPoint(rx0, ry1));
        rp.close();

        auto pb = Bitmap(Bitmap.Config.ARGB_8888, bmp.width, bmp.height);
        pb.eraseColor(Color(0));
        Canvas pc = new Canvas(pb);
        pc.matrix = ctm;
        pc.drawPath(rp, paint);
        auto r = rasterFrom(pb, f.linearRGB);
        r.clipTo(region);
        return r;
    }

    // Filter primitive subregion (§15.1): x/y/width/height restrict the
    // primitive, defaulting to the filter's own x/y/width/height - read
    // in primitiveUnits, so when the units differ it is NOT the same box
    // as the effects region. A zero-size subregion makes the primitive's
    // result transparent black.
    IBox4 primSubregion(in Element e, in FilterSpec f, in IBox4 region,
                        in IBox4 basis, in Matrix ctm)
    {
        if ("x" !in e.attrs && "y" !in e.attrs
            && "width" !in e.attrs && "height" !in e.attrs)
            return region; // §15.7.3: the default subregion IS the filter region

        string g(string k, string def)
        {
            if (auto p = k in e.attrs)
                return *p;
            return def;
        }
        return lengthBox(g("x", ""), g("y", ""), g("width", ""),
                         g("height", ""), f.primsObjBB, basis, ctm);
    }

    // A box of four <length>s in device pixels: objectBoundingBox
    // fractions of the basis box, or userSpaceOnUse lengths riding the
    // element's CTM. Pixels even partly covered count (§15.5's
    // "any pixels which even partly intersect"), hence floor/ceil;
    // invalid lengths fall back to the §15.1 attribute defaults, and a
    // zero or negative width/height disables the box.
    IBox4 lengthBox(string xs, string ys, string ws, string hs,
                    bool objBB, in IBox4 basis, in Matrix ctm)
    {
        float x, y, w, h;
        if (objBB)
        {
            if (!bbFraction(xs, x)) x = -0.10f;
            if (!bbFraction(ys, y)) y = -0.10f;
            if (!bbFraction(ws, w)) w = 1.20f;
            if (!bbFraction(hs, h)) h = 1.20f;
            if (w <= 0 || h <= 0 || basis.empty)
                return IBox4();
            immutable bw = basis.x1 - basis.x0, bh = basis.y1 - basis.y0;
            return IBox4(cast(int) floor(basis.x0 + x * bw),
                         cast(int) floor(basis.y0 + y * bh),
                         cast(int) ceil(basis.x0 + (x + w) * bw),
                         cast(int) ceil(basis.y0 + (y + h) * bh));
        }

        string[string] la = ["x": xs, "y": ys, "width": ws, "height": hs];
        LengthCtx lc = lengthCtx();
        x = convLen(la, "x", -0.10f * lc.vpW, lc, RefAxis.width);
        y = convLen(la, "y", -0.10f * lc.vpH, lc, RefAxis.height);
        w = convLen(la, "width", 1.20f * lc.vpW, lc, RefAxis.width);
        h = convLen(la, "height", 1.20f * lc.vpH, lc, RefAxis.height);
        if (w <= 0 || h <= 0)
            return IBox4();
        return bboxToDevice(FRect(x, y, x + w, y + h), ctm);
    }

    // feImage's placement rect (§15.18, continuous device coords):
    // specified x/y/width/height are primitiveUnits lengths like any
    // primitive subregion (percentages against the viewport in
    // userSpaceOnUse, bbox fractions in objectBoundingBox), but an
    // absent side defaults to 0%/100% *of the filter region* - not the
    // §15.1 -10%/120% defaults the suite's other primitives get.
    FRect feImageRect(in Element e, in FilterSpec f, in IBox4 region,
                      in IBox4 basis, in Matrix ctm)
    {
        float x, y, w, h; // device pixels

        if (f.primsObjBB && !basis.empty)
        {
            immutable bw = basis.x1 - basis.x0, bh = basis.y1 - basis.y0;
            float v;
            x = ("x" in e.attrs && bbFraction(*("x" in e.attrs), v))
                ? basis.x0 + v * bw : cast(float) region.x0;
            y = ("y" in e.attrs && bbFraction(*("y" in e.attrs), v))
                ? basis.y0 + v * bh : cast(float) region.y0;
            w = ("width" in e.attrs && bbFraction(*("width" in e.attrs), v))
                ? v * bw : cast(float) (region.x1 - region.x0);
            h = ("height" in e.attrs && bbFraction(*("height" in e.attrs), v))
                ? v * bh : cast(float) (region.y1 - region.y0);
        }
        else
        {
            auto lc = lengthCtx();
            immutable ux = convLen(e.attrs, "x", 0.0f, lc, RefAxis.width);
            immutable uy = convLen(e.attrs, "y", 0.0f, lc, RefAxis.height);
            immutable uw = convLen(e.attrs, "width", 0.0f, lc, RefAxis.width);
            immutable uh = convLen(e.attrs, "height", 0.0f, lc, RefAxis.height);
            immutable mx0 = ctm[0][0] * ux + ctm[0][2], mx1 = ctm[0][0] * (ux + uw) + ctm[0][2];
            immutable my0 = ctm[1][1] * uy + ctm[1][2], my1 = ctm[1][1] * (uy + uh) + ctm[1][2];
            x = "x" in e.attrs ? min(mx0, mx1) : cast(float) region.x0;
            y = "y" in e.attrs ? min(my0, my1) : cast(float) region.y0;
            w = "width" in e.attrs ? fabs(mx1 - mx0) : cast(float) (region.x1 - region.x0);
            h = "height" in e.attrs ? fabs(my1 - my0) : cast(float) (region.y1 - region.y0);
        }

        if (w <= 0 || h <= 0)
            return FRect(0, 0);
        return FRect(x, y, x + w, y + h);
    }

    // A user-space rect into the raster's device box (corner AABB).
    IBox4 bboxToDevice(in FRect r, in Matrix ctm)
    {
        FPoint[4] pts = [FPoint(r.x, r.y), FPoint(r.x + r.width, r.y),
                         FPoint(r.x, r.y + r.height), FPoint(r.x + r.width, r.y + r.height)];
        ctm.mapPoints(pts[]);
        immutable x0 = min(min(pts[0].x, pts[1].x), min(pts[2].x, pts[3].x));
        immutable x1 = max(max(pts[0].x, pts[1].x), max(pts[2].x, pts[3].x));
        immutable y0 = min(min(pts[0].y, pts[1].y), min(pts[2].y, pts[3].y));
        immutable y1 = max(max(pts[0].y, pts[1].y), max(pts[2].y, pts[3].y));
        return IBox4(cast(int) floor(x0), cast(int) floor(y0),
                     cast(int) ceil(x1), cast(int) ceil(y1));
    }

    // Union of geometry boxes; empty boxes (zero area) absorb nothing.
    static FRect unionBox(FRect a, FRect b)
    {
        if (a.width <= 0 || a.height <= 0)
            return b;
        if (b.width <= 0 || b.height <= 0)
            return a;
        immutable x0 = min(a.x, b.x), y0 = min(a.y, b.y);
        immutable x1 = max(a.x + a.width, b.x + b.width);
        immutable y1 = max(a.y + a.height, b.y + b.height);
        return FRect(x0, y0, x1, y1); // FRect's ctor takes (left, top, right, bottom)
    }

    // <switch>: the first child element whose conditional processing tests
    // pass renders; every other child - passing or not - does not render.
    void switchElement(size_t idx)
    {
        foreach (ch; doc.nodes[idx].children)
        {
            if (doc.nodes[ch].name.empty || !conditionsPass(doc.nodes[ch].attrs))
                continue; // tested out: the search moves to the next child
            renderChild(ch);
            return;
        }
    }

    // Visit the children of arena node `idx` in document order.
    void walk(size_t idx)
    {
        foreach (ch; doc.nodes[idx].children)
        {
            auto n = doc.nodes[ch];
            if (n.name.empty) // a text node
            {
                if (inText)
                    textBuf ~= normalizeText(n.text);
                continue;
            }

            if (!inRoot)
            {
                // Everything before the first <svg> is inert; descend to
                // find it wherever it sits, then set the canvas up.
                if (ch == doc.root)
                {
                    inRoot = true;
                    setupRoot(n.attrs);
                }
                walk(ch);
                continue;
            }

            renderChild(ch);
        }
    }

    // Descend through a subtree that paints nothing. Text nodes inside
    // it still feed an open <text> run: text accumulation keys off
    // `inText` alone (as it did off the SAX onText callback), so e.g.
    // <text><g display="none">hi</g></text> keeps drawing "hi".
    void walkSkip(size_t idx)
    {
        foreach (ch; doc.nodes[idx].children)
        {
            auto n = doc.nodes[ch];
            if (n.name.empty)
            {
                if (inText)
                    textBuf ~= normalizeText(n.text);
            }
            else
                walkSkip(ch);
        }
    }
}

// Parses `source` and renders it into a fresh Bitmap.
// Render `source` to a fresh bitmap. `baseDir` is the source file's
// directory (trailing '/'): the base for relative <image> hrefs;
// empty = the process cwd.
Bitmap renderSVG(string source, float zoom = 1.0f, string baseDir = "")
{
    Renderer r;
    r.doc = parseSVG(source);
    r.docBase = baseDir;
    r.zoom = zoom;
    r.walk(0); // the document pseudo-root; inRoot latches at the <svg>

    // The device is composited premultiplied (blendPM), but an ARGB_8888
    // Bitmap - and any PNG saved from it - is straight-alpha by definition,
    // so convert on the way out. guip stores floor(c*(a+1)/256), making the
    // inverse round(p*256/(a+1)) clamped; a 0 and a 255 are identities.
    foreach (y; 0 .. r.bmp.height)
        foreach (ref px; r.bmp.getLine!PMColor(y))
            if (px.a && px.a != 255)
            {
                immutable s = px.a + 1;
                px.r = cast(ubyte) min(255, (px.r * 256 + s / 2) / s);
                px.g = cast(ubyte) min(255, (px.g * 256 + s / 2) / s);
                px.b = cast(ubyte) min(255, (px.b * 256 + s / 2) / s);
            }
    return r.bmp;
}

unittest
{
    // <length>: units, percentages and em/ex
    LengthCtx lc;
    lc.vpW = 480;
    lc.vpH = 360;
    lc.fontSize = 20;
    assert(parseLength("42", lc) == 42);
    assert(parseLength("42px", lc) == 42);
    assert(parseLength("1in", lc) == 72);
    assert(parseLength("72pt", lc) == 72);
    assert(parseLength("6pc", lc) == 72);
    assert(isClose(parseLength("2.54cm", lc), 72, 1e-3f));
    assert(isClose(parseLength("25.4mm", lc), 72, 1e-3f));
    assert(parseLength("2em", lc) == 40);
    assert(parseLength("1ex", lc) == 10);
    lc.pctRef = lc.vpW;
    assert(parseLength("50%", lc) == 240);
    assert(parseLength("100%", lc) == 480);

    string[string] a = ["width": "10%", "missing": "7"];
    assert(a.convLen("width", 0, lc, RefAxis.width) == 48);
    assert(a.convLen("height", 13, lc, RefAxis.height) == 13);
    // the normalized diagonal, per the <length> spec for r/stroke-width
    assert(isClose(a.convLen("width", 0, lc, RefAxis.diagonal),
                   0.1f * sqrt((480 ^^ 2 + 360 ^^ 2) / 2.0f), 1e-2f));
}

unittest
{
    // preserveAspectRatio
    assert(parsePAR("").alignX == 1 && parsePAR("").meet); // xMidYMid meet
    auto p = parsePAR("xMinYMax slice");
    assert(p.alignX == 0 && p.alignY == 2 && !p.meet && !p.stretch);
    assert(parsePAR("none").stretch);
    assert(parsePAR("junk").alignX == 1); // error -> default

    float[4] vb = [10.0f, 20.0f, 100.0f, 50.0f];

    // meet: whole viewBox, centered
    auto m = viewFit(vb, 200, 200, parsePAR(""));
    assert(m * FPoint(10, 20) == FPoint(0, 50)); // s = 2, y centered
    assert(m * FPoint(110, 70) == FPoint(200, 150));

    // slice: cover the viewport, clip the long axis
    m = viewFit(vb, 200, 200, parsePAR("xMinYMin slice"));
    assert(m * FPoint(10, 20) == FPoint(0, 0)); // s = 4, origins pinned

    // none: non-uniform
    m = viewFit(vb, 200, 100, parsePAR("none"));
    assert(m * FPoint(110, 70) == FPoint(200, 100));

    // xMaxYMax meet
    m = viewFit(vb, 300, 200, parsePAR("xMaxYMax meet"));
    assert(m * FPoint(110, 70) == FPoint(300, 200)); // s = 3, flush right/bottom
}

unittest
{
    // stroke-dasharray parsing
    assert(parseDash("none") is null);
    assert(parseDash("") is null);
    assert(parseDash("10") == [10.0f, 10.0f]); // odd count repeats
    assert(parseDash("2, 5.5") == [2.0f, 5.5f]);
    assert(parseDash("1 2 3") == [1.0f, 2.0f, 3.0f, 1.0f, 2.0f, 3.0f]);
    assert(parseDash("0 0") is null); // sums to zero: like none
    assert(parseDash("-1") is null); // negative: invalid
    assert(parseDash("x") is null);

    // dash lengths stay exact and the offset shifts the pattern start
    Path line;
    line.moveTo(FPoint(0, 0));
    line.lineTo(FPoint(10, 0));
    auto d = svgDash(line, [2.0f, 2.0f], 0);
    size_t runs;
    foreach (v; d.verbs)
        if (v == Path.Verb.Move)
            ++runs;
    assert(runs == 3, to!string(runs)); // 0-2, 4-6, 8-10

    d = svgDash(line, [2.0f, 2.0f], 1); // start mid-dash: 0-1, then gaps
    runs = 0;
    float firstLen;
    Path.Verb[] vs;
    foreach (v, pts; d)
    {
        vs ~= v;
        if (v == Path.Verb.Move)
            ++runs;
    }
    assert(runs == 3);
    assert(vs.length && vs[0] == Path.Verb.Move);

    // a closed rect dashes around the closing edge too
    Path sq;
    sq.addRect(FRect(0, 0, 10, 10));
    d = svgDash(sq, [2.0f, 2.0f], 0);
    runs = 0;
    foreach (v; d.verbs)
        if (v == Path.Verb.Move)
            ++runs;
    assert(runs == 10, to!string(runs)); // perimeter 40 / pattern 4
}

unittest
{
    // currentColor, none, and keyword colors flow through to the bitmap:
    // a lime square painted via color="lime" + fill="currentColor".
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <g color="lime"><rect x="0" y="0" width="10" height="10" fill="currentColor" stroke="none"/></g>
        </svg>`);
    assert(bmp.width == 10 && bmp.height == 10);
    auto px = bmp.getLine!PMColor(5)[5];
    assert(px.r == 0 && px.g == 255 && px.b == 0, to!string(px));

    // fill="none" + stroke paints only the outline
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <rect x="2" y="2" width="4" height="4" fill="none" stroke="red" stroke-width="2"/>
        </svg>`);
    px = bmp.getLine!PMColor(4)[4]; // inside the hole of the ring
    assert(px.r == 0 && px.g == 0 && px.b == 0, to!string(px));
    px = bmp.getLine!PMColor(4)[2]; // on the stroke
    assert(px.r == 255, to!string(px));
}

unittest
{
    // viewBox + width/height="100%" (the W3C suite's standard prolog):
    // canvas takes the viewBox size.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 480 360"/>`);
    assert(bmp.width == 480 && bmp.height == 360, to!string(bmp.width));

    // zoom scales the canvas
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 480 360"/>`, 0.5);
    assert(bmp.width == 240 && bmp.height == 180);

    // percent width/height against the viewBox
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="50%" height="25%" viewBox="0 0 400 400"/>`);
    assert(bmp.width == 200 && bmp.height == 100);

    // no viewBox: canvas from width/height, 1:1
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#00ff00"/></svg>`);
    assert(bmp.width == 40 && bmp.height == 20);
    assert(bmp.getLine!PMColor(10)[10].g == 255);

    // a rect sized by percent of the viewport
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80" viewBox="0 0 100 80">
        <rect x="10%" y="0" width="50%" height="100%" fill="#0000ff"/>
        </svg>`);
    assert(bmp.getLine!PMColor(40)[59].b == 255); // x from 10 to 60
    assert(bmp.getLine!PMColor(40)[1].b == 0);
}

unittest
{
    // <defs> content must not paint; display="none" skips the subtree;
    // visibility="hidden" hides but keeps layout-relevant geometry out of
    // the raster.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <defs><rect x="0" y="0" width="10" height="10" fill="red"/></defs>
        <clipPath id="cp"><circle cx="5" cy="5" r="4"/></clipPath>
        <g display="none"><rect x="0" y="0" width="10" height="10" fill="green"/></g>
        <rect x="0" y="0" width="10" height="10" visibility="hidden" fill="blue"/>
        <rect x="8" y="8" width="2" height="2" fill="gold" visibility="inherit"/>
        </svg>`);
    foreach (y; 0 .. 10)
        foreach (x, px; bmp.getLine!PMColor(y)) {
            if (x >= 8 && y >= 8)
                continue; // the gold 2x2 in the bottom-right corner
            assert(px.r == 0 && px.g == 0 && px.b == 0, to!string([x, y, px.r, px.g, px.b]));
        }
    assert(bmp.getLine!PMColor(9)[9].r == 255); // gold survived
}

unittest
{
    // <use> deep-clones the referenced content at the use site. The
    // instance inherits from the <use> element - NOT from the source
    // context (the defs' red/yellow group must not bleed through) -
    // and x/y offsets the clone.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="20" height="10" viewBox="0 0 20 10">
        <defs><g fill="red" stroke="yellow" stroke-width="3"><rect id="r" width="10" height="10"/></g></defs>
        <use xlink:href="#r" x="10" fill="#00ff00" stroke="none"/>
        </svg>`);
    foreach (x, px; bmp.getLine!PMColor(5))
        assert(px.r == 0 && px.b == 0, to!string([x, px.r, px.g, px.b])); // nothing from the defs group
    assert(bmp.getLine!PMColor(5)[15].g == 255);   // the clone, shifted to x=10
    assert(bmp.getLine!PMColor(5)[5].g == 0);      // ...and nothing at the origin
}

unittest
{
    // use x/y is applied *before* the transform attribute (innermost):
    // rect 10x10 moved to x=20, then rotate(180 15 15) maps [20,30]x[0,10]
    // to [0,10]x[20,30]. The wrong order would land off-canvas entirely.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="30" height="30" viewBox="0 0 30 30">
        <defs><rect id="r" width="10" height="10" fill="#00ff00"/></defs>
        <use xlink:href="#r" x="20" transform="rotate(180 15 15)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(25)[5].g == 255, "x/y then rotate lands bottom-left");
    assert(bmp.getLine!PMColor(5)[5].g == 0);   // the source (in defs) stays unpainted
}

unittest
{
    // <symbol> + <use>: the use sizes the instance viewport (20x10), the
    // symbol's viewBox stretches into it (a 500/1000 quarter -> 10x5), and
    // without a viewBox the symbol's user space stays 1:1.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="30" height="10" viewBox="0 0 30 10">
        <symbol id="s" viewBox="0 0 1000 1000" preserveAspectRatio="none">
            <rect width="500" height="500" fill="#00ff00"/>
        </symbol>
        <use xlink:href="#s" width="20" height="10"/>
        </svg>`);
    assert(bmp.getLine!PMColor(2)[2].g == 255, "scaled quarter fills 10x5 of the box");
    assert(bmp.getLine!PMColor(8)[15].g == 0 && bmp.getLine!PMColor(8)[25].g == 0);

    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="20" height="20" viewBox="0 0 20 20">
        <symbol id="s"><rect width="5" height="5" fill="#00ff00"/></symbol>
        <use xlink:href="#s" x="10" y="10" width="8" height="8"/>
        </svg>`);
    assert(bmp.getLine!PMColor(12)[12].g == 255 && bmp.getLine!PMColor(12)[16].g == 0,
        "viewBox-less symbol stays 1:1 (rect 5x5 inside the 8x8 box)");
}

unittest
{
    // A referenced <svg> behaves like a symbol: the use's width/height
    // size the cloned viewport (struct-use-07-b), overriding the target's
    // own width/height attrs; its viewBox maps into that box.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="30" height="30" viewBox="0 0 30 30">
        <defs>
            <svg id="sub" viewBox="0 0 100 100" width="100" height="100">
                <rect width="100" height="100" fill="#00ff00"/>
            </svg>
        </defs>
        <use xlink:href="#sub" x="10" y="10" width="20" height="20"/>
        </svg>`);
    assert(bmp.getLine!PMColor(15)[15].g == 255, "scaled clone fills the use box");
    assert(bmp.getLine!PMColor(29)[29].g == 255 && bmp.getLine!PMColor(11)[11].g == 255);
    assert(bmp.getLine!PMColor(5)[5].g == 0, "the original (in defs) stays unpainted");
}

unittest
{
    // Conditional processing guards any element: requiredExtensions is
    // never satisfied, requiredFeatures splits on whitespace and ';'
    // (a bogus token sinks the element, types-dom-06-f style), and
    // systemLanguage range-matches the user language ("en": "en-GB" as a
    // range does NOT match, "de;en" does; an empty list never matches).
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        width="10" height="10" viewBox="0 0 10 10">
        <rect width="10" height="10" fill="red" requiredExtensions="http://example.org/bogus"/>
        <rect width="10" height="10" fill="lime" systemLanguage="en-GB"/>
        <rect width="10" height="10" fill="blue" systemLanguage=""/>
        <rect width="10" height="10" fill="gold"
            requiredFeatures="http://www.w3.org/TR/SVG11/feature#Shape bogus.feature.string"/>
        <rect width="10" height="10" fill="#0000ff"
            requiredFeatures="http://www.w3.org/TR/SVG11/feature#Shape;http://www.w3.org/TR/SVG11/feature#Path"/>
        </svg>`);
    auto px = bmp.getLine!PMColor(5)[5];
    assert(px.b == 255 && px.r == 0 && px.g == 0, to!string([px.r, px.g, px.b])); // only the last rect survives

    // empty requiredFeatures passes vacuously (and a subtree fails whole):
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        width="10" height="10" viewBox="0 0 10 10">
        <g requiredFeatures="http://www.w3.org/TR/SVG11/feature#SVGDOM">
            <rect width="10" height="10" fill="red"/>
        </g>
        <g requiredFeatures="">
            <g requiredFeatures="INVALID">
                <rect width="10" height="10" fill="lime"/>
            </g>
        </g>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "failing tests drop the whole subtree");

    // <switch>: first child whose tests pass renders, the rest never;
    // an untested last child is the fallback (struct-cond-01-t/02-t/03-t).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        width="10" height="10" viewBox="0 0 10 10">
        <switch>
            <rect width="10" height="10" fill="red" requiredExtensions="http://example.org/bogus"/>
            <rect width="10" height="10" fill="lime"
                requiredFeatures="http://www.w3.org/TR/SVG11/feature#BasicText"/>
            <rect width="10" height="10" fill="blue"/>
        </switch>
        <switch transform="translate(0, 5)">
            <rect width="10" height="5" fill="red" systemLanguage="de"/>
            <rect y="5" width="10" height="5" fill="gold"/>
        </switch>
        </svg>`);
    px = bmp.getLine!PMColor(2)[5];
    assert(px.g == 255 && px.r == 0, "switch picks BasicText branch, never the fallback");
    px = bmp.getLine!PMColor(7)[5];
    assert(px.r == 255 && px.g >= 200 && px.b == 0, "fallback child renders when tests all fail");
}

unittest
{
    // A failing conditional test on a use TARGET suppresses the instance
    // (struct-cond-overview-02-f), but one on the target's original
    // ancestors only hides the original (struct-cond-overview-05-f).
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="20" height="10" viewBox="0 0 20 10">
        <rect id="off" width="10" height="10" fill="red" requiredExtensions="http://example.org/x"/>
        <g requiredFeatures="INVALID">
            <rect id="parented" x="10" width="10" height="10" fill="#00ff00"/>
        </g>
        <use xlink:href="#off"/>
        <use xlink:href="#parented"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "instance of a failing target stays hidden");
    assert(bmp.getLine!PMColor(5)[15].g == 255, "instance under a failing parent renders");
}

unittest
{
    // Reference cycles must terminate: a self-cycle pair and a 10-long
    // chain both render nothing (struct-use-12-f); a forward href (the
    // target defined *after* the use) resolves through the registry.
    renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="10" height="10" viewBox="0 0 10 10">
        <use id="a" xlink:href="#b" x="10" y="10"/><use id="b" xlink:href="#a" x="10" y="10"/>
        <use id="c1" xlink:href="#c2"/><use id="c2" xlink:href="#c3"/><use id="c3" xlink:href="#c1"/>
        </svg>`); // returns; no hang

    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="20" height="10" viewBox="0 0 20 10">
        <use xlink:href="#later"/>
        <rect id="later" x="10" width="10" height="10" fill="#00ff00"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[15].g == 255, "forward href");
    assert(bmp.getLine!PMColor(5)[5].g == 0, "the clone paints at the href's own coords");
}

unittest
{
    // Nested use: an instance containing a use that references a g of
    // shapes (struct-use-11-f style); and <a> acts as a styled container
    // whose fill inherits into the linked content.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="30" height="10" viewBox="0 0 30 10">
        <defs>
            <g id="unit"><rect width="10" height="10"/></g>
            <g id="pair"><use xlink:href="#unit"/><use xlink:href="#unit" x="10"/></g>
        </defs>
        <use xlink:href="#pair" x="10" fill="#00ff00"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[12].g == 255 && bmp.getLine!PMColor(5)[22].g == 255);

    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        width="10" height="10" viewBox="0 0 10 10">
        <a fill="#00ff00"><rect width="10" height="10"/></a>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].g == 255, "<a> fill inherits to its child");
}

unittest
{
    // fill-rule="evenodd" is honoured: the straight-line pentagram
    // {5/2} has |W| = 2 in its pentagon core, which even-odd punches
    // out and non-zero fills.
    string pentagram(string extra)
    {
        return `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
            <path d="M20,2 31.8,38 1,15.6 39,15.6 8.2,38 Z" ` ~ extra ~ ` fill="white"/>
            </svg>`;
    }

    auto eo = renderSVG(pentagram(`fill-rule="evenodd"`));
    assert(eo.getLine!PMColor(20)[20].r < 60, "even-odd punches the pentagram core");

    auto nz = renderSVG(pentagram(`fill-rule="nonzero"`));
    assert(nz.getLine!PMColor(20)[20].r > 200, "nonzero fills the pentagram core");

    // unset defaults to nonzero; the property inherits; junk keeps parent
    assert(renderSVG(pentagram("")).getLine!PMColor(20)[20].r > 200);
    auto inherited = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <g fill-rule="evenodd"><path d="M20,2 31.8,38 1,15.6 39,15.6 8.2,38 Z" fill="white"/></g>
        </svg>`);
    assert(inherited.getLine!PMColor(20)[20].r < 60, "fill-rule inherits from the group");
    auto reReset = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <g fill-rule="evenodd"><path fill-rule="nonzero" d="M20,2 31.8,38 1,15.6 39,15.6 8.2,38 Z" fill="white"/></g>
        </svg>`);
    assert(reReset.getLine!PMColor(20)[20].r > 200, "fill-rule resets per element");
    auto junk = renderSVG(pentagram(`fill-rule="inherit"`));
    assert(junk.getLine!PMColor(20)[20].r > 200, "inherit at root keeps the initial nonzero");

    // a Jordan contour (the 10-vertex star outline) renders byte-identically
    // under both rules: on F in [0,1] both coverage transforms are the
    // identity, and reconstruction noise around |F| = 1 ties lands just
    // under full, where quantizeCoverage calls it full again.
    string jordan(string extra)
    {
        return `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
            <path d="M20,2 25.3,15.6 39,15.6 27.9,24.1 31.8,38 20,29.6 8.2,38 12.1,24.1 1,15.6 14.7,15.6 Z" `
               ~ extra ~ ` fill="white"/>
            </svg>`;
    }
    auto ja = renderSVG(jordan(`fill-rule="evenodd"`));
    auto jb = renderSVG(jordan(`fill-rule="nonzero"`));
    foreach (y; 0 .. 40)
        assert(ja.getLine!PMColor(y) == jb.getLine!PMColor(y), text("Jordan contour differs at row ", y));
    assert(ja.getLine!PMColor(20)[20].r > 200); // inside either way
}

unittest
{
    // nested same-direction triangles (mirrors paths-data-04-t): the
    // inner triangle is W=2, so even-odd renders a ring and non-zero a
    // solid fill; a reversed inner contour cancels the winding under
    // non-zero but parity still punches it under even-odd.
    string nested(string inner, string extra)
    {
        return `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
            <path d="M16,3 29,27 3,27 Z M` ~ inner ~ ` Z" ` ~ extra ~ ` fill="white"/>
            </svg>`;
    }
    alias px = (Bitmap b, int x, int y) => b.getLine!PMColor(y)[x].r;

    auto eo = renderSVG(nested("16,11 23,23 9,23", `fill-rule="evenodd"`));
    auto nz = renderSVG(nested("16,11 23,23 9,23", `fill-rule="nonzero"`));
    assert(px(eo, 16, 8) > 200 && px(nz, 16, 8) > 200); // the band fills either way
    assert(px(eo, 16, 18) < 60,  "even-odd: inner triangle is a hole");
    assert(px(nz, 16, 18) > 200, "nonzero: inner triangle fills (W=2)");

    auto revEo = renderSVG(nested("16,11 9,23 23,23", `fill-rule="evenodd"`));
    auto revNz = renderSVG(nested("16,11 9,23 23,23", `fill-rule="nonzero"`));
    assert(px(revEo, 16, 18) < 60, "even-odd punches regardless of orientation");
    assert(px(revNz, 16, 18) < 60, "reversed inner contour cancels winding under nonzero");

    // sign independence: a single reversed Jordan contour fills under
    // even-odd exactly like the same contour forward
    auto fwd = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
        <path d="M16,3 29,27 3,27 Z" fill-rule="evenodd" fill="white"/>
        </svg>`);
    auto rev = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
        <path d="M16,3 3,27 29,27 Z" fill-rule="evenodd" fill="white"/>
        </svg>`);
    assert(px(fwd, 16, 10) > 200 && px(rev, 16, 10) > 200, "even-odd is orientation independent");
}

unittest
{
    // two same-direction circle subpaths in ONE path element: the lens
    // is W=2, punched under even-odd, filled under non-zero. (Separate
    // <circle> elements would rasterize as separate rasters and never
    // sum windings - this must be a compound path.)
    const d = "M21,16 A9,9 0 1 1 3,16 A9,9 0 1 1 21,16 Z "
           ~ "M29,16 A9,9 0 1 1 11,16 A9,9 0 1 1 29,16 Z";
    string ovals(string extra)
    {
        return `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
            <path d="` ~ d ~ `" ` ~ extra ~ ` fill="white"/>
            </svg>`;
    }
    auto eo = renderSVG(ovals(`fill-rule="evenodd"`));
    auto nz = renderSVG(ovals(`fill-rule="nonzero"`));
    assert(eo.getLine!PMColor(16)[16].r < 60, "even-odd punches the overlap lens");
    assert(nz.getLine!PMColor(16)[16].r > 200, "nonzero fills the overlap lens");
    assert(eo.getLine!PMColor(16)[8].r > 200 && nz.getLine!PMColor(16)[8].r > 200); // single coverage fills
}

unittest
{
    // Documented limitation: ∫ and mod 2 do not commute, so cells with
    // TWO boundary crossings mis-evaluate. Two same-direction rectangles
    // cross the non-zero/even-odd wire exactly at two pixel centers
    // ((6.5,3.5) and (4.5,6.5)); all coordinates are dyadic so the
    // winding field there is bit-exact: those cells read F = 1.0, the
    // even-odd tie that yields FULL coverage where truth is exactly
    // half. The deviation is asserted as BOUNDED, so a future change -
    // improvement or new failure mode - trips this test.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
        <path fill-rule="evenodd" fill="white"
              d="M0.5,0.5 H6.5 V6.5 H0.5 Z M4.5,3.5 H14.5 V13.5 H4.5 Z"/>
        </svg>`);

    // exact even-odd coverage for axis-aligned rectangles: the odd-wound
    // region is the symmetric difference A △ B.
    struct Rect { double l, t, r, b; }
    enum A = Rect(0.5, 0.5, 6.5, 6.5), B = Rect(4.5, 3.5, 14.5, 13.5);
    double span(double lo, double hi, double x0, double x1)
    {
        return max(0.0, min(hi, x1) - max(lo, x0));
    }
    double area(Rect r, int px, int py)
    {
        return span(r.l, r.r, px, px + 1.0) * span(r.t, r.b, py, py + 1.0);
    }
    double overlapArea(int px, int py)
    {
        Rect c = Rect(max(A.l, B.l), max(A.t, B.t), min(A.r, B.r), min(A.b, B.b));
        return area(c, px, py);
    }

    size_t badCells;
    foreach (py; 0 .. 16)
    {
        auto row = bmp.getLine!PMColor(py);
        foreach (px; 0 .. 16)
        {
            immutable pxc = row[px];
            immutable cov = area(A, px, py) + area(B, px, py) - 2 * overlapArea(px, py);
            // AA coverage rides the alpha byte; the save pass keeps the
            // white channel straight (near 255) wherever alpha is nonzero.
            immutable dev = abs(pxc.a / 255.0 - cov);
            immutable twoCrossings = (px == 6 && py == 3) || (px == 4 && py == 6);
            if (pxc.a)
                assert(pxc.r >= 240, text("straight channel lost at ", [px, py]));
            if (twoCrossings)
            {
                ++badCells;
                assert(pxc.a >= 240, text("tie cell not near full coverage at ", [px, py]));
                assert(dev <= 0.55, text("deviation unbounded at ", [px, py, dev]));
            }
            else
                assert(dev <= 4.0 / 255, text("unexpected deviation at ", [px, py, dev]));
        }
    }
    assert(badCells == 2, text("expected exactly the two crossing cells, got ", badCells));
}

unittest
{
    // nested <svg> viewport: viewBox + x/y offset
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <svg x="10" y="10" width="20" height="20" viewBox="0 0 10 10">
            <rect x="5" width="5" height="10" fill="red"/>
        </svg>
        </svg>`);
    // user x 5..10 -> local 10..20 -> device x 20..30
    assert(bmp.getLine!PMColor(20)[25].r == 255);
    assert(bmp.getLine!PMColor(20)[19].r == 0);
    assert(bmp.getLine!PMColor(20)[10].r == 0);
    assert(bmp.getLine!PMColor(5)[5].r == 0); // outside the viewport

    // preserveAspectRatio="none" stretches
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 10 10" preserveAspectRatio="none">
        <rect x="5" y="5" width="5" height="5" fill="lime"/>
        </svg>`);
    assert(bmp.getLine!PMColor(15)[35].g == 255);
}

unittest
{
    // stroke-linecap/-linejoin/-dasharray reach the rasterizer: round caps
    // bulge past the endpoints of a butt-stroked line.
    auto bmpR = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <path d="M10,10 h20" stroke="red" stroke-width="6" stroke-linecap="round"/>
        </svg>`);
    auto bmpB = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <path d="M10,10 h20" stroke="red" stroke-width="6"/>
        </svg>`);
    assert(bmpR.getLine!PMColor(10)[8].r == 255); // under a round cap
    assert(bmpB.getLine!PMColor(10)[8].r == 0);   // butt cap: not there

    // dashed stroke: gaps stay empty
    auto bmpD = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <path d="M10,10 h20" stroke="red" stroke-width="6" stroke-dasharray="4 4" stroke-dashoffset="0"/>
        </svg>`);
    assert(bmpD.getLine!PMColor(10)[11].r == 255); // dash at 10..14
    assert(bmpD.getLine!PMColor(10)[15].r == 0);   // gap at 14..18
    assert(bmpD.getLine!PMColor(10)[19].r == 255); // dash at 18..22
}

unittest
{
    // <line> spans x1,y1 -> x2,y2 (SVG 1.1 shapes chapter): the segment
    // lives where the attributes say, not from the origin.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <line x1="2" y1="3" x2="18" y2="3" stroke="red" stroke-width="2"/>
        </svg>`);
    auto row = bmp.getLine!PMColor(3);
    assert(row[1].a == 0 && row[2].r == 255, "segment starts at x1");
    assert(row[17].r == 255 && row[18].a == 0, "segment ends at x2");
    assert(bmp.getLine!PMColor(2)[9].r == 255
        && bmp.getLine!PMColor(4)[9].a == 0, "stroke-width 2 centred on y1");

    // A zero-length line paints nothing (and must not trip the stroker).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <line x1="9" y1="5" x2="9" y2="5" stroke="red" stroke-width="8" stroke-linecap="round"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[9].a == 0, "zero-length line paints nothing");

    // skewX(45) shears x by +y (affine, not the projective shear the
    // matrix library's w-row would give): mid-stroke lands at x = 30+25.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="70" height="60" viewBox="0 0 70 60">
        <line x1="30" y1="40" x2="30" y2="10" stroke="red" stroke-width="4" transform="skewX(45)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(25)[55].r == 255, "skewed segment follows the shear");
    assert(bmp.getLine!PMColor(25)[30].a == 0, "nothing stays at the unskewed x");
}

unittest
{
    // fill="url(#id)" rasterizes a gradient paint server: the exact stop
    // colours land at the ramp's endpoints, with a premultiplied blend in
    // between (device==user space for the default identity CTM).
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <defs>
            <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="#ff0000"/>
                <stop offset="1" stop-color="#0000ff"/>
            </linearGradient>
        </defs>
        <rect width="10" height="10" fill="url(#g)"/>
        </svg>`);
    auto row = bmp.getLine!PMColor(5);
    assert(row[0].r == 255 && row[0].b == 0 && row[0].a == 255, to!string([row[0].a, row[0].r, row[0].b]));
    assert(row[9].b >= 200 && row[9].r <= 55, to!string([row[9].r, row[9].b])); // x=9: t=0.9
    assert(row[4].b > row[3].b && row[5].b > row[4].b, "monotonic ramp across the span");
    assert(row[5].r >= 100 && row[5].r <= 156, "premultiplied blend at x=5");

    // objectBoundingBox (the default): fractions of the shape's own bbox.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <defs><linearGradient id="g">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </linearGradient></defs>
        <rect x="10" width="10" height="10" fill="url(#g)"/>
        </svg>`);
    row = bmp.getLine!PMColor(5);
    assert(row[5].a == 0, "nothing left of the shape");
    assert(row[10].r == 255 && row[10].b == 0, "shape left edge is the ramp start");
    assert(row[19].b >= 200 && row[19].r <= 55, "shape right edge is the ramp end");

    // A paint server error paints nothing (as if the paint were none)...
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <rect width="10" height="10" fill="url(#nope)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "unknown paint server paints nothing");

    // ...while the documented `url(#id) paint` fallback rescues it.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <rect x="5" width="5" height="10" fill="url(#nope) lime"/>
        </svg>`);
    row = bmp.getLine!PMColor(5);
    assert(row[2].a == 0 && row[7].g == 255 && row[7].r == 0, to!string([row[2].a, row[7].g, row[7].r]));

    // A flat bbox makes the objectBoundingBox mapping degenerate (§7.11):
    // the server errors, so `url(#g) lime` falls back to the paint and
    // without a fallback nothing strokes - even though the gradient
    // itself parsed fine. pservers-grad-17-b's exact lesson.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <defs><linearGradient id="g">
            <stop offset="0" stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient></defs>
        <line x1="2" y1="3" x2="18" y2="3" stroke="url(#g) lime" stroke-width="2"/>
        <line x1="2" y1="6" x2="18" y2="6" stroke="red" stroke-width="2"/>
        <line x1="2" y1="8" x2="18" y2="8" stroke="url(#g)" stroke-width="2"/>
        </svg>`);
    assert(bmp.getLine!PMColor(6)[10].r == 255, "control: plain stroke paints");
    auto pr = bmp.getLine!PMColor(3)[10];
    assert(pr.g == 255, "flat bbox: fallback paint strokes the line");
    assert(bmp.getLine!PMColor(8)[10].a == 0, "flat bbox without fallback paints nothing");

    // A gradient href'ing itself is an error state: paints nothing.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
        width="10" height="10" viewBox="0 0 10 10">
        <defs><linearGradient id="sc" xlink:href="#sc" gradientUnits="userSpaceOnUse" x1="0" x2="10" y1="0" y2="0">
            <stop offset="1" stop-color="red"/>
        </linearGradient></defs>
        <rect width="10" height="10" fill="url(#sc)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "self-referencing gradient paints nothing");

    // Paint alphas fold into the stop alphas at build time (the blitter
    // only applies AA coverage): stop-opacity 0.5 x fill-opacity 0.5 of
    // opaque white lands at alpha ~ 255*0.25 = 64; the straight-out save
    // recovers the near-white channel from the premultiplied 64.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="10" y1="0" y2="0">
            <stop offset="0" stop-color="white" stop-opacity="0.5"/>
            <stop offset="1" stop-color="white" stop-opacity="0.5"/>
        </linearGradient></defs>
        <rect width="10" height="10" fill="url(#g)" fill-opacity="0.5"/>
        </svg>`);
    auto px = bmp.getLine!PMColor(5)[5];
    assert(px.a >= 60 && px.a <= 68 && px.r >= 248, to!string([px.a, px.r]));
}

unittest
{
    // userSpaceOnUse gradient coordinates live in the user space in effect
    // at the reference: the element's own transform moves shape and ramp
    // together, and <use> inherits the referencing paint unchanged.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </linearGradient></defs>
        <g transform="translate(10 0)"><rect width="10" height="10" fill="url(#g)"/></g>
        </svg>`);
    auto row = bmp.getLine!PMColor(5);
    assert(row[5].a == 0, "left half stays empty");
    assert(row[10].r == 255, "ramp start moved with the element transform");
    assert(row[19].b >= 200);

    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <defs>
            <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
            </linearGradient>
            <rect id="r" width="10" height="10"/>
        </defs>
        <g fill="url(#g)" transform="translate(10 0)"><use href="#r"/></g>
        </svg>`);
    row = bmp.getLine!PMColor(5);
    assert(row[5].a == 0);
    assert(row[10].r == 255, "use instances paint the inherited gradient");
    assert(row[19].b >= 200);
}

unittest
{
    // stroke="url(#g)": bbox units see the geometry box BEFORE the stroke
    // expansion - at x=15 (geometry right edge) the pad-clamped stroke is
    // pure end-stop blue, where a stroke-bbox ramp would still be mixed.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
        <defs><linearGradient id="g">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </linearGradient></defs>
        <rect x="5" y="3" width="10" height="4" fill="none" stroke="url(#g)" stroke-width="2"/>
        </svg>`);
    auto row = bmp.getLine!PMColor(5);
    assert(row[4].r == 255 && row[4].b == 0, "left band: ramp start pads");
    assert(row[15].b == 255 && row[15].r == 0, to!string([row[15].r, row[15].b]));
    assert(row[10].a == 0, "fill=none keeps the interior empty");
}

unittest
{
    // radial on a rect: the centre is stop[0] white, the rim pads stop[1].
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <defs><radialGradient id="r" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="5">
            <stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/>
        </radialGradient></defs>
        <rect width="10" height="10" fill="url(#r)"/>
        </svg>`);
    auto row = bmp.getLine!PMColor(5);
    assert(row[5].r >= 250, "centre paints stop[0]");
    assert(row[0].r <= 8, "opposite rim pads stop[1]");
    assert(row[9].r < 60 && row[9].r > row[0].r, "approaching the rim darkens");
}

unittest
{
    // fill="url(#g)" on <text>: the glyph outline path carries the shader
    // (flushText resolves paint from the glyph geometry bbox). Host font
    // metrics vary, so only "painted at all, and ramp-coloured" is checked.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="40" y1="0" y2="0">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#00ff00"/>
        </linearGradient></defs>
        <text x="2" y="15" font-size="16" fill="url(#g)">M</text>
        </svg>`);
    size_t painted;
    bool reddish;
    foreach (y; 0 .. 20)
        foreach (x, p; bmp.getLine!PMColor(y))
            if (p.a)
            {
                ++painted;
                if (x < 12 && p.r > 150 && p.r > 2 * p.g)
                    reddish = true;
            }
    assert(painted > 10, "the M glyph painted");
    assert(reddish, "glyph picked up the red end of the ramp");
}

unittest
{
    // <pattern> tiling (§14.2), pservers-pattern-01-b's lesson: a 20x20
    // lattice offset to (10,10); yellow tile-local 5..15, green over it
    // at 10..20 in both axes. Sampling is nearest, tiles exact at 1:1.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink" width="60" height="40" viewBox="0 0 60 40">
        <pattern id="p" patternUnits="userSpaceOnUse" x="10" y="10" width="20" height="20">
            <rect x="5" y="5" width="10" height="10" fill="yellow"/>
            <rect x="10" y="10" width="10" height="10" fill="green"/>
        </pattern>
        <rect x="10" y="10" width="40" height="20" fill="url(#p)"/>
        </svg>`);
    auto px = bmp.getLine!PMColor(17)[17];
    assert(px.r == 255 && px.g == 255 && px.b == 0, "tile-local (7,7) is yellow");
    px = bmp.getLine!PMColor(22)[22];
    assert(px.g == 128 && px.r == 0, "tile-local (12,12) is green (CSS green = 0x008000)");
    assert(bmp.getLine!PMColor(10)[10].a == 0, "tile-local (0,0) paints nothing");
    // Lattice period: (37,17) is one period right of (17,17).
    px = bmp.getLine!PMColor(17)[37];
    assert(px.r == 255 && px.g == 255 && px.b == 0, "lattice repeats every 20");

    // viewBox="0 0 10 10" on the tile fits content into (0,0,W,H): the
    // 10x5 half-height rect becomes the top half of a 100px tile.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <pattern id="v" patternUnits="userSpaceOnUse" width="100" height="100" viewBox="0 0 10 10">
            <rect width="10" height="5" fill="blue"/>
        </pattern>
        <rect width="100" height="100" fill="url(#v)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[10].b == 255, "viewBox content fills the tile top");
    assert(bmp.getLine!PMColor(60)[10].a == 0, "and not below the half");

    // patternContentUnits="objectBoundingBox": content coordinates are
    // fractions of the referencing shape's bbox.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <pattern id="bc" patternUnits="userSpaceOnUse" width="40" height="40"
            patternContentUnits="objectBoundingBox">
            <rect width="0.25" height="0.25" fill="red"/>
        </pattern>
        <rect width="100" height="100" fill="url(#bc)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].r == 255, "bbox content unit: quarter of the bbox");
    assert(bmp.getLine!PMColor(30)[5].a == 0, "outside the 25px content corner");
    assert(bmp.getLine!PMColor(5)[45].r == 255, "next lattice period shows it again");

    // Zero tile size carrying a viewBox: an "invisible" server painting no
    // area - invisible even with a fallback given (pservers-pattern-09-f).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <pattern id="z" width="0" height="0" viewBox="0 0 10 10"><rect width="10" height="10" fill="red"/></pattern>
        <rect width="20" height="20" fill="url(#z) lime"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "invisible pattern paints nothing, not the fallback");

    // Zero tile size without a viewBox is a server error: fallback paints
    // (pservers-pattern-03-f's eight green squares).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <pattern id="z2" width="0" height="10"><rect width="10" height="10" fill="red"/></pattern>
        <rect width="20" height="20" fill="url(#z2) lime"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].g == 255 && bmp.getLine!PMColor(5)[5].r == 0,
        "empty pattern without viewBox takes the fallback");

    // A dangling href has no effect when the pattern defines itself
    // (pservers-pattern-07-f): the tiles paint.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
        <pattern id="bad" patternUnits="userSpaceOnUse" width="10" height="10" xlink:href="#missing">
            <rect width="10" height="10" fill="red"/>
        </pattern>
        <rect width="20" height="20" fill="url(#bad) lime"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].r == 255 && bmp.getLine!PMColor(5)[15].r == 255,
        "dangling href: the pattern paints its own tiles");

    // A pattern whose content references itself: depth-capped, paints
    // nothing through to the shape (and must terminate).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <pattern id="self" width="10" height="10">
            <rect width="10" height="10" fill="url(#self)"/>
        </pattern>
        <rect width="20" height="20" fill="url(#self)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "cyclic pattern paints nothing");
}

unittest
{
    // clip-path basics (masking-path-01/02-b): a 10px-wide clipPath rect
    // keeps the left half of a full red rect.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <clipPath id="c"><rect width="10" height="20"/></clipPath>
        <rect width="20" height="20" fill="red" clip-path="url(#c)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[5].r == 255, "inside the clip paints");
    assert(bmp.getLine!PMColor(10)[15].a == 0, "outside the clip paints nothing");

    // Broken references and empty clips mean NOT rendered - no fallback
    // paint server style (masking-path-08-b): unknown id, non-clipPath
    // target, empty clipPath, only-display:none children.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="40" viewBox="0 0 20 40">
        <rect id="notclip" width="5" height="5"/>
        <clipPath id="empty"/>
        <clipPath id="gonekid"><rect width="20" height="10" display="none"/></clipPath>
        <rect width="20" height="10" fill="red" clip-path="url(#nope)"/>
        <rect y="10" width="10" height="10" fill="red" clip-path="url(#notclip)"/>
        <rect y="20" width="10" height="10" fill="red" clip-path="url(#empty)"/>
        <rect y="30" width="10" height="10" fill="red" clip-path="url(#gonekid)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(3)[10].a == 0, "unknown id: not rendered");
    assert(bmp.getLine!PMColor(15)[5].a == 0, "non-clipPath target: not rendered");
    assert(bmp.getLine!PMColor(25)[5].a == 0, "empty clipPath: not rendered");
    assert(bmp.getLine!PMColor(35)[5].a == 0, "display:none kids only: not rendered");

    // Mask children: geometry only. visibility:hidden still clips;
    // opacity / fill=none / a fat stroke are all irrelevant, and stroke
    // never adds clip area (08-b's case grid).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <clipPath id="v"><rect width="10" height="100" visibility="hidden"/></clipPath>
        <clipPath id="o"><rect width="20" height="100" opacity="0" fill="none" stroke="black" stroke-width="4"/></clipPath>
        <clipPath id="sw"><rect x="40" y="40" width="20" height="20" stroke="black" stroke-width="80"/></clipPath>
        <rect width="100" height="100" fill="red" clip-path="url(#v)"/>
        <rect width="100" height="100" fill="lime" clip-path="url(#o)"/>
        <rect width="100" height="100" fill="blue" clip-path="url(#sw)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(50)[5].g == 255 && bmp.getLine!PMColor(50)[5].b == 0,
        "visibility/opacity/fill=none irrelevant: lime clips at x5");
    assert(bmp.getLine!PMColor(50)[15].g == 255 && bmp.getLine!PMColor(50)[15].b == 0,
        "stroke adds no clip area: lime survives, blue did not overwrite at x15");
    assert(bmp.getLine!PMColor(45)[45].b == 255, "stroked child: its fill outline clips at (45,45)");
    assert(bmp.getLine!PMColor(30)[45].a == 0, "and nothing outside the 20px outline (y30 clear)");

    // clip-rule (masking-path-05-f): nested squares on the clipPath CHILD,
    // evenodd punches a hole, nonzero fills solid.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="90" viewBox="0 0 40 90">
        <clipPath id="even"><path clip-rule="evenodd" d="M0,0H40V40H0Z M10,10H30V30H10Z"/></clipPath>
        <clipPath id="odd"><path clip-rule="nonzero" d="M0,50H40V90H0Z M10,60H30V80H10Z"/></clipPath>
        <rect width="40" height="40" fill="red" clip-path="url(#even)"/>
        <rect y="50" width="40" height="40" fill="red" clip-path="url(#odd)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(2)[2].r == 255, "evenodd ring paints");
    assert(bmp.getLine!PMColor(20)[20].a == 0, "evenodd hole stays clear");
    assert(bmp.getLine!PMColor(70)[20].r == 255, "nonzero fills the overlap solid");

    // clipPathUnits="objectBoundingBox" (masking-path-02-b): children are
    // fractions of the paint geometry's bbox; degenerate bbox -> not
    // rendered (even though the element would stroke visibly).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <clipPath id="bb" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
        <rect x="10" y="10" width="20" height="10" fill="red" clip-path="url(#bb)"/>
        <rect x="5" y="2" width="0" height="10" fill="none" stroke="blue" stroke-width="3" clip-path="url(#bb)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(15)[15].r == 255, "bbox fractions: left half of the shape paints");
    assert(bmp.getLine!PMColor(15)[25].a == 0, "right half stays clear");
    assert(bmp.getLine!PMColor(5)[5].a == 0, "degenerate bbox: stroked rect not rendered");

    // Group clips accumulate: g's clip reaches every descendant paint...
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <clipPath id="g2"><rect width="20" height="20"/></clipPath>
        <rect width="40" height="40" fill="red"/>
        <g clip-path="url(#g2)"><rect width="40" height="40" fill="lime"/></g>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[10].g == 255, "g clip paints inside");
    assert(bmp.getLine!PMColor(30)[30].r == 255, "outside, the g paints nothing");

    // ...and a descendant's own clip-path joins the group mask without
    // escaping it (binary masks commute); the clipPath SUBTREE sees
    // neither the group clip nor any referrer ancestor (masking-path-
    // 12-f's non-inheritance).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <clipPath id="outer"><rect width="20" height="40"/></clipPath>
        <rect width="40" height="40" fill="red"/>
        <g clip-path="url(#outer)"><clipPath id="kid"><rect x="20" width="20" height="40"/></clipPath></g>
        <rect width="40" height="40" fill="lime" clip-path="url(#kid)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(20)[30].g == 255, "kid clip paints on its own (no ancestor leak)");
    assert(bmp.getLine!PMColor(20)[10].r == 255, "and nowhere else");

    // Text in a clipPath clips with its glyph outlines (masking-path-
    // 04-b shape; host metrics only guarantee "painted, and not wide").
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
        <clipPath id="t"><text x="0" y="15" font-size="16">M</text></clipPath>
        <rect width="40" height="20" fill="blue" clip-path="url(#t)"/>
        </svg>`);
    bool glyphInk;
    foreach (y; 0 .. 20)
        foreach (x, p; bmp.getLine!PMColor(y)[0 .. 20])
            if (p.b == 255)
                glyphInk = true;
    assert(glyphInk, "the M outline clips paint inside it");
    foreach (y; 0 .. 20)
        assert(bmp.getLine!PMColor(y)[30].a == 0, "nothing beyond the glyph");

    // clip-path cycles between clipPath elements terminate (href cycles
    // invalidate; clip-path-attribute cycles hit the depth cap) and paint
    // nothing.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
        <clipPath id="h1" xlink:href="#h2"><rect width="20" height="20"/></clipPath>
        <clipPath id="h2" xlink:href="#h1"><rect width="20" height="20"/></clipPath>
        <clipPath id="a" clip-path="url(#b)"><rect width="20" height="20"/></clipPath>
        <clipPath id="b" clip-path="url(#a)"><rect width="20" height="20"/></clipPath>
        <rect width="10" height="10" fill="red" clip-path="url(#h1)"/>
        <rect y="10" width="10" height="10" fill="red" clip-path="url(#a)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "clipPath href cycle: invalid, not rendered");
    assert(bmp.getLine!PMColor(15)[5].a == 0, "clip-path attr cycle: capped, paints nothing");
}

unittest
{
    // Luminance masks (masking-mask-01-b semantics): white passes,
    // black blocks, pure red passes its Rec.709 luminance 0.2126, and
    // maskType="alpha" ignores colour entirely.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="80" viewBox="0 0 20 80">
        <mask id="half"><rect width="10" height="20" fill="white"/></mask>
        <mask id="blk"><rect y="20" width="20" height="20" fill="black"/></mask>
        <mask id="redl"><rect y="40" width="20" height="20" fill="red"/></mask>
        <mask id="ahalf" maskType="alpha"><rect y="60" width="20" height="20" fill="black" opacity="0.5"/></mask>
        <rect width="20" height="20" fill="lime" mask="url(#half)"/>
        <rect y="20" width="20" height="20" fill="lime" mask="url(#blk)"/>
        <rect y="40" width="20" height="20" fill="blue" mask="url(#redl)"/>
        <rect y="60" width="20" height="20" fill="lime" mask="url(#ahalf)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[5].g == 255, "white mask passes");
    assert(bmp.getLine!PMColor(10)[15].a == 0, "no mask coverage: nothing");
    assert(bmp.getLine!PMColor(30)[10].a == 0, "black mask blocks the element");
    immutable red = bmp.getLine!PMColor(50)[10];
    assert(red.a > 52 && red.a < 56 && red.b >= 245,
        "red luminance 0.2126 scales alpha (straight blue stays full)");
    immutable alf = bmp.getLine!PMColor(70)[10];
    assert(alf.a > 126 && alf.a < 130 && alf.g >= 250,
        "maskType=alpha: half-transparent black passes 0.5");

    // Broken mask references and empty masks: the element is not
    // rendered (same §14.1/§14.6 nonexistent-reference rule as clip).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="40" viewBox="0 0 20 40">
        <rect id="notmask" x="-6" y="10" width="5" height="5"/>
        <mask id="mempty"/>
        <mask id="mgone"><rect width="10" height="10" display="none"/></mask>
        <rect width="10" height="10" fill="red" mask="url(#nope)"/>
        <rect x="10" width="10" height="10" fill="red" mask="url(#notmask)"/>
        <rect y="10" width="10" height="10" fill="red" mask="url(#mempty)"/>
        <rect x="10" y="10" width="10" height="10" fill="red" mask="url(#mgone)"/>
        <rect y="20" width="10" height="10" fill="red" mask="url(#mempty)"/>
        <rect x="10" y="20" width="10" height="10" fill="red" mask="url(#mgone)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(5)[5].a == 0, "unknown id: not rendered");
    assert(bmp.getLine!PMColor(5)[15].a == 0, "non-mask target: not rendered");
    assert(bmp.getLine!PMColor(15)[5].a == 0, "empty mask: not rendered");
    assert(bmp.getLine!PMColor(25)[15].a == 0, "display:none content: empty mask too");

    // The region clips the mask CONTENT: a userSpaceOnUse frame cuts
    // the white sheet; the bbox-frame default (-10%,-10%,120%,120%)
    // and custom fractions bound the referrer's pixels directly.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="40" viewBox="0 0 20 40">
        <mask id="reg" maskUnits="userSpaceOnUse" x="0" y="0" width="10" height="20"><rect width="20" height="20" fill="white"/></mask>
        <mask id="breg" x="0" width="0.5"><rect x="-50" y="-50" width="120" height="120" fill="white"/></mask>
        <rect width="20" height="20" fill="lime" mask="url(#reg)"/>
        <rect y="20" width="20" height="20" fill="lime" mask="url(#breg)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[5].g == 255 && bmp.getLine!PMColor(10)[15].a == 0,
        "userSpaceOnUse region cuts the mask at x=10");
    assert(bmp.getLine!PMColor(30)[5].g == 255 && bmp.getLine!PMColor(30)[15].a == 0,
        "bbox region x=0 width=0.5 cuts at half the shape");

    // maskContentUnits="objectBoundingBox": children are bbox fractions.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <mask id="cu" maskContentUnits="objectBoundingBox"><rect width="0.5" height="1" fill="white"/></mask>
        <rect width="20" height="20" fill="lime" mask="url(#cu)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[5].g == 255, "content fractions: left half passes");
    assert(bmp.getLine!PMColor(10)[15].a == 0, "right half blocked");

    // A gradient mask gives soft alpha across the shape (the mask
    // children paint through the whole normal pipeline, url paints too).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <linearGradient id="wg"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient>
        <mask id="soft"><rect width="20" height="20" fill="url(#wg)"/></mask>
        <rect width="20" height="20" fill="blue" mask="url(#soft)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[2].a > 200, "near the white end almost opaque");
    assert(bmp.getLine!PMColor(10)[17].a < 60, "near the black end almost gone");

    // mask multiplies with clip-path on the same paint...
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <clipPath id="cl"><rect width="10" height="20"/></clipPath>
        <mask id="mr"><rect x="10" width="10" height="20" fill="white"/></mask>
        <rect width="20" height="20" fill="red" clip-path="url(#cl)" mask="url(#mr)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[5].a == 0 && bmp.getLine!PMColor(10)[15].a == 0,
        "clip left + mask right: the intersection is empty, nothing renders");

    // ...and ancestor masks accumulate exactly like clips (values
    // multiply: 1.0 * 0.5 = 0.5 alpha).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <mask id="g1m"><rect x="-10" y="-10" width="60" height="60" fill="white"/></mask>
        <mask id="g2m"><rect x="-10" y="-10" width="60" height="60" fill="white" opacity="0.5"/></mask>
        <g mask="url(#g1m)"><rect width="40" height="40" fill="lime" mask="url(#g2m)"/></g>
        </svg>`);
    immutable two = bmp.getLine!PMColor(20)[20];
    assert(two.a > 126 && two.a < 130 && two.g >= 250, "stacked masks multiply");

    // A mask that masks itself terminates at the nesting cap and,
    // every layer being empty, renders nothing.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
        <mask id="cyc" mask="url(#cyc)"><rect width="20" height="20" fill="white"/></mask>
        <rect width="20" height="20" fill="lime" mask="url(#cyc)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(10)[10].a == 0, "self-referencing mask: capped, not rendered");
}

unittest
{
    // §11.4 markers. A 4x4 red square, refX/refY (2,2), hangs centred
    // on each vertex of this polyline; the default markerUnits scales
    // the marker viewport by stroke-width 2, so each marker covers the
    // 8x8 block v-4 .. v+3.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="2"
            marker-start="url(#sq)" marker-mid="url(#sq)" marker-end="url(#sq)"/>
        </svg>`);
    foreach (vx; [6, 20, 34])
        assert(bmp.getLine!PMColor(17)[vx].r == 255, "start/mid/end markers at the vertices");
    assert(bmp.getLine!PMColor(16)[2].r == 255 && bmp.getLine!PMColor(23)[9].r == 255,
        "strokeWidth units scale the viewport: the box spans v-4 .. v+3");
    assert(bmp.getLine!PMColor(25)[20].a == 0, "nothing outside the marker boxes");
    immutable bare = bmp.getLine!PMColor(19)[12]; // between markers: just the stroke
    assert(bare.a == 255 && bare.r == 0 && bare.b == 0, "the stroke itself paints on");

    // No stroke and no fill: no markers.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" fill="none" stroke="none"
            marker-mid="url(#sq)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[20].a == 0, "no stroke and no fill, no markers");

    // orient: a tall bar (2x4) west of the ref point. orient 0 keeps it
    // there; orient 90 swings it over the pixel east of the vertex.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="bar" markerWidth="4" markerHeight="4" refX="2" refY="2" orient="0">
            <rect width="2" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="1"
            marker-mid="url(#bar)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(19)[18].r == 255 && bmp.getLine!PMColor(19)[21].r == 0,
        "orient 0: the bar sits west of the vertex");
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="bar" markerWidth="4" markerHeight="4" refX="2" refY="2" orient="90">
            <rect width="2" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="1"
            marker-mid="url(#bar)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(19)[21].r == 255, "orient 90: the bar swings over the vertex");

    // orient="auto" follows the path tangent (bisector at a mid vertex):
    // on the vertical polyline (0,1) is 90 degrees, same box as above.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="bar" markerWidth="4" markerHeight="4" refX="2" refY="2" orient="auto">
            <rect width="2" height="4" fill="red"/></marker>
        <path d="M 20 6 L 20 20 L 20 34" stroke="black" stroke-width="1"
            marker-mid="url(#bar)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(19)[21].r == 255, "auto: tangent (0,1) turns the bar 90 degrees");
    assert(bmp.getLine!PMColor(19)[18].r == 255, "auto: the bar crosses the vertex");

    // markerUnits="userSpaceOnUse" ignores stroke-width: v-2 .. v+3.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2"
            markerUnits="userSpaceOnUse">
            <rect width="4" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="2"
            marker-start="url(#sq)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(18)[4].r == 255, "userSpaceOnUse: the box is v-2 .. v+3");
    assert(bmp.getLine!PMColor(16)[3].a == 0, "userSpaceOnUse ignores stroke-width");

    // Inheritance: marker properties on an ancestor group reach the
    // painted child, and marker-mid="none" cancels just that one.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <g marker-start="url(#sq)" marker-mid="url(#sq)" marker-end="url(#sq)">
            <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="2"/>
        </g>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[6].r == 255 && bmp.getLine!PMColor(17)[34].r == 255,
        "marker properties inherit from ancestor groups");
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <g marker-start="url(#sq)" marker-mid="url(#sq)" marker-end="url(#sq)">
            <path d="M 6 20 L 20 20 L 34 20" marker-mid="none" stroke="black" stroke-width="2"/>
        </g>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[20].a == 0, `marker-mid="none" cancels the inherited mid`);
    assert(bmp.getLine!PMColor(17)[6].r == 255, "the other inherited markers survive");

    // The `marker` shorthand is CSS-only - NOT a presentation attribute
    // (painting-marker-04-f's top row must stay unmarked).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <g marker="url(#sq)">
            <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="2"/>
        </g>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[20].a == 0, "the marker shorthand is not a presentation attribute");

    // §11.4.1: markers hang off stroked OR filled elements - this
    // referrer has no stroke, and 07-f pins that display:none on the
    // referenced marker (directly or via an ancestor) does not hide a
    // reference-drawn marker.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2" display="none">
            <rect width="4" height="4" fill="red"/></marker>
        <g display="none">
            <marker id="sq2" markerWidth="4" markerHeight="4" refX="2" refY="2">
                <rect width="4" height="4" fill="red"/></marker>
        </g>
        <path d="M 6 20 L 20 20 L 34 20" fill="lime"
            marker-start="url(#sq)" marker-mid="url(#sq2)"/>
        </svg>`);
    // stroke-width defaults to 1 here, so the marker box is v-2 .. v+1:
    // probe row 19, not 17 as in the stroke-width-2 cases.
    assert(bmp.getLine!PMColor(19)[6].r == 255 && bmp.getLine!PMColor(19)[20].r == 255,
        "fill-only elements carry markers; display:none does not hide referenced markers");

    // A marker viewBox offset cancels against ref alignment: this
    // viewBox="20 20 10 10" marker with ref (25,25) must sit exactly
    // like an unshifted 10x10 marker with ref (5,5) - sw 2 x fit 0.2
    // x ... = 4px box centred on the vertex (painting-marker-06-f).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="off" viewBox="20 20 10 10" markerWidth="2" markerHeight="2" refX="25" refY="25">
            <rect x="20" y="20" width="10" height="10" fill="purple"/></marker>
        <path d="M 6 20 L 34 20" stroke="black" stroke-width="2" marker-start="url(#off)"/>
        </svg>`);
    immutable shifted = bmp.getLine!PMColor(18)[5];
    assert(shifted.r == 128 && shifted.b == 128 && shifted.a == 255,
        "viewBox offset cancels against refX/refY, marker centred on the vertex");

    // Broken reference: that marker paints nothing, neighbours survive.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20" stroke="black" stroke-width="2"
            marker-start="url(#nope)" marker-mid="url(#sq)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[6].a == 0, "broken reference paints nothing");
    assert(bmp.getLine!PMColor(17)[20].r == 255, "the sibling marker still paints");

    // Vertex rule: mid markers sit only at interior junctions - never a
    // moveto. The first subpath's middle vertex is the only mid; the
    // second subpath starts mid-path (26 is an interior position but a
    // moveto, so no mid), and its end (38) gets no mid either.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <path d="M 6 20 L 20 20 L 34 20 M 26 20 L 38 20" stroke="black" stroke-width="2"
            marker-mid="url(#sq)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[20].r == 255 && bmp.getLine!PMColor(17)[26].a == 0
        && bmp.getLine!PMColor(17)[38].a == 0, "mid markers only at interior junctions");

    // Markers belong to the element's paint, so the element's clip-path
    // covers them too (the scratch-composite path).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
        <marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2">
            <rect width="4" height="4" fill="red"/></marker>
        <clipPath id="ch"><rect width="25" height="40"/></clipPath>
        <path d="M 6 20 L 34 20" stroke="black" stroke-width="2"
            clip-path="url(#ch)" marker-end="url(#sq)"/>
        </svg>`);
    assert(bmp.getLine!PMColor(17)[34].a == 0, "the element's clip covers its markers too");
    assert(bmp.getLine!PMColor(19)[24].a == 255, "the stroke paints inside the clip");
}

unittest
{
    // <image> (§9.8). hrefs resolve against renderSVG's baseDir (main
    // passes the file's directory); these run from the repo root.
    immutable imgBase = "tests/w3c/suite/images/";

    // 1:1 placement is pixel exact: basn0g01.png (1-bit black and
    // white) is white at (0, 0) and black at (5, 5); missing
    // width/height fall back to the natural size.
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
        <image href="PngSuite/basn0g01.png" x="4" y="4"/>
        </svg>`, 1.0f, imgBase);
    immutable first = bmp.getLine!PMColor(4)[4];
    assert(first.r == 255 && first.g == 255 && first.b == 255 && first.a == 255,
        "1:1 image placement (white pixel)");
    immutable dark = bmp.getLine!PMColor(9)[9];
    assert(dark.r == 0 && dark.a == 255, "1:1 image placement (black pixel)");
    assert(bmp.getLine!PMColor(37)[5].a == 0, "nothing beyond the 32x32 image");

    // Scaled images sample bilinearly, matching the browsers'
    // half-pixel registration (u = x/s + 0.5/s - 0.5). At 64x32 over
    // a 32x32 image with preserveAspectRatio="none", sx is 2 and sy
    // 1: x=15 lands on natural u=7.25 and x=16 on u=7.75, straddling
    // basn0g04's row-12 step 68 -> 85 at column 8. Nearest would
    // answer (round(192*68+64*85)>>8, round(64*68+192*85)>>8) = (72, 80).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="64" height="32">
        <image href="PngSuite/basn0g04.png" width="64" height="32"
            preserveAspectRatio="none"/>
        </svg>`, 1.0f, imgBase);
    immutable edgeLo = bmp.getLine!PMColor(12)[15];
    immutable edgeHi = bmp.getLine!PMColor(12)[16];
    assert(edgeLo.r == 72 && edgeHi.r == 80, "scaled images sample bilinearly");

    // data: URI hrefs (§7.4: href is a URI, and struct-image-04-t
    // embeds a JPEG and PNG this way). A 1x1 opaque-red PNG scaled to
    // 10x10 must cover the viewport edge to edge: every device pixel
    // center maps into the half-texel border (u = x/10 + 0.05 - 0.5
    // stays in [-0.5, 0.5]), so bilinear clamps to the single pixel.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
        <image href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12P4z8DwHwAFAAH/cpxSZwAAAABJRU5ErkJggg=="
            width="10" height="10"/>
        </svg>`, 1.0f, imgBase);
    immutable dot = bmp.getLine!PMColor(5)[5];
    assert(dot.r == 255 && dot.g == 0 && dot.b == 0 && dot.a == 255,
        "data: URIs decode and draw like files");
    assert(bmp.getLine!PMColor(0)[9].a == 255, "the 1x1 tile upscales edge-to-edge");

    // xml:base (§5.1.2) rebases the subtree's hrefs.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
        <g xml:base="../images/"><image href="PngSuite/basn0g01.png"/></g>
        </svg>`, 1.0f, "tests/w3c/suite/svg/");
    assert(bmp.getLine!PMColor(5)[5].r == 0 && bmp.getLine!PMColor(5)[5].a == 255,
        "xml:base resolves relative image hrefs");

    // Broken references render nothing (§9.8): missing file, a URL
    // scheme (no network here), and a same-document fragment.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">
        <image href="no-such-file.png" width="20" height="20"/>
        <image href="http://example.com/x.png" width="20" height="20"/>
        <image href="#frag" width="20" height="20"/>
        <image width="20" height="20"/>
        </svg>`, 1.0f, imgBase);
    assert(bmp.getLine!PMColor(10)[10].a == 0, "broken image references render nothing");

    // opacity folds into the pixels (Paint color is ignored on the
    // shader path, so gradients do the same at build time): white scaled
    // to alpha 128 saves as straight white at alpha 128 (the save pass
    // unpremultiplies the device's grey-128 back).
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
        <image href="PngSuite/basn0g01.png" width="10" height="10" opacity="0.5"/>
        </svg>`, 1.0f, imgBase);
    immutable half = bmp.getLine!PMColor(0)[0];
    assert(half.a == 128 && half.r >= 250, "opacity scales the image");

    // "slice" overflows the viewport, and the viewport clips it: at
    // 64x16 over a 32x32 image the scale is 2, so unclipped content
    // would also cover row 20 of the (deliberately taller) canvas.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="64" height="40">
        <image href="PngSuite/basn0g01.png" width="64" height="16"
            preserveAspectRatio="xMidYMid slice"/>
        </svg>`, 1.0f, imgBase);
    assert(bmp.getLine!PMColor(1)[1].a == 255, "slice paints inside the viewport");
    assert(bmp.getLine!PMColor(20)[1].a == 0, "slice content clips at the viewport");

    // An <image> inside <clipPath> is not a clip shape (§14.3): it
    // contributes no geometry, so the empty clip hides the element.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
        <clipPath id="ch"><image href="PngSuite/basn0g01.png"/></clipPath>
        <rect width="40" height="40" fill="lime" clip-path="url(#ch)"/>
        </svg>`, 1.0f, imgBase);
    assert(bmp.getLine!PMColor(20)[20].a == 0, "an image is not a valid clip child");
}

unittest
{
    // A filtered container must see the bbox of its whole subtree:
    // the objectBoundingBox region of a <g> covers every child, so an
    // identity chain keeps them all (guards the FRect right/bottom vs
    // width/height constructor mix-up in the bbox union).
    auto bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="60" height="50">
        <filter id="id" filterUnits="objectBoundingBox" x="0%" y="0%" width="100%" height="100%">
            <feGaussianBlur stdDeviation="0"/>
        </filter>
        <g filter="url(#id)">
            <rect x="10" y="10" width="40" height="10" fill="blue"/>
            <rect x="10" y="25" width="40" height="10" fill="#ff0"/>
        </g>
        </svg>`);
    immutable top = bmp.getLine!PMColor(15)[30];
    immutable bot = bmp.getLine!PMColor(30)[30];
    assert(top.a == 255 && top.r == 0 && top.g == 0 && top.b > 250, "first child survives");
    assert(bot.a == 255 && bot.r > 250 && bot.g > 250 && bot.b < 5, "last child survives");

    // feBlend normal over a half-transparent flood is plain source-over
    // (the PM blend term carries the backdrop's alpha): blue 0.5 over
    // flood green 0.5 gives PM (0, 0.25, 0.5, 0.75) in linearRGB, i.e.
    // sRGB (0, 156, 213, 191), composited over white.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="60" height="50">
        <filter id="bn" filterUnits="objectBoundingBox" x="0%" y="0%" width="100%" height="100%">
            <feFlood flood-color="#0f0" flood-opacity="0.5" result="g"/>
            <feBlend in="SourceGraphic" in2="g" mode="normal"/>
        </filter>
        <rect width="60" height="50" fill="white"/>
        <rect x="10" y="10" width="40" height="30" fill="blue" opacity="0.5" filter="url(#bn)"/>
        </svg>`);
    immutable px = bmp.getLine!PMColor(25)[30];
    assert(px.a == 255, "opaque backdrop");
    assert(px.r > 60 && px.r < 68, `red is the white showing through: ${to!string(px)}`);
    assert(px.g > 177 && px.g < 185, `green straight 1/3: ${to!string(px)}`);
    assert(px.b > 219 && px.b < 227, `blue straight 2/3: ${to!string(px)}`);
}
