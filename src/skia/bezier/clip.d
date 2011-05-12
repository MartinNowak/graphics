module skia.bezier.clip;

import skia.bezier.chop, skia.bezier.curve, skia.math.clamp, skia.math.poly;
import guip.point, guip.rect;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings, std.numeric;

int clipBezier(T, size_t K, size_t MS)(ref const Point!T[K] curve, ref const Rect!T rect, ref Point!T[K][MS] clipped) {
  auto monocnt = chopMonotonic(curve, clipped);
  uint clipcnt;
  foreach(i; 0 .. monocnt)
    if (clipMonoBezier(clipped[i], rect, clipped[i])) {
      if (clipcnt != i)
        move(clipped[i], clipped[clipcnt]);
      ++clipcnt;
    }
  return clipcnt;
}

bool clipMonoBezier(T, size_t K)(ref const Point!T[K] curve, ref const Rect!T rect, ref Point!T[K] clipped) {
  assert(!rect.empty);
  return clipMonoBezierImpl!("x")(curve, rect.left, rect.right, clipped)
    && clipMonoBezierImpl!("y")(clipped, rect.top, rect.bottom, clipped);
}

bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[2] line, double lo, double hi, ref Point!T[2] clipped)
in {
  assert(monotonic!(dir)(line));
} body {

  const v0 = mixin(Format!(q{line[0].%s}, dir));
  const v1 = mixin(Format!(q{line[1].%s}, dir));

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
    if (line !is clipped)
      clipped = line;
  } else
    sliceBezier(line, s0, s1, clipped);
  return true;
}


bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[3] quad, double lo, double hi, ref Point!T[3] clipped)
in {
  //  assert(monotonic!(dir)(quad), to!string(quad));
} body {

  const v0 = mixin(Format!(q{quad[0].%s}, dir));
  const v1 = mixin(Format!(q{quad[1].%s}, dir));
  const v2 = mixin(Format!(q{quad[2].%s}, dir));

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
    if (quad !is clipped)
      clipped = quad;
  } else
    sliceBezier(quad, s0, s1, clipped);
  return true;
}


bool clipMonoBezierImpl(string dir, T)
(ref const Point!T[4] cubic, double lo, double hi, ref Point!T[4] clipped)
in {
  //  assert(monotonic!(dir)(cubic));
} body {

  const v0 = mixin(Format!(q{cubic[0].%s}, dir));
  const v1 = mixin(Format!(q{cubic[1].%s}, dir));
  const v2 = mixin(Format!(q{cubic[2].%s}, dir));
  const v3 = mixin(Format!(q{cubic[3].%s}, dir));

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
    if (cubic !is clipped)
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
  assert(clipped == [FPoint(0./6., 0./3.), FPoint(1./6, 1./3.), FPoint(2./6., 2./3.), FPoint(3./6., 3./3.)]);
}

unittest {
  FPoint[4] cubic = [FPoint(0, 0), FPoint(2, 2), FPoint(2, -2), FPoint(0, 2)];
  auto clip = FRect(0, 0, 1, 1);
  FPoint[4][5] clipped;
  auto cnt = clipBezier(cubic, clip, clipped);
  std.stdio.writeln(clipped[0 .. cnt]);
}
