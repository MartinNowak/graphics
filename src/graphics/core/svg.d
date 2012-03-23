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

        mat = m * mat;
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
            pts[0] = parse!FPoint(s) + path.points[$-1];
            goto Lmove;

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
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            pts[1] = parse!FPoint(s) + rel;
            pts[2] = parse!FPoint(s) + rel;
            goto Lcubic;

        case 'S':
            pts[0] = path.points[$-1];
            pts[1] = parse!FPoint(s);
            pts[2] = parse!FPoint(s);
            goto Lscubic;
        case 's':
            immutable rel = path.points[$-1];
            pts[0] = pts[0];
            pts[1] = parse!FPoint(s) + rel;
            pts[2] = parse!FPoint(s) + rel;
            goto Lscubic;

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
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            pts[1] = parse!FPoint(s) + rel;
            goto Lquad;

        case 'T':
            pts[0] = path.points[$-1];
            pts[1] = parse!FPoint(s);
            goto Lsquad;
        case 't':
            immutable rel = path.points[$-1];
            pts[0] = rel;
            pts[1] = pts[0] + rel;
            goto Lsquad;

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
            immutable rel = path.points[$-1];
            pts[0] = parse!FPoint(s) + rel;
            auto xrad = parse!float(s);
            auto larc = parse!bool(s);
            auto sweep = parse!bool(s);
            pts[1] = parse!FPoint(s) + rel;
            goto Larc;

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
    if (!s.empty)
    {   bool res = void;
        if (s[0] == '0') res = false;
        else if (s[0] == '1') res = true;
        else goto Lerror;
        return s = s[1 .. $], res;
    }
 Lerror: throw new ConvException("expected '0'|'1' not "~s);
}
