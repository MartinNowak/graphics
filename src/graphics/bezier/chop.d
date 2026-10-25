module graphics.bezier.chop;

import graphics.bezier.curve, graphics.math.clamp, graphics.math.poly;
import guip.point;
import std.algorithm;

/**
 * Split bezier curve with de Castlejau algorithm.
 */
Point!T[K][2] splitBezier(size_t K, T)(in Point!T[K] pts, double t) {

  Point!T[K][2] result = void;
  result[1] = pts;
  splitBezier(result[0], result[1], t);
  return result;
}

// use ref here to allow uninitliazed arrays
void splitBezier(size_t K, T)(/*out*/ref Point!T[K] left, ref Point!T[K] curve, double t)
in {
  assert(fitsIntoRange!("()")(t, 0.0, 1.0));
} body {
  static assert(K >= 2);

  left[0] = curve[0];

  const mt = 1 - t;
  int k = K;
  while (--k > 0) {
    foreach(i; 0 .. k)
      curve[i] = curve[i] * mt + curve[i + 1] * t;
    left[K - k] = curve[0];
  }
  assert(left[K-1] == curve[0]);
}


void sliceBezier(size_t K, T)(ref const Point!T[K] pts, float t0, float t1, ref Point!T[K] result) if(K==2)
in { assert(t1 > t0); }
body
{
    T[K] x=void, y=void;
    bezToPoly(pts, x, y);
    immutable p0 = Point!T(poly!T(x, t0), poly!T(y, t0));
    immutable p1 = Point!T(poly!T(x, t1), poly!T(y, t1));
    constructBezier(p0, p1, result);
}

void sliceBezier(size_t K, T)(ref const Point!T[K] pts, float t0, float t1, ref Point!T[K] result) if(K==3)
in { assert(t1 > t0); }
body
{
    T[K] x=void, y=void;
    bezToPoly(pts, x, y);
    immutable p0 = Point!T(poly!T(x, t0), poly!T(y, t0));
    immutable p1 = Point!T(poly!T(x, t1), poly!T(y, t1));
    immutable dt = t1 - t0;
    immutable d0 = Vector!T(polyDer!T(x, t0) * dt, polyDer!T(y, t0) * dt);
    constructBezier(p0, p1, d0, result);
}

void sliceBezier(size_t K, T)(ref const Point!T[K] pts, float t0, float t1, ref Point!T[K] result) if(K==4)
in { assert(t1 > t0); }
body
{
    T[K] x=void, y=void;
    bezToPoly(pts, x, y);
    immutable p0 = Point!T(poly!T(x, t0), poly!T(y, t0));
    immutable p1 = Point!T(poly!T(x, t1), poly!T(y, t1));
    immutable dt = t1 - t0;
    immutable d0 = Vector!T(polyDer!T(x, t0) * dt, polyDer!T(y, t0) * dt);
    immutable d1 = Vector!T(polyDer!T(x, t1) * dt, polyDer!T(y, t1) * dt);
    constructBezier(p0, p1, d0, d1, result);
}

int chopMonotonic(T, size_t K, size_t MS)(ref const Point!T[K] curve, ref Point!T[K][MS] monos) if(K==2)
in {
  foreach(ref mono; monos)
    assert(&curve != &mono);
} body {
  static assert(MS >= 1 + 2 * (K-2));

  monos[0] = curve;
  return 1;
}

int chopMonotonic(T, size_t K, size_t MS)(ref const Point!T[K] curve, ref Point!T[K][MS] monos) if(K>2)
in {
  foreach(ref mono; monos)
    assert(&curve != &mono);
} body {
  static assert(MS >= 1 + 2 * (K-2));

  double[2] tx = void, ty = void;
  immutable xcnt = criticalPoints!"x"(curve, tx);
  immutable ycnt = criticalPoints!"y"(curve, ty);
  double[2*(K-2)] ts;
  foreach(i; 0 .. xcnt)
    ts[i] = tx[i];
  foreach(i; 0 .. ycnt)
    ts[xcnt + i] = ty[i];
  auto cnt = xcnt + ycnt;
  sort(ts[0 .. cnt]);
  if (cnt == 1) {
    monos[1] = curve;
    splitBezier(monos[0], monos[1], ts[0]);
  } else {
    Point!T lastPt = curve[0];
    Vector!T lastDer = (K - 1) * (curve[1] - curve[0]);
    double lastT = 0;
    foreach(i, t; ts[0 .. cnt]) {
      Point!T nextPt = evalBezier(curve, t);
      Vector!T nextDer = evalBezierDer(curve, t);
      static if (K == 4)
        constructBezier(lastPt, nextPt, lastDer * (t - lastT), nextDer * (t - lastT), monos[i]);
      else
        constructBezier(lastPt, nextPt, lastDer * (t - lastT), monos[i]);
      lastPt = nextPt;
      lastDer = nextDer;
      lastT = t;
    }
    static if (K == 4) {
      Vector!T nextDer = (K-1)*(curve[$-1] - curve[$-2]);
      constructBezier(lastPt, curve[$-1], lastDer * (1 - lastT), nextDer * (1 - lastT), monos[cnt]);
    } else
      constructBezier(lastPt, curve[$-1], lastDer * (1 - lastT), monos[cnt]);
  }
  debug
  {
    // a monotone segment has at most one critical point (real wiggle);
    // checked exactly where the segments are born
    foreach(i; 0 .. cnt + 1)
      assert(criticalCount!"x"(monos[i]) <= 1 && criticalCount!"y"(monos[i]) <= 1);
  }
  return cnt + 1;
}


unittest {
  FPoint[3] quad = [FPoint(0, 0), FPoint(2, 2), FPoint(4, 0)];
  FPoint[3][3] monos;
  assert(chopMonotonic(quad, monos) == 2);
  assert(monos[0] == [FPoint(0, 0), FPoint(1, 1), FPoint(2, 1)]);
  assert(monos[1] == [FPoint(2, 1), FPoint(3, 1), FPoint(4, 0)]);

  quad = [FPoint(0, 0), FPoint(2, 2), FPoint(0, 0)];
  assert(chopMonotonic(quad, monos) == 3);
  foreach(ref mono; monos)
    assert(monotonic!"x"(mono) && monotonic!"y"(mono));
  assert(monos[0][0] == FPoint(0, 0));
  assert(monos[2][2] == FPoint(0, 0));
}

unittest {
  // Regression (butterfly.svg): cubic with P2 == P3, so x' and y' vanish
  // exactly at t = 1 and x' has one interior root at t = 34.5/262.5.
  // Subdividing at that root in float shifts the endpoint critical points
  // slightly inside (0, 1): the right segment's x derivative has two
  // strictly-interior roots whose extremum values are within a few ulps of
  // the endpoint values. That float noise must not be counted as real
  // wiggles, or the monotonicity tripwire (and clipMonoBezierImpl's)
  // fire on a segment that is monotone to within rounding.
  FPoint[4] cubic = [FPoint(323.62, 177.12), FPoint(335.12, 168.12),
                      FPoint(297.12, 168.12), FPoint(297.12, 168.12)];
  FPoint[4][5] monos;
  auto cnt = chopMonotonic(cubic, monos);
  assert(cnt == 2);
  foreach(i; 0 .. cnt)
    assert(criticalCount!"x"(monos[i]) <= 1 && criticalCount!"y"(monos[i]) <= 1);
}
