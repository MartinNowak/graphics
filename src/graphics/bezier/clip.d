module graphics.bezier.clip;

import graphics.bezier.chop, graphics.bezier.curve, graphics.math.clamp, graphics.math.poly;
import guip.point, guip.rect;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings, std.numeric;

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

bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[2] line, double lo, double hi, ref Point!T[2] clipped)
in {
  //  assert(monotonic!(dir)(line));
  assert(hi > lo);
} body {

  const v0 = mixin(Format!(q{line[0].%s}, dir));
  const v1 = mixin(Format!(q{line[1].%s}, dir));

  if (v0 == v1) {
    if (fitsIntoRange!("[]")(v0, lo, hi))
      goto NoChange;
    return false;
  }

  const rel0 = (lo - v0) / (v1 - v0);
  const t0 = clampToRange(rel0, 0, 1);
  const rel1 = (hi - v0) / (v1 - v0);
  const t1 = clampToRange(rel1, 0, 1);

  if (t0 !<> t1)
    return false;

  assert(t0 <>= t1);
  assert(fitsIntoRange!("[]")(t0, 0, 1));
  assert(fitsIntoRange!("[]")(t1, 0, 1));
  const s0 = min(t0, t1);
  const s1 = max(t0, t1);
  if (s0 == 0 && s1 == 1) {
  NoChange:
    if (&line != &clipped)
      clipped = line;
  } else
    sliceBezier(line, s0, s1, clipped);
  return true;
}


bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[3] quad, double lo, double hi, ref Point!T[3] clipped)
in {
  //  assert(monotonic!(dir)(quad), to!string(quad));
  assert(hi > lo);
} body {

  const v0 = mixin(Format!(q{quad[0].%s}, dir));
  const v1 = mixin(Format!(q{quad[1].%s}, dir));
  const v2 = mixin(Format!(q{quad[2].%s}, dir));

  if (v0 == v2) {
    if (fitsIntoRange!("[]")(v0, lo, hi))
      goto NoChange;
    return false;
  }

  double intersection(double v0, double v1, double v2, double val) {
    double ts[2];
    auto cnt = polyRoots(v0 - 2 * v1 + v2, -2 * v0 + 2 * v1, v0 - val, ts);
    foreach(t; ts[0 .. cnt])
      if (fitsIntoRange!("[]")(t, 0, 1))
        return t;
    assert(0);
  }

  const rel0 = (lo - v0) / (v2 - v0);
  const t0 = fitsIntoRange!("()")(rel0, 0, 1) ? intersection(v0, v1, v2, lo) : clampToRange(rel0, 0, 1);
  const rel1 = (hi - v0) / (v2 - v0);
  const t1 = fitsIntoRange!("()")(rel1, 0, 1) ? intersection(v0, v1, v2, hi) : clampToRange(rel1, 0, 1);

  if (t0 !<> t1)
    return false;

  assert(t0 <>= t1);
  assert(fitsIntoRange!("[]")(t0, 0, 1));
  assert(fitsIntoRange!("[]")(t1, 0, 1));

  const s0 = min(t0, t1);
  const s1 = max(t0, t1);
  if (s0 == 0 && s1 == 1) {
  NoChange:
    if (&quad != &clipped)
      clipped = quad;
  } else
    sliceBezier(quad, s0, s1, clipped);
  return true;
}


bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[4] cubic, double lo, double hi, ref Point!T[4] clipped)
in {
  //  assert(monotonic!(dir)(cubic), to!string(cubic));
  assert(hi > lo);
} body {

  const v0 = mixin(Format!(q{cubic[0].%s}, dir));
  const v1 = mixin(Format!(q{cubic[1].%s}, dir));
  const v2 = mixin(Format!(q{cubic[2].%s}, dir));
  const v3 = mixin(Format!(q{cubic[3].%s}, dir));

  if (v0 == v3)
    return fitsIntoRange!("[]")(v0, lo, hi);

  double intersection(double v0, double v1, double v2, double v3, double val) {
    auto evaldg = (double t) {
      const mt = 1-t;
      return mt * mt * mt * v0 + 3 * mt * mt * t * v1 + 3 * mt * t * t * v2 + t * t * t * v3 - val;
    };
    auto r = findRoot(
        evaldg, 0.0, 1.0,
        v0 - val, v3 - val,
        (double lo, double hi) { return hi - lo < 1e-3; });
    return fabs(r[2]) !> fabs(r[3]) ? r[0] : r[1];
  }

  const rel0 = (lo - v0) / (v3 - v0);
  const t0 = fitsIntoRange!("()")(rel0, 0, 1) ? intersection(v0, v1, v2, v3, lo) : clampToRange(rel0, 0, 1);
  const rel1 = (hi - v0) / (v3 - v0);
  const t1 = fitsIntoRange!("()")(rel1, 0, 1) ? intersection(v0, v1, v2, v3, hi) : clampToRange(rel1, 0, 1);

  if (t0 !<> t1)
    return false;

  assert(t0 <>= t1);
  assert(fitsIntoRange!("[]")(t0, 0, 1));
  assert(fitsIntoRange!("[]")(t1, 0, 1));

  const s0 = min(t0, t1);
  const s1 = max(t0, t1);
  if (s0 == 0 && s1 == 1) {
    if (&cubic != &clipped)
      clipped = cubic;
  } else
    sliceBezier(cubic, s0, s1, clipped);
  return true;
}

version(unittest) import std.stdio;
unittest {
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

unittest {
  FPoint[3] quad = [FPoint(0, 0), FPoint(0.5, 1.0), FPoint(2, 2)];
  auto clip = FRect(0, 0, 1, 1);
  FPoint[3] clipped;
  assert(clipMonoBezier(quad, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(0.25, 0.5), FPoint(0.75, 1)]);
}

unittest {
  FPoint[4] cubic = [FPoint(0./3., 0./3.), FPoint(1./3, 2./3.), FPoint(2./3., 4./3.), FPoint(3./3., 6./3.)];
  auto clip = FRect(0, 0, 1, 1);
  FPoint[4] clipped;
  assert(clipMonoBezier(cubic, clip, clipped));
  assert(equal!q{a.approxEqual(b)}(
           clipped[],
           [FPoint(0./6., 0./3.), FPoint(1./6, 1./3.), FPoint(2./6., 2./3.), FPoint(3./6., 3./3.)]));
}

unittest {
  FPoint[4] cubic = [FPoint(0, 0), FPoint(2, 2), FPoint(2, -2), FPoint(0, 2)];
  auto clip = FRect(0, 0, 1, 1);
  FPoint[4][5] clipped;
  auto cnt = clipBezier(cubic, clip, clipped);
}
