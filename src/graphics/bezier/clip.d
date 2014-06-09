module graphics.bezier.clip;

import graphics.bezier.chop, graphics.bezier.curve, graphics.math.clamp, graphics.math.poly;
import guip.point, guip.rect;
import std.algorithm, std.conv, std.exception, std.math, std.numeric;

/*
 * Splits a bezier curve into monotonic segments and clip each one to
 * fit into $(D_Param clip).  Calls ($D_Param dg) for each of these
 * segments. Calls $(D_Param borderdg) for border segments connecting
 * the monotone segments.
 */
void clippedMonotonic(T, size_t K)(
    ref const Point!T[K] curve,
    Rect!T clip,
    scope void delegate(ref const Point!T[K] monoSeg) dg,
    scope void delegate(ref const Point!T[2] line) borderdg)
{
    Point!T[K][1 + 2*(K-2)] monos = void;
    auto monocnt = clipBezier(curve, clip, monos);

    Point!T pos = curve[0];
    for (size_t i = 0; i < monocnt; ++i)
    {
        if (pos != monos[i][0])
            joinSegment(pos, monos[i][0], clip, borderdg);
        dg(monos[i]);
        pos = monos[i][$-1];
    }
    if (pos != curve[$-1])
        joinSegment(pos, curve[$-1], clip, borderdg);
}

private void joinSegment(T)(Point!T a, Point!T b, Rect!T clip, scope void delegate(ref const Point!T[2]) dg)
{
    a.x = clampToRange(a.x, clip.left, clip.right);
    a.y = clampToRange(a.y, clip.top, clip.bottom);
    b.x = clampToRange(b.x, clip.left, clip.right);
    b.y = clampToRange(b.y, clip.top, clip.bottom);
    auto diff = b - a;
    Point!T[2] line = void;
    line[0] = a;
    line[1] = a;

    if (approxEqual(a.x, clip.left) || approxEqual(a.x, clip.right))
    {
        // y first
        if (diff.y != 0)
        {
            line[1].y += diff.y;
            dg(line);
            line[0].y += diff.y;
        }
        if (diff.x != 0)
        {
            line[1].x += diff.x;
            dg(line);
            line[0].x += diff.x;
        }
    }
    else
    {
        // x first
        if (diff.x != 0)
        {
            line[1].x += diff.x;
            dg(line);
            line[0].x += diff.x;
        }
        if (diff.y != 0)
        {
            line[1].y += diff.y;
            dg(line);
            line[0].y += diff.y;
        }
    }
}

int clipBezier(T, size_t K, size_t MS)(ref const Point!T[K] curve, ref const Rect!T rect, ref Point!T[K][MS] clipped) {
  auto monocnt = chopMonotonic(curve, clipped);
  uint clipcnt;
  foreach(i; 0 .. monocnt)
    if (clipMonoBezier(clipped[i], rect, clipped[i])) {
      if (i != clipcnt)
        clipped[clipcnt] = clipped[i];
      ++clipcnt;
    }
  return clipcnt;
}

bool clipMonoBezier(T, size_t K)(ref const Point!T[K] curve, ref const Rect!T rect, ref Point!T[K] clipped) {
  assert(!rect.empty);
  return
    curve[0] != curve[$-1]
    && clipMonoBezierImpl!("x")(curve, rect.left, rect.right, clipped)
    && clipMonoBezierImpl!("y")(clipped, rect.top, rect.bottom, clipped);
}

