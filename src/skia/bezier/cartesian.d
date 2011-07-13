module skia.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import skia.bezier.chop, skia.bezier.clip, skia.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings, std.range;
import skia.math.clamp, skia.math.poly, skia.util.format;
import qcheck._;

//debug=Illinois;
debug(Illinois) import std.stdio;

BezIota!(T, K) beziota(string dir, T, size_t K)(ref const Point!T[K] curve, double step) {
  T[K] cs = void;
  foreach(i; 0 .. K)
    cs[i] = mixin(Format!(q{curve[i].%s}, dir));
  return typeof(return)(cs, step);
}

BezIota!(T, 2) beziota(T)(T c0, T c1, double step) {
  T[2] cs = void; cs[0] = c0; cs[1] = c1;
  return typeof(return)(cs, step);
}

struct BezIota(T, size_t K) {
  this(ref const T[K] cs, double step) {
    this._direction = checkedTo!int(sgn(cs[$-1] - cs[0]));
    double adv = this._direction * step;

    // round towards next gridpos with a small additional offset in
    // case cs[0] already is close to a gridpos
    immutable gridpos = round((cs[0] + (0.5 + 1e-5) * adv) / step);

    // pixels are floor indexed (1.2, 1.2) is pos (1, 1)
    this._position = checkedTo!int(floor(cs[0] + 1e-5 * adv));

    if (this._direction != 0) {
      double start = gridpos * step;
      // no gridpos between start and end
      if ((cs[$-1] - start) * this._direction <= 0)
        return;
      // start is at least tolerance away from cs[0]
      assert((start - cs[0]) * this._direction > 1e-5 * step);

      this.steps = iota(start, cast(double)cs[$-1], adv);
      assert(!this.steps.empty);

      // remove last iota value if it falls near cs[$-1]
      immutable last = this.steps[this.steps.length - 1];
      if (fabs(cs[$-1] - last) < 2 * float.epsilon * fabs(cs[$-1] - cs[0]))
        this.steps.popBack;

      convertPoly(cs, this.coeffs);
      static if (K == 4)
        this.endV = cs[$-1];
    }
  }

  @property bool empty() const {
    return steps.empty;
  }

  @property double front() {
    assert(!empty);
    if (isNaN(curT)) {
      curT = findT();
      assert(fitsIntoRange!("()")(curT, 0, 1));
    }
    return curT;
  }

  void popFront() {
    curT = curT.nan;
    steps.popFront;
    this._position += this._direction;
  }

  static if (hasLength!(typeof(steps))) {
    @property size_t length() const {
      return steps.length;
    }
  }

  int direction() const {
    return _direction;
  }

  int position() const {
    return this._position;
  }

  static if (K == 2) {
    double findT() {
      double t = void;
      auto rootcnt = polyRoots(coeffs[0], coeffs[1] - steps.front, t);
      assert(rootcnt);
      return t;
    }
  } else static if (K == 3) {
    double findT() {
      double ts[2] = void;
      auto rootcnt = polyRoots(coeffs[0], coeffs[1], coeffs[2] - steps.front, ts);
      if (rootcnt == 1) {
        return ts[0];
      } else {
        assert(rootcnt == 2);
        if (ts[0] < ts[1] && ts[0] >= 0) {
          assert(!fitsIntoRange!("()")(ts[1], 0, 1));
          return ts[0];
        } else {
          return ts[1];
        }
      }
    }
  } else static if (K == 4) {
    double findT() {
      //    auto evaldg = (double t) { return ((coeffs[0] * t + coeffs[1]) * t + coeffs[2]) * t + coeffs[3] - v; };
      const v = steps.front;
      return findCubicRoot(coeffs, this.coeffs[3] - v, this.endV - v, v);
    }
  } else
    static assert(0, "unimplemented");

