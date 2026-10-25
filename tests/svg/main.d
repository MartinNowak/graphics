import std.algorithm, std.ascii, std.conv, std.exception, std.file, std.getopt, std.math, std.path, std.range, std.stdio, std.string;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser, std.experimental.xml.sax;
import std.experimental.xml.interfaces : isCursor;
import graphics;
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

    static struct Style { bool transform; Color cstroke, cfill=Color.Black; float strokeWidth=1; }

    // Push-style traversal of the SVG document: the SAX parser walks the whole
    // document (prolog, DTD, elements) and calls the matching `on*` handler
    // for each node in document order, so there is no manual cursor driving.
    struct Handler
    {
        Bitmap bmp;
        Canvas canvas;
        Style[] styles;
        Path path;
        float zoom;
        bool inRoot;

        // Set up the canvas and the viewport zoom (viewBox -> canvas).
        void setupRoot(in string[string] a)
        {
            // viewBox="min-x min-y width height"; fall back to a fixed viewBox
            // when it is missing.
            float[4] vb = [0.0f, 0.0f, 1000.0f, 1000.0f];
            if (auto p = "viewBox" in a)
            {
                parseViewBox(vb, *p);
                enforce(vb[2] > 0 && vb[3] > 0, "invalid viewBox");
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
            Style style = styles.length ? styles[$-1] : Style.init;
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
            if (styles[$-1].transform)
                canvas.restore();
            --styles.length;
        }

        void flushPath(in string[string] attr)
        {
            immutable s = pushStyle(attr);
            scope (exit) popStyle();
            if (s.cstroke.a != 0)
            {
                import graphics.core.patheffect;
                auto stroked = strokePath(path, s.strokeWidth);
                canvas.drawPath(stroked, Paint(s.cstroke));
            }
            if (s.cfill.a != 0)
            {
                path.close();
                canvas.drawPath(path, Paint(s.cfill));
            }
            path.reset();
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

        // Returns true if the element opens a style (<g>).
        bool element(string tag, in string[string] a)
        {
            if (tag == "g")
            {
                pushStyle(a);
                return true;
            }
            shape(tag, a);
            return false;
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
                popStyle();  // <g/>: close the style immediately
        }

        void onElementEnd(ref C node)
        {
            if (inRoot && node.name == "g")
                popStyle();
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
