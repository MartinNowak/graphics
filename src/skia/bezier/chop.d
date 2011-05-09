module skia.bezier.chop;

import skia.bezier.curve, skia.math.clamp;
import guip.point;

/**
 * Split bezier curve with de Castlejau algorithm.
 */
Point!T[K][2] splitBezier(size_t K, T)(Point!T[K] pts, real tValue)
in {
  assert(fitsIntoRange!("()")(tValue, 0.0, 1.0), to!string(tValue));
  assert(pts.length == K);
} body {
  static assert(K>=2);

  real oneMt = 1 - tValue;

  Point!T split(Point!T p0, Point!T p1) {
    return Point!T(p0.x * oneMt + p1.x * tValue, p0.y * oneMt + p1.y * tValue);
  }

  Point!T[K] left;
  left[0] = pts[0];

  int k = K;
  while (--k > 0) {
    for (int i = 0; i < k ; ++i) {
      pts[i] = split(pts[i], pts[i+1]);
    }
    left[K-k] = pts[0];
  }
  assert(left[K-1] == pts[0]);
  Point!T[K][2] res;
  res[0] = left;
  res[1] = pts;
  return res;
}


void cutBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 2)
in {
  assert(t1 > t0);
} body {
  result[0] = evalBezier(pts, t0);
  result[$-1] = evalBezier(pts, t1);
}

void cutBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 3)
in {
  assert(t1 > t0);
} body {
  result[0] = evalBezier(pts, t0);
  result[$-1] = evalBezier(pts, t1);
  result[1] = (evalBezierDer(pts, t0) * ((t1 - t0) / 2) + result[0]);
}

void cutBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 4)
in {
  assert(t1 > t0);
} body {
  result[0] = evalBezier(pts, t0);
  result[$-1] = evalBezier(pts, t1);
  result[1] = (evalBezierDer(pts, t0) * ((t1 - t0) / 3) + result[0]);
  result[2] = (result[3] - evalBezierDer(pts, t1) * ((t1 - t0) / 3));
}

version(unittest) import std.stdio;
unittest {
  FPoint[3] res;
  FPoint[3] test = [FPoint(0.0, 0.0), FPoint(0.5, 0.2), FPoint(1.0, 1.0)];
  auto ptss = splitBezier(test, 0.4);
  auto step = 0.2;
  foreach(i; 1 .. 10) {
    ptss = splitBezier(ptss[0], 0.2);
    step *= 0.4;
    std.stdio.writeln(step);
  }
  cutBezier(test, 0.0, step, res);
  std.stdio.writeln(evalBezierDer(test, 0));
  std.stdio.writeln(evalBezierDer(ptss[0], 0));
  std.stdio.writeln(evalBezierDer(res, 0));
  std.stdio.writeln(evalBezierDer(ptss[0], 1));
  std.stdio.writeln(evalBezierDer(res, 1));
  std.stdio.writeln(ptss[0], res);
}
