module skia.core.edge_detail.algo;

private {
  import std.algorithm : swap;
  import std.math : isNaN, abs;
  import std.traits : isFloatingPoint;

  import skia.math.fast_sqrt;
  import skia.core.point;
}

bool isLine(T)(in Point!T[] pts) {
  if (pts.length < 2)
    return false;
  auto refVec = pts[$-1] - pts[0];
  foreach(pt; pts[1..$-1]) {
    if (abs(crossProduct(refVec, pt)) > 1e-2) {
      return false;
    }
  }
  return true;
}

int valid_unit_divide(T)(T numer, T denom, out T ratio) {
  if (numer * denom <= 0) {
    return 0;
  }

  T r = numer / denom;
  assert(r >= 0);
  if (r == 0 || r >= 1) {
    return 0;
  }
  static if (isFloatingPoint!T) {
    if (isNaN(r)) {
      return 0;
    }
  }
  ratio = r;
  return 1;
}

int quadUnitRoots(T)(T[3] coeffs, out T[2] roots) {
  auto a = coeffs[0];
  auto b = coeffs[1];
  auto c = coeffs[2];

  auto r = b*b - 4*a*c;
  if (r < 0)
    return 0;
  static if (isFloatingPoint!T) {
    if (isNaN(r))
      return 0;
  }
  r = fastSqrt(r);
  auto q = b < 0 ? -(b-r)/2 : -(b+r)/2;
  int rootIdx;
  rootIdx += valid_unit_divide(q, a, roots[rootIdx]);
  rootIdx += valid_unit_divide(c, q, roots[rootIdx]);
  if (rootIdx == 2) {
    if (roots[0] > roots[1])
      swap(roots[0], roots[1]);
    if (roots[0] == roots[1])
      rootIdx -= 1;
  }
  return rootIdx;
}

/**
 * Split bezier curve with de Castlejau algorithm.
 */
Point!T[K][2] splitBezier(int K, T)(in Point!T[] pts, T tValue) if (K>=2) {
  assert(0 < tValue && tValue < 1);
  assert(pts.length == K);

  T oneMt = 1 - tValue;

  Point!T split(Point!T p0, Point!T p1) {
    return p0 * oneMt + p1 * tValue;
  }

  Point!T[K] left;
  Point!T[K] tmp = pts[0 .. K];
  left[0] = pts[0];

  int k = K;
  while (--k > 0) {
    for (int i = 0; i < k ; ++i) {
      tmp[i] = split(tmp[i], tmp[i+1]);
    }
    left[K-k] = tmp[0];
  }
  return [left, tmp];
}

unittest {
  auto pts = [point(0.0, 0.0), point(1.0, 1.0)];
  auto split = splitBezier!2(pts, 0.5);
  auto exp = point(0.0, 0.0);
  assert(split[0][0] == exp);
  exp = point(0.5, 0.5);
  assert(split[0][1] == exp);
  assert(split[1][0] == exp);
  exp = point(1.0, 1.0);
  assert(split[1][1] == exp);
}

unittest {
  auto pts = [point(0.0, 0.0), point(2.0, 2.0), point(4.0, 0.0)];
  auto split = splitBezier!3(pts, 0.25);
}
