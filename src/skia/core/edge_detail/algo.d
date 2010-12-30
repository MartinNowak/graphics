module skia.core.edge_detail.algo;

private {
  import std.algorithm : swap;
  import std.array : front, back;
  import std.math : isNaN, abs, sqrt;
  import std.numeric : FPTemporary;
  import std.traits : isFloatingPoint;
  import std.metastrings : Format;

  import skia.math._;
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

int valid_unit_divide(T, T2)(T numer, T denom, out T2 ratio) {
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

int quadIntersection(T)(in Point!T[3] pts, T y, out T[2] roots) {
  FPTemporary!T a = pts[0].y - 2*pts[1].y + pts[2].y;
  FPTemporary!T b = (-2*pts[0].y + 2*pts[1].y);
  FPTemporary!T c = pts[0].y - y;
  return quadUnitRoots(fixedAry!3(a, b, c), roots);
}

int quadUnitRoots(T1, T2)(in T1[3] coeffs, out T2[2] roots) {
  FPTemporary!T1 a = coeffs[0];
  FPTemporary!T1 b = coeffs[1];
  FPTemporary!T1 c = coeffs[2];

  FPTemporary!T1 r = b*b - 4*a*c;
  if (r < 0)
    return 0;
  assert(!isNaN(r));

  r = sqrt(r);
  int rootIdx;
  rootIdx += valid_unit_divide(-b+r, 2*a, roots[rootIdx]);
  rootIdx += valid_unit_divide(-b-r, 2*a, roots[rootIdx]);
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
Point!T[K][2] splitBezier(size_t K, T)(in Point!T[K] pts, real tValue) {
  static assert(K>=2);
  assert(0 < tValue && tValue < 1);
  assert(pts.length == K);

  real oneMt = 1 - tValue;

  Point!T split(Point!T p0, Point!T p1) {
    return Point!T(p0.x * oneMt + p1.x * tValue, p0.y * oneMt + p1.y * tValue);
  }

  Point!T[K] left;
  Point!T[K] tmp = pts;
  left[0] = pts[0];

  int k = K;
  while (--k > 0) {
    for (int i = 0; i < k ; ++i) {
      tmp[i] = split(tmp[i], tmp[i+1]);
    }
    left[K-k] = tmp[0];
  }
  assert(left[K-1] == tmp[0]);
  return [left, tmp];
}

unittest {
  auto pts = fixedAry!2(point(0.0, 0.0), point(1.0, 1.0));
  auto split = splitBezier(pts, 0.5);
  auto exp = point(0.0, 0.0);
  assert(split[0][0] == exp);
  exp = point(0.5, 0.5);
  assert(split[0][1] == exp);
  assert(split[1][0] == exp);
  exp = point(1.0, 1.0);
  assert(split[1][1] == exp);
}

unittest {
  auto pts = fixedAry!3(point(0.0, 0.0), point(2.0, 2.0), point(4.0, 0.0));
  auto split = splitBezier(pts, 0.25);
}

/**
 * sorts points and returns winding
 */
byte sortPoints(T, size_t N)(ref Point!T[N] pts) {
  if (pts.front.y > pts.back.y) {
    auto i = 0;
    while (i < (N/2)) {
      swap(pts[i], pts[N-i-1]);
      ++i;
    }
    return -1;
  }
  return 1;
}

/**
 * Overloads to calc x/y of given bezier control points.
 */
T calcBezier(string v, T)(in Point!T[2] pts, T t) {
  fitsIntoRange!("[]")(t, 0.0, 1.0);
  auto mt = 1 - t;
  enum cmd = Format!("mt*pts[0].%s + t*pts[1].%s", v, v);
  return mixin(cmd);
}

T calcBezier(string v, T)(in Point!T[3] pts, T t) {
  fitsIntoRange!("[]")(t, 0.0, 1.0);
  auto mt = 1 - t;
  enum cmd = Format!("mt*mt*pts[0].%s + 2*t*mt*pts[1].%s + t*t*pts[2].%s", v, v, v);
  return mixin(cmd);
}

T calcBezier(string v, T)(in Point!T[4] pts, T t) {
  fitsIntoRange!("[]")(t, 0.0, 1.0);
  auto mt = 1 - t;
  enum cmd = Format!("mt*mt*mt*pts[0].%s + 3*t*mt*mt*pts[1].%s + 3*t*t*mt*pts[2].%s + t*t*t*pts[3].%s",
                     v, v, v, v);
  return mixin(cmd);
}
