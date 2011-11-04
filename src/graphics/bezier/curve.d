module graphics.bezier.curve;

import guip.point;
import graphics.math.clamp, graphics.math.poly;
import std.algorithm, std.metastrings;

void bezToPoly(T)(ref T[2] line)
{
    immutable c0 = -line[0] + line[1];
    immutable c1 = line[0];
    line[0] = c0;
    line[1] = c1;
}

void bezToPoly(T)(ref T[3] quad)
{
    immutable c0 = quad[0] - 2 * quad[1] + quad[2];
    immutable c1 = 2 * (-quad[0] + quad[1]);
    immutable c2 = quad[0];
    quad[0] = c0;
    quad[1] = c1;
    quad[2] = c2;
}

void bezToPoly(T)(ref T[4] cubic)
{
    immutable c0 = -cubic[0] + 3 * (cubic[1] - cubic[2]) + cubic[3];
    immutable c1 = 3 * (cubic[0] - 2 * cubic[1] + cubic[2]);
    immutable c2 = 3 * (-cubic[0] + cubic[1]);
    immutable c3 = cubic[0];
    cubic[0] = c0;
    cubic[1] = c1;
    cubic[2] = c2;
    cubic[3] = c3;
}

void bezToPoly(T, size_t K)(ref const Point!T[K] curve, ref T[K] x, ref T[K] y)
{
    foreach(i; SIota!(0, K))
    {
        x[i] = curve[i].x;
        y[i] = curve[i].y;
    }
    bezToPoly(x);
    bezToPoly(y);
}

Point!T evalBezier(T, size_t K)(ref const Point!T[K] bez, double t)
{
    assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
    T[K] x=void, y=void;
    bezToPoly(bez, x, y);
    return Point!T(poly!T(x, t), poly!T(y, t));
}

Point!T evalBezierDer(T, size_t K)(ref const Point!T[K] bez, double t)
{
    assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
    T[K] x=void, y=void;
    bezToPoly(bez, x, y);
    return Point!T(polyDer!T(x, t), polyDer!T(y, t));
}

/*
 * Struct to hold bezier construction state.
 */
struct BezierCState(T, size_t K)
{
    static if (K == 2)
        void constructBezier(ref Point!T[K] line)
    {
        line[0] = p0;
        line[1] = p1;
    }

    static if (K == 3)
        void constructBezier(ref Point!T[K] quad)
    {
        quad[1] = quad[0] = p0;
        quad[1].x += 0.5 * d0.x;
        quad[1].y += 0.5 * d0.y;
        quad[2] = p1;
    }

    static if (K == 4)
        void constructBezier(ref Point!T[K] cubic)
    {
        cubic[1] = cubic[0] = p0;
        cubic[1].x += (1./3.) * d0.x;
        cubic[1].y += (1./3.) * d0.y;
        cubic[3] = cubic[2] = p1;
        cubic[2].x -= (1./3.) * d1.x;
        cubic[2].y -= (1./3.) * d1.y;
    }

    Point!T p0; // start point
    Point!T p1; // end point
    static if (K >= 3)
    {
        Vector!T d0; // derivative at start
        Vector!T d1; // derivative at end
    }
}

// creates a line from two points
void constructBezier(T)(Point!T p0, Point!T p1, ref Point!T[2] line)
{
    BezierCState!(T, 2)(p0, p1).constructBezier(line);
}

// creates a quadratic bezier from two points and the derivative a t=0
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, ref Point!T[3] quad)
{
    BezierCState!(T, 3)(p0, p1, d0).constructBezier(quad);
}

// creates a cubic bezier from two points and the derivatives a t=0 and t=1
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, Vector!T d1, ref Point!T[4] cubic)
{
    BezierCState!(T, 4)(p0, p1, d0, d1).constructBezier(cubic);
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