  static void convertPoly(ref const T[K] cs, ref T[K] polycs) {
    static if (K == 2) {
      polycs[0] = cs[1] - cs[0];
      polycs[1] = cs[0];
    } else static if (K == 3) {
      polycs[0] = cs[0] - 2 * cs[1] + cs[2];
      polycs[1] = 2 * (-cs[0] + cs[1]);
      polycs[2] = cs[0];
    } else static if (K == 4) {
      polycs[0] = -cs[0] + 3 * (cs[1] - cs[2]) + cs[3];
      polycs[1] = 3 * (cs[0] - 2 * cs[1] + cs[2]);
      polycs[2] = 3 * (-cs[0] + cs[1]);
      polycs[3] = cs[0];
    } else
      static assert(0);
  }

  int _direction;
  int _position;
  T[K] coeffs;
  typeof(iota(0.0, 0.0, 0.0)) steps;
  double curT;
  static if (K == 4)
    T endV;
}


unittest {
  assert(beziota(1.0, 3.0, 1.0).length == 1);
  assert(beziota(1.0 - 1e-10, 3.0, 1.0).length == 1);
  assert(beziota(0.99, 3.0, 1.0).length == 2);
  assert(beziota(1.1, 3.0, 1.0).length == 1);
  assert(beziota(1.6, 3.0, 1.0).length == 1);
  assert(beziota(1.0, 3.01, 1.0).length == 2);
  assert(beziota(1.1, 3.01, 1.0).length == 2);
  assert(beziota(1.6, 3.01, 1.0).length == 2);
  assert(beziota(3.0, 1.0, 1.0).length == 1);
  assert(beziota(3.1, 1.0, 1.0).length == 2);
  assert(beziota(3.1, 0.9, 1.0).length == 3);
  assert(beziota(3.0, 0.9, 1.0).length == 2);
  assert(beziota(-1.0, -3.0, 1.0).length == 1);
  assert(beziota(-1.0, -3.1, 1.0).length == 2);
  assert(beziota(-1.1, -3.1, 1.0).length == 2);
  assert(beziota(-1.6, -3.1, 1.0).length == 2);

  assert(beziota(1.0, 3.0, 1.0).position == 1);
  assert(beziota(1.0+1e-10, -1.0, 1.0).position == 0);
  assert(beziota(1.1, 3.0, 1.0).position == 1);
  assert(beziota(1.6, 3.0, 1.0).position == 1);
  assert(beziota(1.1, 3.01, 1.0).position == 1);
  assert(beziota(3.0, 1.0, 1.0).position == 2);
  assert(beziota(0.0, 1.0, 1.0).position == 0);
  assert(beziota(0.0, -2.0, 1.0).position == -1);
  assert(beziota(0.6, 3.0, 1.0).position == 0);
  assert(beziota(1.0 - 1e-10, 3.0, 1.0).position == 1);

  // test empty beziotas for correct position
  assert(beziota(0.0, 0.0, 1.0).position == 0);
  assert(beziota(0.1, 0.1, 1.0).position == 0);
  assert(beziota(0.6, 0.6, 1.0).position == 0);
  assert(beziota(1.0, 1.0, 1.0).position == 1);
  assert(beziota(1.0+1e-10, 1.0+1e-10, 1.0).position == 1);
  assert(beziota(1.0-1e-10, 1.0-1e-10, 1.0).position == 0);
  assert(beziota(0.0, 0.5, 1.0).position == 0);
  assert(beziota(-0.1, 0.5, 1.0).position == -1);

  foreach(t; beziota(0.300140381f, 0.0f, 1.0))
    assert(fitsIntoRange!("()")(t, 0, 1));

  QCheckResult testBeziota(T, size_t K)(Point!T[K] pts, double step) {
    if (step <= 0)
      return QCheckResult.Reject;
    foreach(t; beziota!("x", T, K)(pts, step))
      assert(fitsIntoRange!("()")(t, 0, 1));
    foreach(t; beziota!("y", T, K)(pts, step))
      assert(fitsIntoRange!("()")(t, 0, 1));

    static if (K < 4) {
      // TODO: fix for cubics
      auto testf = (double a, double b) { assert(b > a); return b; };
      reduce!(testf)(0.0, beziota!("x", T, K)(pts, step));
      reduce!(testf)(0.0, beziota!("y", T, K)(pts, step));
    }

    return QCheckResult.Ok;
  }

  immutable cnt = count(100);
  immutable smLo = maxValue(1.0);
  immutable smHi = minValue(-1.0);
  quickCheck!(testBeziota!(float, 2), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(float, 2), cnt)();
  quickCheck!(testBeziota!(double, 2), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(double, 2), cnt)();
  quickCheck!(testBeziota!(float, 3), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(float, 3), cnt)();
  quickCheck!(testBeziota!(double, 3), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(double, 3), cnt)();
  quickCheck!(testBeziota!(float, 4), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(float, 4), cnt)();
  quickCheck!(testBeziota!(double, 4), cnt, smLo, smHi)();
  quickCheck!(testBeziota!(double, 4), cnt)();
}

