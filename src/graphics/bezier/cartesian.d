module graphics.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings, std.range;
import graphics.math.clamp, graphics.math.poly;
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

  @property int direction() const {
    return _direction;
  }

  @property int pos() const {
    return this._position;
  }

  alias pos position;

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
      return QCheckResult.Discard;
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

  auto config = Config().maxSuccess(100);
  auto smconfig = Config().maxSuccess(100).minValue(-1).maxValue(1);

  quickCheck!(testBeziota!(float, 2))(smconfig);
  quickCheck!(testBeziota!(float, 2))(config);
  quickCheck!(testBeziota!(double, 2))(smconfig);
  quickCheck!(testBeziota!(double, 2))(config);
  quickCheck!(testBeziota!(float, 3))(smconfig);
  quickCheck!(testBeziota!(float, 3))(config);
  quickCheck!(testBeziota!(double, 3))(smconfig);
  quickCheck!(testBeziota!(double, 3))(config);
  quickCheck!(testBeziota!(float, 4))(smconfig);
  quickCheck!(testBeziota!(float, 4))(config);
  quickCheck!(testBeziota!(double, 4))(smconfig);
  quickCheck!(testBeziota!(double, 4))(config);
}

auto cartesianBezierWalkerRange(T, size_t K)(ref const Point!T[K] curve, Size!T grid=Size!T(1, 1))
{
    static struct Result
    {
        this(ref const Point!T[K] curve, Size!T grid=Size!T(1, 1))
        {
            _xwalk = beziota!("x")(curve, grid.width);
            _ywalk = beziota!("y")(curve, grid.height);
        }

        bool empty() const
        {
            return _xwalk.empty && _ywalk.empty;
        }

        double front()
        {
            if (_xwalk.empty)
                return _ywalk.front;
            else if (_ywalk.empty)
                return _xwalk.front;
            else
                // TODO: consider averaging
                return min(_xwalk.front, _ywalk.front);
        }

        void popFront()
        {
            if (_xwalk.empty)
                _ywalk.popFront;
            else if (_ywalk.empty)
                _xwalk.popFront;
            else if (approxEqual(_xwalk.front, _ywalk.front, 1e-6, 1e-6))
            {
                _xwalk.popFront; _ywalk.popFront;
            }
            else if (_xwalk.front < _ywalk.front)
                _xwalk.popFront;
            else if (_ywalk.front < _xwalk.front)
                _ywalk.popFront;
            else
                assert(0, "Unordered relation");
        }

        @property IPoint pos() const
        {
            return IPoint(_xwalk.position, _ywalk.position);
        }

        BezIota!(T, K) _xwalk, _ywalk;
    }

    return Result(curve, grid);
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
