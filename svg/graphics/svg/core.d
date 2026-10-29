module graphics.svg.core;

import std.ascii, std.algorithm, std.conv, std.functional, std.math, std.range;

import guip.point;
import graphics.core.matrix;

// Returns false when the list contains a `matrix(0 0 0 0 e f)`, which per
// SVG 1.1 disables rendering of the element and its children.
bool transformSVG(ref Matrix mat, string s)
{
    bool degenerate;
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
                m.setTranslate(x, 0); // SVG 1.1 §9.5: translate(tx) => ty = 0
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
        {
            // SVG skewX(a) is affine: x' = x + y·tan(a). The library's
            // setSkewX puts the tangent in the w-row, which under the
            // matrix's projective point mapping divides by (1 + x·tan) -
            // not an SVG skew. Build the matrix by hand instead.
            immutable t = tan(parse!float(s) * PI / 180.0f);
            m.reset();
            m[0][1] = t;
            break;
        }

        case "skewY":
        {
            // SVG skewY(a): y' = y + x·tan(a) (same reasoning as skewX).
            immutable t = tan(parse!float(s) * PI / 180.0f);
            m.reset();
            m[1][0] = t;
            break;
        }

        case "matrix":
            // SVG matrix(a b c d e f): x' = ax + cy + e, y' = bx + dy + f.
            immutable a = parse!float(s), b = parse!float(s), cc = parse!float(s);
            immutable d = parse!float(s), e = parse!float(s), f = parse!float(s);
            m[0][0] = a; m[0][1] = cc; m[0][2] = e;
            m[1][0] = b; m[1][1] = d;  m[1][2] = f;
            m[2][0] = 0;
            m[2][1] = 0;
            m[2][2] = 1;
            // SVG 1.1: a matrix with all-zero a-f "shall disable the element"
            // (the transform is not rendered).
            if (a == 0 && b == 0 && cc == 0 && d == 0)
                degenerate = true;
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
    return !degenerate;
}

/// Parse one arc endpoint flag pair ("0 1", "1,0", ...).
private bool parseArcFlag(ref string s)
in(s.length)
{
    import std.exception : enforce;
    skipCW(s);
    enforce(s.length && (s[0] == '0' || s[0] == '1'), "invalid arc flag");
    immutable res = s[0] == '1';
    s = s[1 .. $];
    skipCW(s);
    return res;
}

/// Append the SVG elliptical arc `d`-grammar segment from the path's current
/// point to `to` (SVG 1.1 F.6.5: endpoint -> centre parameterisation, then
/// cubic approximation of <= 90 degree segments).
private void addArc(Path)(ref Path path, float rx, float ry, float xRotation,
                         bool largeArc, bool arcSweep, FPoint to)
{
    import std.math : abs, cos, sin, sqrt, tan, ceil, PI, atan2;
    import std.algorithm : max;
    import std.exception : enforce;

    immutable from = path.points[$-1];
    rx = abs(rx);
    ry = abs(ry);
    if (rx == 0 || ry == 0 || from == to)
    {
        if (from != to)
            path.lineTo(to);
        return;
    }

    immutable phi = xRotation * PI / 180.0f;
    immutable cosP = cos(phi), sinP = sin(phi);
    auto dx = (from.x - to.x) / 2, dy = (from.y - to.y) / 2;
    auto x1p = cosP * dx + sinP * dy;
    auto y1p = -sinP * dx + cosP * dy;

    // Radii too small to reach the endpoints: scale them up (F.6.5 step 6).
    auto lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1)
    {
        immutable r = sqrt(lam);
        rx *= r;
        ry *= r;
    }

    auto num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    auto den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    auto coef = sqrt(max(num / den, 0.0f));
    if (largeArc == arcSweep)
        coef = -coef;
    immutable cxp = coef * rx * y1p / ry;
    immutable cyp = -coef * ry * x1p / rx;
    immutable cx = cosP * cxp - sinP * cyp + (from.x + to.x) / 2;
    immutable cy = sinP * cxp + cosP * cyp + (from.y + to.y) / 2;

    immutable theta = atan2((y1p - cyp) / ry, (x1p - cxp) / rx);
    immutable theta2 = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx);
    float dTheta = theta2 - theta;
    if (arcSweep && dTheta <= 0)
        dTheta += 2 * PI;
    else if (!arcSweep && dTheta >= 0)
        dTheta -= 2 * PI;

    // Cubics of at most a quarter turn each; the error for a 90 degree
    // segment is ~2.7e-4 of the radius, plenty for the rasteriser.
    immutable segs = max(1, cast(int) ceil(abs(dTheta) / (PI / 2) - 1e-3f));
    immutable step = dTheta / segs;
    immutable alpha = 4.0f / 3.0f * tan(step / 4);
    for (int i = 0; i < segs; ++i)
    {
        immutable t0 = theta + step * i, t1 = t0 + step;
        auto p0 = FPoint(cx + rx * cos(t0), cy + ry * sin(t0));
        auto p3 = FPoint(cx + rx * cos(t1), cy + ry * sin(t1));
        auto t0d = FPoint(-rx * sin(t0), ry * cos(t0));
        auto t1d = FPoint(-rx * sin(t1), ry * cos(t1));
        auto p1 = p0 + FPoint(alpha * t0d.x, alpha * t0d.y);
        auto p2 = p3 - FPoint(alpha * t1d.x, alpha * t1d.y);
        auto spin = (FPoint p) {
            auto px = p.x - cx, py = p.y - cy;
            return FPoint(cx + cosP * px - sinP * py, cy + sinP * px + cosP * py);
        };
        // Land the final segment exactly on the specified endpoint; the
        // trig-rebuilt one differs from it by float noise.
        immutable last = i + 1 == segs;
        path.cubicTo(spin(p1), spin(p2), last ? to : spin(p3));
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
            pts[1] = parse!FPoint(s) + rel;
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
        case 'a':
        {
            immutable rel = c == 'a' ? path.points[$-1] : FPoint(0, 0);
            immutable rx = parse!float(s), ry = parse!float(s);
            immutable xRotation = parse!float(s);
            immutable largeArc = parseArcFlag(s), sweep = parseArcFlag(s);
            immutable to = parse!FPoint(s) + rel;
            addArc(path, rx, ry, xRotation, largeArc, sweep, to);
            break;
        }
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
    skipCW(s);
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
    assert(near(m * FPoint(0, 0), FPoint(10, 0)), "translate(tx) => ty = 0 (§9.5)");

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

    // SVG skews are affine shears (not the library's w-row projective skew):
    m.reset();
    transformSVG(m, "skewX(45)");
    assert(!m.perspective);
    assert(near(m * FPoint(0, 1), FPoint(1, 1)));
    m.reset();
    transformSVG(m, "skewY(45)");
    assert(!m.perspective);
    assert(near(m * FPoint(1, 0), FPoint(1, 1)));

    m.reset();
    assert(transformSVG(m, "matrix(1 2 3 4 5 6)"));
    // x' = ax + cy + e, y' = bx + dy + f
    assert(near(m * FPoint(1, 1), FPoint(9, 12)));

    // SVG 1.1: an all-zero matrix disables the element.
    m.reset();
    assert(!transformSVG(m, "matrix(0 0 0 0 10 10)"));
    assert(near(m * FPoint(1, 1), FPoint(10, 10))); // matrix itself still applies

    // transform list: "A B" applies B first, then A
    m.reset();
    transformSVG(m, "translate(10, 0) scale(2)");
    assert(near(m * FPoint(1, 1), FPoint(12, 2)));

    assertThrown(transformSVG(m, "bogus(1)"));
}

