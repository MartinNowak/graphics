module graphics.svg.render;

import std.algorithm, std.ascii, std.conv, std.exception, std.math, std.range, std.string;
import graphics;
import graphics.core.fonthost;
import graphics.core.glyph;
import graphics.core.matrix;
import graphics.core.patheffect;
import graphics.core.path_detail.path_measure;
import graphics.core.pmcolor : PMColor, alphaMul, alphaScale;
import graphics.core.shader : Shader, ColorShader;
import graphics.svg.color;
import graphics.svg.core;
import graphics.svg.gradient;
import graphics.svg.parser;
import graphics.svg.pattern;

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

        // Inherited fill rule (SVG 1.1 11.2.4); clip-rule waits on clip
        // paths themselves.
        Path.FillRule fillRule = Path.FillRule.NonZero;

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

            case "clip-rule": // clip paths arrive with the document model
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
        Paint fillP = resolvePaint(true, s, op * clamp(s.fillOpacity, 0f, 1f), bbox);
        Paint strokeP = resolvePaint(false, s, op * clamp(s.strokeOpacity, 0f, 1f), bbox);

        immutable doFill = s.visible && (fillP.shader !is null || fillP.color.a != 0);
        immutable doStroke = s.visible
            && (strokeP.shader !is null || strokeP.color.a != 0) && s.strokeWidth > 0;

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

        if (doFill)
        {
            // Subpaths are implicitly closed at raster time
            // (Path.applyFilled); no path.close() needed here.
            // path.reset() does not clear fillRule, so assign per flush.
            path.fillRule = s.fillRule;
            canvas.drawPath(path, fillP);
        }
        if (doStroke)
            canvas.drawPath(stroked, strokeP);
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
        Paint fillP = resolvePaint(true, s, op * clamp(s.fillOpacity, 0f, 1f), bbox);
        Paint strokeP = resolvePaint(false, s, op * clamp(s.strokeOpacity, 0f, 1f), bbox);

        immutable doFill = s.visible && (fillP.shader !is null || fillP.color.a != 0);
        immutable doStroke = s.visible
            && (strokeP.shader !is null || strokeP.color.a != 0) && s.strokeWidth > 0;

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

        if (doFill)
        {
            // Glyph outlines carry explicit Close verbs; the fill
            // closure (applyFilled) covers any straggler subpath.
            // Pin the rule to non-zero on purpose (the comment above
            // this block is right): convention-directed TrueType/CFF
            // outlines fill the same under both rules, and `path` is
            // shared with flushPath whose fillRule assignment above
            // would otherwise leak into text.
            path.fillRule = Path.FillRule.NonZero;
            canvas.drawPath(path, fillP);
        }
        if (doStroke)
            canvas.drawPath(stroked, strokeP);
        path.reset();
        textBuf = "";
    }

    // Build the path for a shape and flush it with its style.
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
Bitmap renderSVG(string source, float zoom = 1.0f)
{
    Renderer r;
    r.doc = parseSVG(source);
    r.zoom = zoom;
    r.walk(0); // the document pseudo-root; inRoot latches at the <svg>
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
            immutable dev = abs(pxc.r / 255.0 - cov);
            immutable twoCrossings = (px == 6 && py == 3) || (px == 4 && py == 6);
            if (twoCrossings)
            {
                ++badCells;
                assert(pxc.r >= 240, text("tie cell not near full coverage at ", [px, py]));
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
    // opaque white lands at alpha ~ 255*0.25 = 64, premultiplied ~64.
    bmp = renderSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="10" y1="0" y2="0">
            <stop offset="0" stop-color="white" stop-opacity="0.5"/>
            <stop offset="1" stop-color="white" stop-opacity="0.5"/>
        </linearGradient></defs>
        <rect width="10" height="10" fill="url(#g)" fill-opacity="0.5"/>
        </svg>`);
    auto px = bmp.getLine!PMColor(5)[5];
    assert(px.a >= 60 && px.a <= 68 && px.r >= 60 && px.r <= 68, to!string([px.a, px.r]));
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
