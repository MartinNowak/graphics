import std.algorithm, std.ascii, std.conv, std.exception, std.file, std.getopt, std.math, std.path, std.range, std.stdio, std.string;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser, std.experimental.xml.sax;
import std.experimental.xml.interfaces : isCursor;
import graphics;
import graphics.core.fonthost;
import graphics.core.glyph;
import graphics.core.matrix;
import graphics.core.svg;

T convAttr(T)(in string[string] aa, string s, T def)
{
    if (auto p = s in aa)
        return to!T(*p);
    else
        return def;
}

// Flatten the attributes of the cursor's current element into a map.
string[string] attrs(CursorType)(ref CursorType cursor) if (isCursor!CursorType)
{
    string[string] res;
    foreach (a; cursor.attributes)
        res[a.name] = a.value;
    return res;
}

uint parseLength(string s)
{   import std.string;
    auto res = std.conv.parse!float(s);
    enum dpi = 72;
    switch (toLower(s))
    {
    case "", "px": break;
    case "cm": res *= dpi * (1.0 / 2.54); break;
    case "in": res *= dpi; break;
    case "mm": res *= dpi * (1.0 / 25.4); break;
    case "pt": res *= dpi * (1.0 / 72.0); break;
    case "pc": res *= dpi * (12.0 / 72.0); break;
    // unitless value: user space, i.e. px
    default: break;
    }
    return to!uint(res);
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

void renderSVG(string fn, float zoom)
{
    string text = cast(string)std.file.read(fn);

    // Tolerate documents without an XML declaration (SVG does not require one).
    auto c = text.lexer.parser.cursor((CursorError e) {});
    alias C = typeof(c);

    static struct Style
    {
        bool transform;
        Color cstroke, cfill=Color.Black;
        float strokeWidth=1, opacity=1, fillOpacity=1, strokeOpacity=1;

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

        // Set up the canvas and the viewport zoom (viewBox -> canvas).
        void setupRoot(in string[string] a)
        {
            // viewBox="min-x min-y width height"; when missing, user space
            // maps 1:1 to the canvas (user units are px), so the viewBox
            // defaults to the canvas dims.
            float[4] vb = [0.0f, 0.0f, 1000.0f, 1000.0f];
            if (auto p = "viewBox" in a)
            {
                parseViewBox(vb, *p);
                enforce(vb[2] > 0 && vb[3] > 0, "invalid viewBox");
            }
            else
            {
                // FIXME: <length>
                immutable wpx = float(("width" in a) ? parseLength(*("width" in a)) : 0f);
                immutable hpx = float(("height" in a) ? parseLength(*("height" in a)) : 0f);
                if (wpx > 0) vb[2] = wpx;
                if (hpx > 0) vb[3] = hpx;
            }

            // canvas size: width/height attributes, else the viewBox dims,
            // scaled by the CLI zoom factor
            // FIXME: <length>
            immutable width = float(("width" in a) ? parseLength(*("width" in a)) : vb[2]) * zoom;
            immutable height = float(("height" in a) ? parseLength(*("height" in a)) : vb[3]) * zoom;

            bmp = Bitmap(Bitmap.Config.ARGB_8888, to!uint(round(width)), to!uint(round(height)));
            canvas = new Canvas(bmp);

            // Zoom: uniformly scale the viewBox into the canvas, preserving
            // aspect ratio and centering it ("xMidYMid meet").
            immutable s = min(width / vb[2], height / vb[3]);
            immutable tx = (width - vb[2] * s) * 0.5f - vb[0] * s;
            immutable ty = (height - vb[3] * s) * 0.5f - vb[1] * s;
            Matrix zoom;
            zoom[0][0] = s;
            zoom[1][1] = s;
            zoom[0][2] = tx;
            zoom[1][2] = ty;
            canvas.matrix = zoom;
        }

        Style pushStyle(in string[string] attr)
        {
            // Default-construct the base style so every field gets its member
            // initializer (font defaults included).
            Style style = styles.length ? styles.data.back : Style();
            style.transform = false;

            void apply(string k, string v)
            {
                switch (k)
                {
                case "stroke-width":
                    style.strokeWidth = to!float(v);
                    break;

                case "fill":
                    style.cfill = color(v);
                    break;

                case "stroke":
                    style.cstroke = color(v);
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
                    style.fontSize = float(parseLength(v));
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
                        immutable w = to!int(strip(v));
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
                    transformSVG(canvas.matrix, v);
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

        void flushPath(in string[string] attr)
        {
            immutable s = pushStyle(attr);
            scope (exit) popStyle();

            // Effective paint alpha: the group `opacity` multiplies the
            // per-paint opacity (fill-opacity/stroke-opacity) and the
            // color's own alpha.
            immutable op = clamp(s.opacity, 0f, 1f);

            if (s.cstroke.a != 0)
            {
                import graphics.core.patheffect;
                auto stroked = strokePath(path, s.strokeWidth);
                Color c = s.cstroke;
                c.a = to!ubyte(round(c.a * op * clamp(s.strokeOpacity, 0f, 1f)));
                canvas.drawPath(stroked, Paint(c));
            }
            if (s.cfill.a != 0)
            {
                path.close();
                Color c = s.cfill;
                c.a = to!ubyte(round(c.a * op * clamp(s.fillOpacity, 0f, 1f)));
                canvas.drawPath(path, Paint(c));
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
            immutable s = styles.data.back;

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

            // Same effective-opacity compositing as flushPath.
            immutable op = clamp(s.opacity, 0f, 1f);

            if (s.cstroke.a != 0)
            {
                import graphics.core.patheffect;
                auto stroked = strokePath(path, s.strokeWidth);
                Color c = s.cstroke;
                c.a = to!ubyte(round(c.a * op * clamp(s.strokeOpacity, 0f, 1f)));
                canvas.drawPath(stroked, Paint(c));
            }
            if (s.cfill.a != 0)
            {
                path.close();
                Color c = s.cfill;
                c.a = to!ubyte(round(c.a * op * clamp(s.fillOpacity, 0f, 1f)));
                canvas.drawPath(path, Paint(c));
            }
            path.reset();
            textBuf = "";
        }

        // Build the path for a shape and flush it with its style.
        void shape(string tag, in string[string] a)
        {
            switch (tag)
            {
            case "rect":
                {
                    auto pt = FPoint(a.convAttr("x", 0.0f), a.convAttr("y", 0.0f));
                    auto sz = FSize(a.convAttr("width", 0.0f), a.convAttr("height", 0.0f));
                    enforce(sz.width >= 0 && sz.height >= 0);
                    auto rx = a.convAttr("rx", 0.0f);
                    auto ry = a.convAttr("ry", 0.0f);
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
                    immutable pt = FPoint(a.convAttr("cx", 0.0f), a.convAttr("cy", 0.0f));
                    immutable r = a.convAttr("r", 0.0f);
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
                    immutable pt = FPoint(a.convAttr("cx", 0.0f), a.convAttr("cy", 0.0f));
                    immutable rad = FSize(a.convAttr("rx", 0.0f), a.convAttr("ry", 0.0f));
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
                    immutable p0 = FPoint(a.convAttr("x0", 0.0f), a.convAttr("y0", 0.0f));
                    immutable p1 = FPoint(a.convAttr("x1", 0.0f), a.convAttr("y1", 0.0f));

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
                // nested <svg> roots and any other container markup
                break;
            }
        }

        // Returns true if the element opens a style (<g>, <text>, <tspan>).
        bool element(string tag, in string[string] a)
        {
            switch (tag)
            {
            case "g":
                pushStyle(a);
                return true;

            case "text":
                inText = true;
                textBuf = "";
                // x/y (default 0/0), optionally shifted by dx/dy.
                textPos = FPoint(a.convAttr("x", 0.0f) + a.convAttr("dx", 0.0f),
                                a.convAttr("y", 0.0f) + a.convAttr("dy", 0.0f));
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
                if ("x" in a)
                    textPos.x = a.convAttr("x", 0.0f);
                if ("y" in a)
                    textPos.y = a.convAttr("y", 0.0f);
                textPos.x += a.convAttr("dx", 0.0f);
                textPos.y += a.convAttr("dy", 0.0f);
                pushStyle(a);
                return true;

            default:
                shape(tag, a);
                return false;
            }
        }

        void onElementStart(ref C node)
        {
            if (!inRoot)
            {
                if (node.name == "svg")
                {
                    inRoot = true;
                    setupRoot(attrs(node));
                }
                return;
            }
            element(node.name, attrs(node));
        }

        void onElementEmpty(ref C node)
        {
            if (!inRoot)
            {
                if (node.name == "svg")
                {
                    inRoot = true;
                    setupRoot(attrs(node));
                }
                return;
            }
            if (element(node.name, attrs(node)))
            {
                if (node.name == "text")
                    inText = false;  // <text/>: no run to flush
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
            if (!inRoot)
                return;
            switch (node.name)
            {
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
    sax.setSource(text);
    sax.processDocument();
    enforce(sax.handler.inRoot, "no <svg> root element");

    sax.handler.bmp.save(fn.setExtension("png"));
}

// Usage: svg [-z|--zoom <factor>] <file.svg> ...
// -z/--zoom scales the canvas (and thus the rendering) uniformly.
void main(string[] args)
{
    float zoom = 1.0f;
    auto rslt = getopt(args, "zoom|z", "scale the canvas (default: 1)", &zoom);
    if (rslt.helpWanted)
        defaultGetoptPrinter("Render SVG files to PNG files.", rslt.options);
    enforce(zoom > 0, "zoom factor must be positive");
    foreach (file; args[1 .. $])
        renderSVG(file, zoom);
}
