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
    auto grid = cs[0] / step;
    auto snapgrid = floor(grid);
    this._position = checkedTo!int(snapgrid);
    if (this._direction < 0 && snapgrid == grid)
      this._position += this._direction;
    double start = round((cs[0] + 0.5 * adv) / step) * step;
    if (start == cs[0])
      start += adv;
    if (this._direction != 0 && checkedTo!int(sgn(cs[$-1] - start)) == this._direction)
      this.steps = iota(start, cast(double)cs[$-1], adv);
    convertPoly(cs, this.coeffs);
  }

  @property bool empty() const {
    return steps.empty;
  }

  @property double front() {
    assert(!empty);
    if (curT !<> 0)
      curT = findT();
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

  double findT() {
    const v = steps.front;
    static if (K == 2) {
      auto evaldg = (double t) { return coeffs[0] * t + coeffs[1] - v; };
    } else static if (K == 3) {
      auto evaldg = (double t) { return (coeffs[0] * t + coeffs[1]) * t + coeffs[2] - v; };
    } else static if (K == 4) {
      auto evaldg = (double t) { return ((coeffs[0] * t + coeffs[1]) * t + coeffs[2]) * t + coeffs[3] - v; };
    } else
      static assert(0);

    double root;
    findRootIllinois!(evaldg)(0, 1, coeffs[$-1] - v, reduce!("a+b")(0.0, coeffs) - v, root);
    return root;
  }

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
}


unittest {
  assert(beziota(1.0, 3.0, 0.5).length == 3);
  assert(beziota(1.1, 3.0, 0.5).length == 3);
  assert(beziota(1.1, 3.01, 0.5).length == 4);
  assert(beziota(3.0, 1.0, 0.5).length == 3);

  assert(beziota(-1.0, -3.0, 0.5).length == 3);

  foreach(t; beziota(1.0, 3.0, 0.5)) {
    assert(fitsIntoRange!("()")(t, 0, 1));
  }
  foreach(t; beziota(3.0, 1.0, 0.5)) {
    assert(fitsIntoRange!("()")(t, 0, 1));
  }
}

void cartesianBezierWalker(alias dg, T, size_t K)(ref const Point!T[K] curve, Rect!T clip, Size!(T) grid)
in {
  assert(grid.width > 0 && grid.height > 0);
} body {
  Point!T[K][1 + 2*(K-2)] monos = void;
  auto monocnt = clipBezier(curve, clip, monos);

  foreach(mono; monos[0 .. monocnt]) {
    auto xwalk = beziota!("x")(mono, grid.width);
    auto ywalk = beziota!("y")(mono, grid.height);
    auto gridPos = IPoint(xwalk.position, ywalk.position);

    double lastT = 0.0;
    for (bool cont=true; cont;) {
      double nextT;
      IPoint gridAdv = void;
      if (!xwalk.empty && !ywalk.empty) {
        if (approxEqual(xwalk.front, ywalk.front, 1e-6, 1e-6)) {
          nextT = 0.5 * (xwalk.front + ywalk.front);
          xwalk.popFront; ywalk.popFront;
          gridAdv = IPoint(xwalk.direction, ywalk.direction);
        } else if (xwalk.front < ywalk.front) {
          nextT = xwalk.front; xwalk.popFront; gridAdv = IPoint(xwalk.direction, 0);
        } else {
          assert(xwalk.front > ywalk.front);
          nextT = ywalk.front; ywalk.popFront; gridAdv = IPoint(0, ywalk.direction);
        }
      } else if (!xwalk.empty) {
        nextT = xwalk.front; xwalk.popFront; gridAdv = IPoint(xwalk.direction, 0);
      } else if (!ywalk.empty) {
        nextT = ywalk.front; ywalk.popFront; gridAdv = IPoint(0, ywalk.direction);
      } else {
        nextT = 1.0; gridAdv = IPoint(0, 0);
        cont = false;
      }
      assert(nextT > lastT);
      Point!T[K] slice = void;
      sliceBezier(mono, lastT, nextT, slice);
      lastT = nextT;
      dg(gridPos, slice);
      gridPos += gridAdv;
      assert(gridPos == IPoint(xwalk.position, ywalk.position),
             to!string(gridPos) ~ "|" ~ to!string(IPoint(xwalk.position, ywalk.position)));
    }
  }
}

void printLine(size_t K)(IPoint gridPos, FPoint[K] curve) { std.stdio.writeln(gridPos, "|", curve); }
unittest {
  FPoint[2] line = [FPoint(336, 425), FPoint(341, 420)];
  cartesianBezierWalker!(printLine)(line, FRect(1000, 1000), FSize(1, 1));
  FPoint[4] curve = [FPoint(1.1, 1), FPoint(2, 10), FPoint(3, -0.1), FPoint(4.49, 1.1)];
  cartesianBezierWalker!(printLine)(curve, FRect(10, 10), FSize(0.5, 0.5));
}

enum tolerance = 1e-2;
void findRootIllinois(alias f)(double a, double b, double fa, double fb, ref double root)
in {
  assert(signbit(fa) != signbit(fb));
} body {
  //  size_t iterations;
  double gamma = 1.0;
  while (true) {
    //    ++iterations;
    double c = (gamma * b * fa - a * fb) / (gamma * fa - fb);
    double fc = f(c);
    debug(Illinois) writeln("illinois step: ", iterations,
                            " a: ", a, " fa: ", fa,
                            " b: ", b, " fb: ", fb,
                            " c: ", c, " fc: ", fc);
    if (fabs(fc) < tolerance) {
      debug(Illinois) writeln("converged after: ", iterations,
                              " at: ", c);
      root = c;
      return;
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

size_t iterCnt;
QCheckResult testRootFinding(FPoint[3] curve, FRect clip) {
  clip.sort();
  if (clip.empty)
    return QCheckResult.Reject;
  FPoint[3][3] monos;

  auto monocnt = clipBezier(curve, clip, monos);
  if (monocnt == 0)
    return QCheckResult.Reject;
  foreach(m; monos[0 .. monocnt]) {
    auto fa = evalBezier(m, 0).y;
    auto fb = evalBezier(m, 1).y;
    if (fa <> fb) {
      foreach(i; 1 .. 1000) {
        auto w0 = i * 0.001;
        auto ymean = w0 * fa + (1 - w0) * fb;
        const a = (m[0].y - 2*m[1].y + m[2].y);
        const b = 2*(m[1].y - m[0].y);
        const c = m[0].y - ymean;
//        const a = m[1].y - m[0].y;
//        const b = m[0].y - ymean;
        double root;
        auto evaldg = (double t) {
          return (a * t + b) * t + c;
          //          return a * t + b;
        };
        findRootIllinois!(evaldg)(0, 1, fa-ymean, fb-ymean, root);
        //        auto cnt = enforce(polyRoots(a, b, root));
        assert(approxEqual(evalBezier(m, root).y, ymean), fmtString("yr:%f ym:%f", evalBezier(m, root).y, ymean));
      }
    }
  }
  return QCheckResult.Ok;
}

unittest {
  //  setRandomSeed(1001);
  //
  quickCheck!(testRootFinding, count(2_000), Policies.RandomizeMembers)();
  std.stdio.writeln(1. / 2_000 * iterCnt);
}