unittest
{
    import graphics.core.path : Path;
    import std.math : abs;

    bool near(FPoint a, FPoint b) { return abs(a.x - b.x) < 1e-3f && abs(a.y - b.y) < 1e-3f; }

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

    // elliptical arcs: F.6.5 endpoint->centre conversion, <= 90 degree cubics
    path = Path.init;
    addSVGPath(path, "M 10 30 A 20 20 0 0 1 50 30");
    assert(path.verbs[1 .. $].length >= 2);
    foreach (v; path.verbs[1 .. $])
        assert(v == Path.Verb.Cubic);
    assert(near(path.points[$-1], FPoint(50, 30)));
    // The sweep=1 half circle bulges through (30, 10); the first cubic covers
    // theta 180..270, so its Bezier midpoint sits near theta 225 = (15.86, 15.86).
    auto p = path.points;
    immutable bx = (p[0].x + 3*p[1].x + 3*p[2].x + p[3].x) / 8;
    immutable by = (p[0].y + 3*p[1].y + 3*p[2].y + p[3].y) / 8;
    assert(abs(bx - 15.858f) < 0.02f && abs(by - 15.858f) < 0.02f);

    // zero radii degenerate to a straight line
    path = Path.init;
    addSVGPath(path, "M 0 0 A 0 5 0 0 1 10 10");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line]);
    assert(path.points[$-1] == FPoint(10, 10));

    // radii too small to span the gap are scaled up (F.6.5 step 6)
    path = Path.init;
    addSVGPath(path, "M 0 0 A 3 3 0 0 1 10 0");
    assert(path.verbs[1 .. $].length >= 2 && path.points[$-1] == FPoint(10, 0));

    // relative arcs and implicit command repetition
    path = Path.init;
    addSVGPath(path, "M 10 30 a 20 20 0 0 1 40 0 a 20 20 0 0 0 40 0");
    assert(path.points[$-1] == FPoint(90, 30));
    assert(path.verbs.length >= 5);

    // a zero-length arc (from == to) draws nothing (F.6.5 step 3)
    path = Path.init;
    addSVGPath(path, "M 0 0 A 5 5 0 0 0 0 0 L 10 0");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line]);

    // an empty subpath closed by Z then reopened must not assert
    path = Path.init;
    addSVGPath(path, "M 5 5 Z M 10 10 L 20 20");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line]);
    assert(path.points == [FPoint(10, 10), FPoint(20, 20)]);
}

unittest
{
    import graphics.core.path : Path;

    Path path;
    addSVGPolyLine(path, "0,0 10,0 10,10");
    assert(path.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line]);
    assert(path.points == [FPoint(0, 0), FPoint(10, 0), FPoint(10, 10)]);
}