void cartesianBezierWalker(T, size_t K)(
    ref const Point!T[K] curve,
    Rect!T clip,
    Size!(T) grid,
    void delegate(IPoint gridPos, ref Point!T[K] slice) clientDg,
    void delegate(IPoint gridPos, ref Point!T[2] line) clientSegConDg=null)
in {
  assert(grid.width > 0 && grid.height > 0);
} body {
  Point!T[K][1 + 2*(K-2)] monos = void;
  auto monocnt = clipBezier(curve, clip, monos);

  if (clientSegConDg is null) {
    foreach(ref mono; monos[0 .. monocnt])
      walkMonoBezier!(T, K)(mono, grid, clientDg);
  } else {

    Point!T segStart = curve[0];
    size_t i;
    while (i < monocnt) {
      if (segStart != monos[i][0])
        joinSegment(segStart, monos[i][0], clip, grid, clientSegConDg);
      walkMonoBezier!(T, K)(monos[i], grid, clientDg);
      segStart = monos[i][$-1];
      ++i;
    }
    if (segStart != curve[$-1])
      joinSegment(segStart, curve[$-1], clip, grid, clientSegConDg);
  }
}

private void walkMonoBezier(T, size_t K)(ref const Point!T[K] curve, Size!T grid, void delegate(IPoint, ref Point!T[K]) clientDg) {
  auto xwalk = beziota!("x")(curve, grid.width);
  auto ywalk = beziota!("y")(curve, grid.height);
  auto slicer = rollingSlicer(curve, 0.0);
  auto gridPos = IPoint(xwalk.position, ywalk.position);

  for (bool cont=true; cont;) {
    double nextT;
    int xadv, yadv;
    if (!xwalk.empty && !ywalk.empty) {
      if (approxEqual(xwalk.front, ywalk.front, 1e-6, 1e-6)) {
        nextT = 0.5 * (xwalk.front + ywalk.front);
        xwalk.popFront; ywalk.popFront;
        xadv = xwalk.direction;
        yadv = ywalk.direction;
      } else if (xwalk.front < ywalk.front) {
        nextT = xwalk.front; xwalk.popFront; xadv = xwalk.direction;
      } else {
        assert(xwalk.front > ywalk.front);
        nextT = ywalk.front; ywalk.popFront; yadv = ywalk.direction;
      }
    } else if (!xwalk.empty) {
      nextT = xwalk.front; xwalk.popFront; xadv = xwalk.direction;
    } else if (!ywalk.empty) {
      nextT = ywalk.front; ywalk.popFront; yadv = ywalk.direction;
    } else {
      nextT = 1.0;
      cont = false;
    }
    Point!T[K] slice = void;
    slicer.advance(nextT, slice);
    clientDg(gridPos, slice);
    gridPos.x += xadv; gridPos.y += yadv;
    assert(gridPos == IPoint(xwalk.position, ywalk.position),
           to!string(gridPos) ~ "|" ~ to!string(IPoint(xwalk.position, ywalk.position)));
  }
}

