module graphics.svg;

import std.algorithm, std.ascii, std.conv, std.exception, std.math, std.range, std.string;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser, std.experimental.xml.sax;
import std.experimental.xml.interfaces : isCursor;
import graphics;
import graphics.core.fonthost;
import graphics.core.glyph;
import graphics.core.matrix;
import graphics.core.patheffect;
import graphics.core.path_detail.path_measure;
import graphics.core.pmcolor : PMColor;
import graphics.svg.color;
import graphics.svg.core;

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

// Flatten the attributes of the cursor's current element into a map.
string[string] attrs(CursorType)(ref CursorType cursor) if (isCursor!CursorType)
{
    string[string] res;
    foreach (a; cursor.attributes)
        res[a.name] = a.value;
    return res;
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

// Parses `source` and renders it into a fresh Bitmap.
Bitmap renderSVG(string source, float zoom = 1.0f)
{
    // Tolerate documents without an XML declaration (SVG does not require one).
    auto c = source.lexer.parser.cursor((CursorError e) {});
    alias C = typeof(c);

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

    // Push-style traversal of the SVG document: the SAX parser walks the whole
    // document (prolog, DTD, elements) and calls the matching `on*` handler
    // for each node in document order, so there is no manual cursor driving.
    struct Handler
    {
        Bitmap bmp;
        Canvas canvas;
        Appender!(Style[]) styles;
        Path path;
        float zoom;
        bool inRoot;

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

        // > 0 while inside a subtree that must not paint: <defs>, <clipPath>,
        // ..., or a display="none" element. Counts start tags so the matching
        // end tags can skip symmetrically.
        int skipDepth;

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
                    if (equalCase(v, "currentColor"))
                        style.fillIsCurrent = true;
                    else
                    {
                        Color c;
                        if (parsePaint(v, c))
                            style.cfill = c;
                    }
                    break;

                case "stroke":
                    if (equalCase(v, "currentColor"))
                        style.strokeIsCurrent = true;
                    else
                    {
                        Color c;
                        if (parsePaint(v, c))
                            style.cstroke = c;
                    }
                    break;

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
                    // Handled by the element handlers as a whole-subtree skip;
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
            Color fillC = s.fillIsCurrent ? s.curColor : s.cfill;
            Color strokeC = s.strokeIsCurrent ? s.curColor : s.cstroke;
            fillC.a = to!ubyte(round(fillC.a * op * clamp(s.fillOpacity, 0f, 1f)));
            strokeC.a = to!ubyte(round(strokeC.a * op * clamp(s.strokeOpacity, 0f, 1f)));

            immutable doFill = s.visible && fillC.a != 0;
            immutable doStroke = s.visible && strokeC.a != 0 && s.strokeWidth > 0;

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
                canvas.drawPath(path, Paint(fillC));
            }
            if (doStroke)
                canvas.drawPath(stroked, Paint(strokeC));
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
            Color fillC = s.fillIsCurrent ? s.curColor : s.cfill;
            Color strokeC = s.strokeIsCurrent ? s.curColor : s.cstroke;
            fillC.a = to!ubyte(round(fillC.a * op * clamp(s.fillOpacity, 0f, 1f)));
            strokeC.a = to!ubyte(round(strokeC.a * op * clamp(s.strokeOpacity, 0f, 1f)));

            immutable doFill = s.visible && fillC.a != 0;
            immutable doStroke = s.visible && strokeC.a != 0 && s.strokeWidth > 0;

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
                canvas.drawPath(path, Paint(fillC));
            }
            if (doStroke)
                canvas.drawPath(stroked, Paint(strokeC));
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
                    immutable p0 = FPoint(a.convLen("x0", 0.0f, lc, RefAxis.width),
                                          a.convLen("y0", 0.0f, lc, RefAxis.height));
                    immutable p1 = FPoint(a.convLen("x1", 0.0f, lc, RefAxis.width),
                                          a.convLen("y1", 0.0f, lc, RefAxis.height));

                    path.moveTo(p0);
                    path.lineTo(p1);
                    flushPath(a);
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
                // <a>, <switch> and any other container markup
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

        // Elements whose entire content is reference material: never painted
        // directly (clip paths, gradients, markers ...), plus non-graphical
        // and deferred-profile markup.
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
            case "g":
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

        void onElementStart(ref C node)
        {
            if (skipDepth)
            {
                ++skipDepth;
                return;
            }
            if (!inRoot)
            {
                if (node.name == "svg")
                {
                    inRoot = true;
                    setupRoot(attrs(node));
                }
                return;
            }
            auto a = attrs(node);
            if (isNonRendering(node.name) || a.get("display", "") == "none")
            {
                ++skipDepth;
                return;
            }
            element(node.name, a);
        }

        void onElementEmpty(ref C node)
        {
            if (skipDepth)
                return;
            if (!inRoot)
            {
                if (node.name == "svg")
                {
                    inRoot = true;
                    setupRoot(attrs(node));
                }
                return;
            }
            auto a = attrs(node);
            if (isNonRendering(node.name) || a.get("display", "") == "none")
                return;
            if (element(node.name, a))
            {
                if (node.name == "text")
                    inText = false;  // <text/>: no run to flush
                if (node.name == "svg")
                    closeViewport(); // closes the style too
                else
                    popStyle();  // <g/>: close the style immediately
            }
        }

        void onText(ref C node)
        {
            if (inText)
                textBuf ~= normalizeText(node.content);
        }

        void onCDataSection(ref C node)
        {
            if (inText)
                textBuf ~= normalizeText(node.content);
        }

        void onElementEnd(ref C node)
        {
            if (skipDepth)
            {
                --skipDepth;
                return;
            }
            if (!inRoot)
                return;
            switch (node.name)
            {
            case "svg":
                if (viewportDepth) // the root <svg> did not push a viewport
                    closeViewport();
                break;

            case "g":
                popStyle();
                break;

            case "text", "tspan":
                if (inText)
                {
                    flushText();
                    popStyle();  // close the style opened at element start
                    if (node.name == "text")
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
    }

    auto sax = c.saxParser!(Handler);
    sax.handler.zoom = zoom;
    sax.setSource(source);
    sax.processDocument();
    enforce(sax.handler.inRoot, "no <svg> root element");

    return sax.handler.bmp;
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
