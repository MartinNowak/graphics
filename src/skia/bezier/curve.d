module skia.bezier.curve;

import guip.point;
import skia.math.clamp, skia.math.poly;
import std.algorithm, std.metastrings;

Point!T evalBezier(T)(ref const Point!T[2] line, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));

  const x0 = -line[0].x + line[1].x;
  const x1 = line[0].x;

  const y0 = -line[0].y + line[1].y;
  const y1 = line[0].y;

  return Point!T(x0 * t + x1, y0 * t + y1);
}

Point!T evalBezier(T)(ref const Point!T[3] quad, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0));

  const x0 = quad[0].x - 2 * quad[1].x + quad[2].x;
  const x1 = 2 * (-quad[0].x + quad[1].x);
  const x2 = quad[0].x;

  const y0 = quad[0].y - 2 * quad[1].y + quad[2].y;
  const y1 = 2 * (-quad[0].y + quad[1].y);
  const y2 = quad[0].y;

  return Point!T((x0 * t + x1) * t + x2, (y0 * t + y1) * t + y2);
}

Point!T evalBezier(T)(ref const Point!T[4] cubic, double t) {
  assert(fitsIntoRange!("[]")(t, 0.0, 1.0), to!string(t));

  const x0 = -cubic[0].x + 3 * (cubic[1].x - cubic[2].x) + cubic[3].x;
  const x1 = 3 * (cubic[0].x - 2 * cubic[1].x + cubic[2].x);
  const x2 = 3 * (-cubic[0].x + cubic[1].x);
  const x3 = cubic[0].x;

  const y0 = -cubic[0].y + 3 * (cubic[1].y - cubic[2].y) + cubic[3].y;
  const y1 = 3 * (cubic[0].y - 2 * cubic[1].y + cubic[2].y);
  const y2 = 3 * (-cubic[0].y + cubic[1].y);
  const y3 = cubic[0].y;

  return Point!T(((x0 * t + x1) * t + x2) * t + x3, ((y0 * t + y1) * t + y2) * t + y3);
}


Vector!T evalBezierDer(T)(ref const Point!T[2] line, double t) {
  return Vector!T(line[1].x - line[0].x, line[1].y - line[0].y);
}

Vector!T evalBezierDer(T)(ref const Point!T[3] quad, double t) {
  const x0 = quad[0].x - 2 * quad[1].x + quad[2].x;
  const x1 = quad[1].x - quad[0].x;

  const y0 = quad[0].y - 2 * quad[1].y + quad[2].y;
  const y1 = quad[1].y - quad[0].y;
  return Vector!T(2 * (x0 * t + x1), 2 * (y0 * t + y1));
}

Vector!T evalBezierDer(T)(ref const Point!T[4] cubic, double t) {
  const x0 =  - cubic[0].x + 3 * (cubic[1].x - cubic[2].x) + cubic[3].x;
  const x1 = 2 * (cubic[0].x - 2 * cubic[1].x + cubic[2].x);
  const x2 = cubic[1].x - cubic[0].x;

  const y0 =  - cubic[0].y + 3 * (cubic[1].y - cubic[2].y) + cubic[3].y;
  const y1 = 2 * (cubic[0].y - 2 * cubic[1].y + cubic[2].y);
  const y2 = cubic[1].y - cubic[0].y;
  return Vector!T(3 * ((x0 * t + x1) * t + x2), 3 * ((y0 * t + y1) * t + y2));
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
  uint cnt;
  cnt += bezierExtremaX(quad, ts[cnt]);
  cnt += bezierExtremaY(quad, ts[cnt]);
  sort(ts[0 .. cnt]);
  return cnt;
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
  double[2] tx = void;
  auto xcnt = bezierExtremaX(cubic, tx);
  foreach(i; 0 .. xcnt)
    ts[i] = tx[i];
  double[2] ty = void;
  auto ycnt = bezierExtremaY(cubic, ty);
  foreach(i; 0 .. ycnt)
    ts[xcnt + i] = ty[i];
  sort(ts[0 .. xcnt + ycnt]);
  return xcnt + ycnt;
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

bool monotonic(string dir, T, size_t K)(Point!T[K] curve) {
  foreach(i; 1 .. K-1) {
    const rel = mixin(Format!(
                        q{(curve[i].%s - curve[i-1].%s) * (curve[i+1].%s - curve[i].%s)},
                        dir, dir, dir, dir));
    if (rel !>= 0)
      return false;
  }
  return true;
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
