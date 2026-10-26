module graphics.core.svg;

import std.ascii, std.algorithm, std.conv, std.functional, std.range;

import guip.point;
import graphics.core.matrix;

void transformSVG(ref Matrix mat, string s)
{
    skipW(s);
    while (s.length)
    {
        Matrix m = void;

        auto name = s[0 .. $ - find!(not!isAlpha)(s).length];
        s = find(s[name.length .. $], '(')[1 .. $];
        switch (name)
        {
        case "translate":
            immutable x = parse!float(s);
            if (s[0] == ')')
                m.setTranslate(x, x);
            else
                m.setTranslate(x, parse!float(s));
            break;

        case "scale":
            immutable x = parse!float(s);
            if (s[0] == ')')
                m.setScale(x, x);
            else
                m.setScale(x, parse!float(s));
            break;

        case "rotate":
            immutable ang = parse!float(s);
            if (s[0] == ')')
                m.setRotate(ang);
            else
            {
                immutable px = parse!float(s);
                immutable py = parse!float(s);
                m.setRotate(ang, px, py);
            }
            break;

        case "skewX":
            m.setSkewX(parse!float(s));
            break;

        case "skewY":
            m.setSkewY(parse!float(s));
            break;

        case "matrix":
            m[0][0] = parse!float(s);
            m[0][1] = parse!float(s);
            m[0][2] = parse!float(s);
            m[1][0] = parse!float(s);
            m[1][1] = parse!float(s);
            m[1][2] = parse!float(s);
            m[2][0] = 0;
            m[2][1] = 0;
            m[2][2] = 1;
            break;

        default:
            throw new Exception("unexpected transformation "~s);
        }
        assert(s[0] == ')');
        s = s[1 .. $];
        skipCW(s);

        // Accumulate left-to-right so the list product stays outermost:
        // a transform list "A B" applies as matrix A*B (B to the point first),
        // and the incoming `mat` (parent CTM, e.g. the viewport zoom) must
        // remain the outermost factor.
        mat = mat * m;
    }
}

void addSVGPath(Path)(ref Path path, string s)
{
    static immutable mask =
    {
        uint res;
        foreach(c; "mzlhvcsqta")
            res |= (1 << c - 'a');
        return res;
    }();

    FPoint[3] pts=void;
    skipCW(s);
    char c;
    while (!s.empty)
    {
        auto n = s[0]|0x20;
        if (n >= 'a' && n <= 'z' && mask & (1 << n - 'a'))
        {   c = s[0]; s = s[1 .. $];
            skipCW(s);
        }

        switch (c)
        {
        default: assert(0);

        case 'M':
            c = 'L'; // implicit lineto
            pts[0] = parse!FPoint(s);
            goto Lmove;
        case 'm':
            c = 'l'; // implicit lineto
        {
            immutable p0 = parse!FPoint(s);
            //! a relative moveto on an empty path is absolute (SVG 1.1, "rendering errors")
            pts[0] = path.points.length ? p0 + path.points[$-1] : p0;
            goto Lmove;
        }

        Lmove:
            path.moveTo(pts[0]);
            break;

        case 'Z', 'z':
            path.close();
            break;

        case 'L':
            pts[0] = parse!FPoint(s);
            goto Lline;
        case 'l':
            pts[0] = parse!FPoint(s) + path.points[$-1];
            goto Lline;
        case 'H':
            pts[0] = FPoint(parse!float(s), path.points[$-1].y);
            goto Lline;
        case 'h':
            pts[0] = path.points[$-1];
            pts[0].x += parse!float(s);
            goto Lline;
        case 'V':
            pts[0] = FPoint(path.points[$-1].x, parse!float(s));
            goto Lline;
        case 'v':
            pts[0] = path.points[$-1];
            pts[0].y += parse!float(s);
            goto Lline;

        Lline:
            path.lineTo(pts[0]);
            break;

        case 'C':
            pts[0] = parse!FPoint(s);
            pts[1] = parse!FPoint(s);
            pts[2] = parse!FPoint(s);
            goto Lcubic;
        case 'c':
        {
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            pts[1] = parse!FPoint(s) + rel;
            pts[2] = parse!FPoint(s) + rel;
            goto Lcubic;
        }

        case 'S':
            pts[0] = path.points[$-1];
            pts[1] = parse!FPoint(s);
            pts[2] = parse!FPoint(s);
            goto Lscubic;
        case 's':
        {
            immutable rel = path.points[$-1];
            pts[0] = pts[0];
            pts[1] = parse!FPoint(s) + rel;
            pts[2] = parse!FPoint(s) + rel;
            goto Lscubic;
        }

        Lscubic:
            if (!path.verbs.empty && path.verbs[$-1] == Path.Verb.Cubic)
                pts[1] += path.points[$-1] - path.points[$-2];
            goto Lcubic;

        Lcubic:
            path.cubicTo(pts[0], pts[1], pts[2]);
            break;

        case 'Q':
            pts[0] = parse!FPoint(s);
            pts[1] = parse!FPoint(s);
            goto Lquad;
        case 'q':
        {
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            pts[1] = parse!FPoint(s) + rel;
            goto Lquad;
        }

        case 'T':
            pts[0] = path.points[$-1];
            pts[1] = parse!FPoint(s);
            goto Lsquad;
        case 't':
        {
            immutable rel = path.points[$-1];
            pts[0] = rel;
            pts[1] = pts[0] + rel;
            goto Lsquad;
        }

        Lsquad:
            if (!path.verbs.empty && path.verbs[$-1] == Path.Verb.Quad)
                pts[0] += path.points[$-1] - path.points[$-2];
            goto Lquad;

        Lquad:
            path.quadTo(pts[0], pts[1]);
            break;

        case 'A':
            pts[0] = parse!FPoint(s);
            auto xrad = parse!float(s);
            auto larc = parse!bool(s);
            auto sweep = parse!bool(s);
            pts[1] = parse!FPoint(s);
            goto Larc;

        case 'a':
        {
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            auto xrad = parse!float(s);
            auto larc = parse!bool(s);
            auto sweep = parse!bool(s);
            pts[1] = parse!FPoint(s) + rel;
            goto Larc;
        }

        Larc:
            // BUG: need to reimplement arcTo
            path.arcTo(pts[0], pts[1]);
            break;
        }
    }
}