bool clipMonoBezierImpl(string dir, T, size_t K)
(ref const Point!T[K] curve, double lo, double hi, ref Point!T[K] clipped)
in
{
    assert(hi > lo);
}
body
{
    T[K] v = void;
    foreach(i; SIota!(0, K))
        v[i] = __traits(getMember, curve[i], dir);

    if (v[0] == v[K-1])
    {
        if (fitsIntoRange!("[]")(v[0], lo, hi))
        {
            if (&curve != &clipped)
                clipped = curve;
            return true;
        }
        else
            return false;
    }

    static if (K == 3)
    {
        static double intersection(ref const T[K] coeffs, double val)
        {
            double ts[2] = void;
            auto cnt = polyRoots(coeffs[0], coeffs[1], coeffs[2] - val, ts);
            switch (cnt)
            {
            case 2:
                if (fitsIntoRange!("[]")(ts[1], 0, 1))
                    return ts[1];
                else
                    goto case;

            case 1:
                assert(fitsIntoRange!("[]")(ts[0], 0, 1));
                return ts[0];

            default:
                assert(0, std.string.format("Too many roots %s.", cnt));
            }
        }
    }
    else static if (K == 4)
    {
        static double intersection(ref const T[4] coeffs, double val)
        {
            double dg(double t) { return poly!(T)(coeffs, t) - val; }
            return findRootIllinois(&dg, 0.0, 1.0);
        }
    }

    immutable rlen = 1.0 / (v[K-1] - v[0]);
    immutable relLo = (lo - v[0]) * rlen;
    immutable relHi = (hi - v[0]) * rlen;

    double t0 = clampToRange(relLo, 0, 1);
    double t1 = clampToRange(relHi, 0, 1);

    static if (K > 2)
    {
        if (t0 == relLo)
        {
            bezToPoly(v);
            t0 = intersection(v, lo);
            if (t1 == relHi)
                goto LSkipPoly;
        }
        else if (t1 == relHi)
        {
            bezToPoly(v);
        LSkipPoly:
            t1 = intersection(v, hi);
        }
    }

    if (t0 == t1)
        return false;

    assert(fitsIntoRange!("[]")(t0, 0-1e-6, 1+1e-6));
    assert(fitsIntoRange!("[]")(t1, 0-1e-6, 1+1e-6));

    // TODO: avoid extra clamping
    immutable s0 = clampToRange(min(t0, t1), 0, 1);
    immutable s1 = clampToRange(max(t0, t1), 0, 1);
    if (s0 == 0 && s1 == 1)
    {
        if (&curve != &clipped)
            clipped = curve;
    }
    else
    {
        sliceBezier(curve, s0, s1, clipped);
    }
    return true;
}

version(unittest) import std.stdio;
unittest
{
    FPoint[2] line = [FPoint(0, 0), FPoint(2, 2)];
    auto clip = FRect(0, 0, 1, 1);
    FPoint[2] clipped;
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(1, 1)]);
    line[1] = FPoint(2, 1);
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(1, 0.5)]);
    line[1] = FPoint(1, 2);
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(0.5, 1)]);

    line = [FPoint(-2, -2), FPoint(2, 2)];
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(1, 1)]);

    line = [FPoint(-2, -1), FPoint(2, -0.5)];
    assert(!clipMonoBezier(line, clip, clipped));

    line = [FPoint(-2, -1), FPoint(2, 1)];
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(1, 0.5)]);

    line = [FPoint(0, 0), FPoint(1, 1)];
    assert(clipMonoBezier(line, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(1, 1)]);
}

unittest
{
    FPoint[3] quad = [FPoint(0, 0), FPoint(0.5, 1.0), FPoint(2, 2)];
    auto clip = FRect(0, 0, 1, 1);
    FPoint[3] clipped;
    assert(clipMonoBezier(quad, clip, clipped));
    assert(clipped == [FPoint(0, 0), FPoint(0.25, 0.5), FPoint(0.75, 1)]);
}

unittest
{
    FPoint[4] cubic = [FPoint(0./3., 0./3.), FPoint(1./3, 2./3.), FPoint(2./3., 4./3.), FPoint(3./3., 6./3.)];
    auto clip = FRect(0, 0, 1, 1);
    FPoint[4] clipped;
    assert(clipMonoBezier(cubic, clip, clipped));
    assert(equal!q{a.approxEqual(b)}(
               clipped[],
               [FPoint(0./6., 0./3.), FPoint(1./6, 1./3.), FPoint(2./6., 2./3.), FPoint(3./6., 3./3.)]));
}

unittest
{
    FPoint[4] cubic = [FPoint(0, 0), FPoint(2, 2), FPoint(2, -2), FPoint(0, 2)];
    auto clip = FRect(0, 0, 1, 1);
    FPoint[4][5] clipped;
    auto cnt = clipBezier(cubic, clip, clipped);
}
