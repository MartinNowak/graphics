import std.algorithm, std.conv, std.exception, std.file, std.path, std.range, std.stdio, std.string;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser;
import std.experimental.xml.interfaces : isCursor, XMLKind;
import graphics;
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

void renderSVG(string fn)
{
    string text = cast(string)std.file.read(fn);

    // Drive the pull parser with a single recursive function, instead of
    // re-wiring element handlers into every sub-parser: `visit` handles an
    // element, descends into its children via `enter`, and the sibling loop
    // advances past each child's subtree with `next`.
    auto c = text.lexer.parser.cursor;

    // Skip the prolog (<?xml ...?>, the DTD, comments) to reach the root element.
    c.enter;
    while (c.kind != XMLKind.elementStart)
    {
        if (c.kind == XMLKind.dtdStart)
        {
            c.next();  // skip to the DTD end (sets the nextFailed latch)
            c.exit();  // clear the latch without moving
            continue;
        }
        if (!c.next())
            enforce(false, "no root element");
    }
    enforce(c.name == "svg");

    uint width = 1000, height = 1000;
    // FIXME: <length>
    {
        auto a = attrs(c);
        if (auto p = "width" in a) width = parseLength(*p);
        if (auto p = "height" in a) height = parseLength(*p);
    }

    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, width, height);
    auto canvas = new Canvas(bmp);

    static struct Style { bool transform; Color cstroke, cfill=Color.Black; float strokeWidth=1; }
    Style[] styles;

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

    Path path;

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

    alias C = typeof(c);

    void visit(ref C cur)
    {
        auto tag = cur.name;
        auto a = attrs(cur);
        bool styled = false;

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

        case "g":
            styled = true;
            pushStyle(a);
            break;

        default:
            // nested <svg> roots and any other container markup
            break;
        }

        if (cur.enter())
        {
            do
            {
                if (cur.kind == XMLKind.elementStart || cur.kind == XMLKind.elementEmpty)
                    visit(cur);
            } while (cur.next());
            cur.exit();
        }

        if (styled)
            popStyle();
    }

    visit(c);

    bmp.save(fn.setExtension("png"));
}

void main(string[] args)
{
    foreach(file; args[1 .. $])
        renderSVG(file);
}
