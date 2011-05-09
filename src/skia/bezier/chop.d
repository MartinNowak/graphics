module skia.bezier.chop;

import skia.bezier.curve, skia.math.clamp;
import guip.point;

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
  assert(fitsIntoRange!("()")(t, 0.0, 1.0), to!string(t));
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

void sliceBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 2)
in {
  assert(t1 > t0);
} body {
  constructBezier(evalBezier(pts, t0), evalBezier(pts, t1), result);
}

void sliceBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 3)
in {
  assert(t1 > t0);
} body {
  constructBezier(evalBezier(pts, t0), evalBezier(pts, t1),
                  evalBezierDer(pts, t0) * (t1 - t0), result);
}

void sliceBezier(size_t K, T)(Point!T[K] pts, double t0, double t1, ref Point!T[K] result) if(K == 4)
in {
  assert(t1 > t0);
} body {
  constructBezier(evalBezier(pts, t0), evalBezier(pts, t1),
                  evalBezierDer(pts, t0) * (t1 - t0), evalBezierDer(pts, t1) * (t1 - t0), result);
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
  sliceBezier(test, 0.0, step, res);
  std.stdio.writeln(evalBezierDer(test, 0));
  std.stdio.writeln(evalBezierDer(ptss[0], 0));
  std.stdio.writeln(evalBezierDer(res, 0));
  std.stdio.writeln(evalBezierDer(ptss[0], 1));
  std.stdio.writeln(evalBezierDer(res, 1));
  std.stdio.writeln(ptss[0], res);
}
