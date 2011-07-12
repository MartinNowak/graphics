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

RollingSlicer!(K, T) rollingSlicer(size_t K, T)(ref const Point!T[K] curve, double startT) {
  return RollingSlicer!(K, T)(curve, startT);
}

struct RollingSlicer(size_t K, T) if (K == 2) {
  this(ref const Point!T[K] curve, double startT) {
    this.curve = &curve;
    this.curPt = evalBezier(curve, startT);
  }

  void advance(double nextT, ref Point!T[K] slice) {
    Point!T nextPt = evalBezier(*this.curve, nextT);
    constructBezier(this.curPt, nextPt, slice);
    this.curPt = nextPt;
  }

  const Point!T[K]* curve;
  Point!T curPt;
}

struct RollingSlicer(size_t K, T) if (K == 3) {
  this(ref const Point!T[K] curve, double startT) {
    this.curve = &curve;
    this.curT = startT;
    this.curPt = evalBezier(curve, startT);
  }

  void advance(double nextT, ref Point!T[K] slice) {
    assert(nextT > this.curT);
    Point!T nextPt = evalBezier(*this.curve, nextT);
    constructBezier(this.curPt, nextPt, evalBezierDer(*this.curve, this.curT) * (nextT - this.curT), slice);
    this.curT = nextT;
    this.curPt = nextPt;
  }

  const Point!T[K]* curve;
  double curT;
  Point!T curPt;
}

struct RollingSlicer(size_t K, T) if (K == 4) {
  this(ref const Point!T[K] curve, double startT) {
    this.curve = &curve;
    this.curT = startT;
    this.curPt = evalBezier(*this.curve, startT);
    this.curDer = evalBezierDer(*this.curve, startT);
  }

  void advance(double nextT, ref Point!T[K] slice) {
    assert(nextT > this.curT);
    Point!T nextPt = evalBezier(*this.curve, nextT);
    Vector!T nextDer = evalBezierDer(*this.curve, nextT);
    constructBezier(this.curPt, nextPt, this.curDer * (nextT - this.curT), nextDer * (nextT - this.curT), slice);
    this.curT = nextT;
    this.curPt = nextPt;
    this.curDer = nextDer;
  }

  const Point!T[K]* curve;
  double curT;
  Point!T curPt;
  Vector!T curDer;
}

version(none) {
  import std.stdio;
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

  double[2*(K-2)] ts;
  auto cnt = bezierExtrema(curve, ts);
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
