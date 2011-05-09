module skia.bezier.curve;

import guip.point;
import skia.math.clamp, skia.math.poly;
import std.algorithm;

Point!T evalBezier(T)(ref const Point!T[2] line, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  return line[0] * (1 - t) + line[1] * t;
}

Point!T evalBezier(T)(ref const Point!T[3] quad, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  const mt = 1 - t;
  return quad[0] * (mt * mt) + quad[1] * (2 * mt * t) + quad[2] * (t * t);
}

Point!T evalBezier(T)(ref const Point!T[4] cubic, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
  const mt = 1 - t;
  return cubic[0] * (mt * mt * mt) + cubic[1] * (3 * mt * mt * t)
    + cubic[2] * (3 * mt * t * t) + cubic[3] * (t * t * t);
}


Vector!T evalBezierDer(T)(ref const Point!T[2] line, double t) {
  return line[1] - line[0];
}

Vector!T evalBezierDer(T)(ref const Point!T[3] quad, double t) {
  return ((quad[1] - quad[0]) * (1 - t) + (quad[2] - quad[1]) * t) * 2;
}

Vector!T evalBezierDer(T)(ref const Point!T[4] cubic, double t) {
  const mt = 1 - t;
  return ((cubic[1] - cubic[0]) * (mt * mt) + (cubic[2] - cubic[1]) * (2 * mt * t)
          + (cubic[3] - cubic[2]) * (t * t)) * 3;
}


// creates a line from two points
void constructBezier(T)(Point!T p0, Point!T p1, ref Point!T[2] line) {
  line[0] = p0;
  line[1] = p1;
}

// creates a quadratic bezier from two points and the derivative a t=0
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, ref Point!T[3] quad) {
  quad[0] = p0;
  quad[1] = p0 + 0.5 * d0;
  quad[$-1] = p1;
}

// creates a cubic bezier from two points and the derivatives a t=0 and t=1
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, Vector!T d1, ref Point!T[4] cubic) {
  cubic[0] = p0;
  cubic[1] = p0 + (1./3.) * d0;
  cubic[2] = p1 - (1./3.) * d1;
  cubic[$-1] = p1;
}


/**
 * calculates t parameter of quad x extrema
 * Returns: number of found extremas (0 or 1)
 */
int bezierExtremaX(T)(ref const Point!T[3] quad, ref double t) {
  const b = quad[1].x - quad[0].x;
  const a = quad[2].x - quad[1].x - b;
  if (polyRoots(a, b, t) && fitsIntoRange!("()")(t, 0, 1))
    return 1;
  return 0;
}

/**
 * calculates t parameter of quad x extrema
 * Returns: number of found extremas (0 or 1)
 */
int bezierExtremaY(T)(ref const Point!T[3] quad, ref double t) {
  const b = quad[1].y - quad[0].y;
  const a = quad[2].y - quad[1].y - b;
  if (polyRoots(a, b, t) && fitsIntoRange!("()")(t, 0, 1))
    return 1;
  return 0;
}

int bezierExtrema(T)(ref const Point!T[3] quad, ref double[2] ts) {
  uint idx;
  idx += bezierExtremaX(quad, ts[idx]);
  idx += bezierExtremaY(quad, ts[idx]);
  return idx;
}


/**
 * calculates t parameters of cubic x extrema
 * Returns: number of found extremas (0 or 1)
 */
int bezierExtremaX(T)(ref const Point!T[4] cubic, ref double[2] ts) {
  const d10 = cubic[1].x - cubic[0].x;
  const d21 = cubic[2].x - cubic[1].x;
  const d32 = cubic[3].x - cubic[2].x;
  return cubicPolyRoots(d10, d21, d32, ts);
}

/**
 * calculates t parameters of cubic x extrema
 * Returns: number of found extremas (0 or 1)
 */
int bezierExtremaY(T)(ref const Point!T[4] cubic, ref double[2] ts) {
  const d10 = cubic[1].y - cubic[0].y;
  const d21 = cubic[2].y - cubic[1].y;
  const d32 = cubic[3].y - cubic[2].y;
  return cubicPolyRoots(d10, d21, d32, ts);
}

int bezierExtrema(T)(ref const Point!T[4] cubic, ref double[4] ts) {
  uint idx;
  idx += bezierExtremaX(cubic, ts[idx .. idx + 2]);
  idx += bezierExtremaY(cubic, ts[idx .. idx + 2]);
  return idx;
}

private int cubicPolyRoots(double d10, double d21, double d32, ref double[2] ts) {
  const a = d10 - 2 * d21 + d32;
  const b = 2 * (d21 - d10);
  const c = d10;

  uint rootcnt = polyRoots(a, b, c, ts);
  if (rootcnt > 1 && !fitsIntoRange!("()")(ts[0], 0, 1)) {
    --rootcnt;
    swap(ts[0], ts[1]);
  }
  if (rootcnt > 0 && !fitsIntoRange!("()")(ts[rootcnt - 1], 0, 1))
    --rootcnt;
  return rootcnt;
}

version(unittest) import std.math;
unittest {
  FPoint[3] quad = [FPoint(0, 0), FPoint(1, 1), FPoint(0, 0)];
  double t;
  assert(bezierExtremaY(quad, t) > 0);
  assert(approxEqual(t, 0.5));
  assert(bezierExtremaX(quad, t) > 0);
  assert(approxEqual(t, 0.5));
}
