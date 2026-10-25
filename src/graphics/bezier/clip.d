module graphics.bezier.clip;

import graphics.bezier.chop, graphics.bezier.curve, graphics.math.clamp, graphics.math.poly;
import guip.point, guip.rect;
import std.algorithm, std.conv, std.exception, std.math, std.numeric, std.string;

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

    if (isClose(a.x, clip.left) || isClose(a.x, clip.right))
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
  if (curve[0] != curve[$-1]
      && clipMonoBezierImpl!("x")(curve, rect.left, rect.right, clipped)
      && clipMonoBezierImpl!("y")(clipped, rect.top, rect.bottom, clipped)) {
      // sliceBezier rebuilds endpoints as poly(t); the float evaluation
      // can land just outside the rect. Snap them back in.
      // (The y clip re-derives x coordinates too, so this must run
      // after both dimension clips, not inside clipMonoBezierImpl.)
      clipped[0].x = clampToRange(clipped[0].x, rect.left, rect.right);
      clipped[0].y = clampToRange(clipped[0].y, rect.top, rect.bottom);
      clipped[$-1].x = clampToRange(clipped[$-1].x, rect.left, rect.right);
      clipped[$-1].y = clampToRange(clipped[$-1].y, rect.top, rect.bottom);
      return true;
  }
  return false;
}

bool clipMonoBezierImpl(string dir, T, size_t K)
(ref const Point!T[K] curve, double lo, double hi, ref Point!T[K] clipped)
in
{
    assert(hi > lo);
}
body
{
    // a monotone segment has at most one critical point (a real wiggle);
    // exact, unlike the polygon-based monotonic test which is only a
    // sufficient condition
    debug assert(criticalCount!(dir, T, K)(curve) <= 1);

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

    // each lo/hi crossing is a single root in (0, 1) on a monotone segment
    static double intersection(ref const T[K] coeffs, double val)
    {
        double y0 = coeffs[$-1] - val;   // f(0), exact — no eval needed
        assert(y0 != 0);                 // val strictly interior (guaranteed by guard below)
        return findRootNewton!(T, K, true)(coeffs, val, 0.0, 1.0, y0, 1e-6);
    }

    immutable rlen = 1.0 / (v[K-1] - v[0]);
    immutable relLo = (lo - v[0]) * rlen;
    immutable relHi = (hi - v[0]) * rlen;

    double t0 = clampToRange(relLo, 0, 1);
    double t1 = clampToRange(relHi, 0, 1);

    static if (K > 2)
    {
        // refine only when the boundary value is strictly interior;
        // endpoints give t = 0 / t = 1 directly (the y0 == 0 case)
        bool polyd = false;
        if (t0 > 0.0 && t0 < 1.0)        // relLo strictly interior
        {
            if (!polyd) { bezToPoly(v); polyd = true; }
            t0 = intersection(v, lo);
        }
        if (t1 > 0.0 && t1 < 1.0)        // relHi strictly interior
        {
            if (!polyd) { bezToPoly(v); polyd = true; }
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

unittest
{
    // Regression (butterfly.svg): cubic with P2 == P3. Float subdivision
    // shifts the endpoint critical points slightly inside (0, 1) on the
    // chopped segments; clipMonoBezierImpl's monotonicity tripwire must not
    // fire on them. Clip with a rectangle containing the whole curve:
    // nothing is cut, every segment is passed through as-is.
    FPoint[4] cubic = [FPoint(323.62, 177.12), FPoint(335.12, 168.12),
                       FPoint(297.12, 168.12), FPoint(297.12, 168.12)];
    auto clip = FRect(297.0, 168.0, 336.0, 178.0);
    FPoint[4][5] clipped;
    assert(clipBezier(cubic, clip, clipped) == 2);
}

unittest
{
    // monotone cubic; clip boundaries coincide with the segment endpoint
    // values (lo == v[0], hi == v[K-1]) — exercises the no-refinement path
    FPoint[4] cubic = [FPoint(0, 0), FPoint(1, 1), FPoint(2, 2), FPoint(3, 4)];
    FPoint[4] clipped;

    // both boundaries on both dimensions: no refinement, whole curve
    auto clip = FRect(0, 0, 3, 4);
    assert(clipMonoBezier(cubic, clip, clipped));
    assert(clipped == cubic);

    // lo == y(0) exactly: t = 0 is not refined, endpoint kept exactly
    clip = FRect(0, 0, 1, 1);
    assert(clipMonoBezier(cubic, clip, clipped));
    assert(clipped[0] == FPoint(0, 0));
    assert(isClose(clipped[$-1].y, 1.0));
    assert(clipped[$-1].x > 0.0 && clipped[$-1].x < 1.0);
}

unittest
{
    // cubic whose derivative roots are near-coincident (thin middle part):
    // y'(t) = 30(t - 0.48)(t - 0.52); reference y(0.48) = 1.24416,
    // y(0.52) = 1.24384; x(t) = t.
    FPoint[4] cubic = [FPoint(0, 0), FPoint(1./3., 2.496), FPoint(2./3., -0.008), FPoint(1, 2.488)];
    FPoint[4][5] monos;
    auto cnt = chopMonotonic(cubic, monos);
    assert(cnt == 3);
    assert(isClose(monos[0][$-1].y, 1.24416));
    assert(isClose(monos[1][0].y, 1.24416));
    assert(isClose(monos[1][$-1].y, 1.24384));
    assert(isClose(monos[2][0].y, 1.24384));

    // clip to y in [0, 2]: segments 1 and 2 stay whole, segment 3 is cut
    // where y(t) = 2 at t = 0.9238 (x(t) = t)
    FPoint[4][5] clipped;
    auto clip = FRect(0, 0, 1, 2);
    auto ccnt = clipBezier(cubic, clip, clipped);
    assert(ccnt == 3);
    assert(clipped[0] == monos[0]);
    assert(clipped[1] == monos[1]);
    assert(isClose(clipped[ccnt - 1][$-1].x, 0.9238));
    assert(isClose(clipped[ccnt - 1][$-1].y, 2.0));
}