void addSVGPolyLine(Path)(ref Path path, string s)
{
    skipCW(s);
    auto pt = parse!FPoint(s);
    path.moveTo(pt);
    while (!s.empty)
        path.lineTo(parse!FPoint(s));
}

private:

static void skipW(ref string s)
{
    s = find!(a => !isWhite(a))(s);
}

static void skipCW(ref string s)
{
    s = find!(a => a != ',' && !isWhite(a))(s);
}

static T parse(T)(ref string s)
{
    immutable res = std.conv.parse!T(s);
    skipCW(s);
    return res;
}

static Point!T parse(T:Point!T)(ref string s)
{
    Point!T pt=void;
    pt.x = parse!T(s);
    pt.y = parse!T(s);
    return pt;
}

static bool parse(T:bool)(ref string s)
{
    skipCW(s);
    if (!s.empty)
    {   bool res = void;
        if (s[0] == '0') res = false;
        else if (s[0] == '1') res = true;
        else goto Lerror;
        s = s[1 .. $];
        skipCW(s);
        return res;
    }
 Lerror: throw new ConvException("expected '0'|'1' not "~s);
}

unittest
{
    import graphics.core.path : Path;
    import std.exception : assertThrown;
    import std.math : abs;

    bool near(FPoint a, FPoint b) { return abs(a.x - b.x) < 1e-4f && abs(a.y - b.y) < 1e-4f; }

    Matrix m;
    transformSVG(m, "translate(10)");
    assert(near(m * FPoint(0, 0), FPoint(10, 10)));

    m.reset();
    transformSVG(m, "translate(10, 20)");
    assert(near(m * FPoint(1, 2), FPoint(11, 22)));

    m.reset();
    transformSVG(m, "scale(2)");
    assert(near(m * FPoint(3, 4), FPoint(6, 8)));

    m.reset();
    transformSVG(m, "scale(2, 3)");
    assert(near(m * FPoint(1, 1), FPoint(2, 3)));

    m.reset();
    transformSVG(m, "rotate(90)");
    assert(near(m * FPoint(1, 0), FPoint(0, 1)));

    m.reset();
    transformSVG(m, "rotate(90, 5, 5)");
    assert(near(m * FPoint(5, 5), FPoint(5, 5)));

    m.reset();
    transformSVG(m, "skewX(0.5)");
    assert(m.perspective);
    m.reset();
    transformSVG(m, "skewY(0.5)");
    assert(m.perspective);

    m.reset();
    transformSVG(m, "matrix(1 2 3 4 5 6)");
    assert(near(m * FPoint(1, 1), FPoint(6, 15)));

    // transform list: "A B" applies B first, then A
    m.reset();
    transformSVG(m, "translate(10, 0) scale(2)");
    assert(near(m * FPoint(1, 1), FPoint(12, 2)));

    assertThrown(transformSVG(m, "bogus(1)"));
}

unittest
{
    import graphics.core.path : Path;

    Path path;
    addSVGPath(path, "M 0 0 L 10 10 H 20 V 0 Z");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line, Path.Verb.Line, Path.Verb.Close]);
    assert(path.points == [FPoint(0, 0), FPoint(10, 10), FPoint(20, 10), FPoint(20, 0)]);

    // implicit lineto after moveto
    path = Path.init;
    addSVGPath(path, "M 0 0 5 5 10 0");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line]);
    assert(path.points == [FPoint(0, 0), FPoint(5, 5), FPoint(10, 0)]);

    // relative commands
    path = Path.init;
    addSVGPath(path, "m 1 1 l 2 2 h 3 v -4");
    assert(path.points == [FPoint(1, 1), FPoint(3, 3), FPoint(6, 3), FPoint(6, -1)]);

    // cubics and smooth cubics
    path = Path.init;
    addSVGPath(path, "M 0 0 C 1 1 2 2 3 3 S 4 4 5 5");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Cubic, Path.Verb.Cubic]);
    // S seeds the first handle with the current point and shifts the parsed
    // handle by the previous cubic's leg reflection.
    assert(path.points == [FPoint(0, 0), FPoint(1, 1), FPoint(2, 2), FPoint(3, 3),
                           FPoint(3, 3), FPoint(5, 5), FPoint(5, 5)]);

    // quads and smooth quads
    path = Path.init;
    addSVGPath(path, "M 0 0 Q 1 1 2 2 T 3 3");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Quad, Path.Verb.Quad]);
    // T reflects the previous control point (1,1) through (2,2) into (3,3)
    assert(path.points[$-2] == FPoint(3, 3));
    assert(path.points[$-1] == FPoint(3, 3));

    // elliptical arc command produces at least one move
    path = Path.init;
    addSVGPath(path, "M 0 0 A 5 5 0 0 1 10 10");
    assert(path.verbs.length >= 1 && path.verbs[0] == Path.Verb.Move);
}

unittest
{
    import graphics.core.path : Path;

    Path path;
    addSVGPolyLine(path, "0,0 10,0 10,10");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line]);
    assert(path.points == [FPoint(0, 0), FPoint(10, 0), FPoint(10, 10)]);
}