unittest {
  {
    FPoint[3] pts = [
        FPoint(508.988892, -9.74220704e-15),
        FPoint(530.460022, 21.0119686),
        FPoint(548.355408, 48.0376587),
    ];
    walkMonoBezier(pts, FSize(1, 1), (IPoint, ref FPoint[3]){});
  }

  {
    FPoint[2] pts = [
        FPoint(0.22756958, 20.4533081),
        FPoint(0.22756958, -1.83880688e-10),
    ];
    walkMonoBezier(pts, FSize(1, 1), (IPoint, ref FPoint[2]){});
  }

  {
    FPoint[2] pts = [
        FPoint(302.100647, 0.111938477),
        FPoint(-1.33329295e-05, 0.111938477),
    ];
    walkMonoBezier(pts, FSize(1, 1), (IPoint, ref FPoint[2]){});
  }
}

private void joinSegment(T)(Point!T a, Point!T b, Rect!T clip, Size!T grid, void delegate(IPoint, ref Point!T[2]) clientDg) {
  a = Point!T(clampToRange(a.x, clip.left, clip.right), clampToRange(a.y, clip.top, clip.bottom));
  b = Point!T(clampToRange(b.x, clip.left, clip.right), clampToRange(b.y, clip.top, clip.bottom));
  auto diff = b - a;
  Point!T[2] line = void;
  line[0] = a;
  line[1] = a;

  if (approxEqual(a.x, clip.left) || approxEqual(a.x, clip.right)) {
    // y first
    if (diff.y != 0) {
      line[1].y += diff.y;
      walkMonoBezier!(T, 2)(line, grid, clientDg);
      line[0].y += diff.y;
    }
    if (diff.x != 0) {
      line[1].x += diff.x;
      walkMonoBezier!(T, 2)(line, grid, clientDg);
      line[0].x += diff.x;
    }
  } else {
    // x first
    if (diff.x != 0) {
      line[1].x += diff.x;
      walkMonoBezier!(T, 2)(line, grid, clientDg);
      line[0].x += diff.x;
    }
    if (diff.y != 0) {
      line[1].y += diff.y;
      walkMonoBezier!(T, 2)(line, grid, clientDg);
      line[0].y += diff.y;
    }
  }
}

version(none) {
  unittest {
    void printLine(size_t K)(IPoint gridPos, ref FPoint[K] curve) {
      std.stdio.writeln(gridPos, "|", curve);
    }

    FPoint[2] line = [FPoint(336, 425), FPoint(341, 420)];
    cartesianBezierWalker(line, FRect(1000, 1000), FSize(1, 1), &printLine!2);
    FPoint[4] curve = [FPoint(1.1, 1), FPoint(2, 10), FPoint(3, -0.1), FPoint(4.49, 1.1)];

    cartesianBezierWalker(curve, FRect(10, 10), FSize(0.5, 0.5), &printLine!4);
  }
}

enum tolerance = 1e-2;
double findCubicRoot(T)(ref const T[4] coeffs, double fa, double fb, double v) {
  //  size_t iterations;
  double evalT(double t) {
    return ((coeffs[0] * t + coeffs[1]) * t + coeffs[2]) * t + coeffs[3] - v;
  }
  double a = 0.0, b = 1.0;
  double gamma = 1.0;
  while (true) {
    //    ++iterations;
    double c = (gamma * b * fa - a * fb) / (gamma * fa - fb);
    double fc = evalT(c);
    debug(Illinois) writeln("illinois step: ", iterations,
                            " a: ", a, " fa: ", fa,
                            " b: ", b, " fb: ", fb,
                            " c: ", c, " fc: ", fc);
    if (fabs(fc) < tolerance) {
      debug(Illinois) writeln("converged after: ", iterations,
                              " at: ", c);
      return c;
    } else {
      if (fc * fb < 0) {
        a = b;
        fa = fb;
        gamma = 1.0;
      } else {
        gamma = 0.5;
      }
      b = c;
      fb = fc;
    }
  }
}
