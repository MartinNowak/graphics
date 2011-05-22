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
    if (this._direction != 0 && checkedTo!int(sgn(cs[$-1] - start)) == this._direction) {
      this.steps = iota(start, cast(double)cs[$-1], adv);
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
        assert(fitsIntoRange!("[]")(ts[0], 0, 1));
        return ts[0];
      } else {
        assert(rootcnt == 2);
        if (ts[0] < ts[1] && ts[0] >= 0) {
          assert(fitsIntoRange!("[]")(ts[0], 0, 1));
          assert(!fitsIntoRange!("[]")(ts[1], 0, 1));
          return ts[0];
        } else {
          assert(fitsIntoRange!("[]")(ts[1], 0, 1));
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

void cartesianBezierWalker(T, size_t K)(
    ref const Point!T[K] curve,
    Rect!T clip,
    Size!(T) grid,
    void delegate(IPoint gridPos, ref Point!T[K] slice) clientDg)
in {
  assert(grid.width > 0 && grid.height > 0);
} body {
  Point!T[K][1 + 2*(K-2)] monos = void;
  auto monocnt = clipBezier(curve, clip, monos);

  foreach(ref mono; monos[0 .. monocnt]) {
    walkMonoBezier!(T, K)(mono, grid, clientDg);
  }
}

private void walkMonoBezier(T, size_t K, Dg)(ref const Point!T[K] curve, Size!T grid, Dg clientDg) {
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
  void printLine(size_t K)(IPoint gridPos, ref FPoint[K] curve) {
    std.stdio.writeln(gridPos, "|", curve);
  }

  FPoint[2] line = [FPoint(336, 425), FPoint(341, 420)];
  cartesianBezierWalker(line, FRect(1000, 1000), FSize(1, 1), &printLine!2);
  FPoint[4] curve = [FPoint(1.1, 1), FPoint(2, 10), FPoint(3, -0.1), FPoint(4.49, 1.1)];

  cartesianBezierWalker(curve, FRect(10, 10), FSize(0.5, 0.5), &printLine!4);
}

enum tolerance = 1e-2;
double findCubicRoot(ref const float[4] coeffs, double fa, double fb, double v) {
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
