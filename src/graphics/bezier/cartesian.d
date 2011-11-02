module graphics.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings,
    std.numeric, std.range, std.traits;
import graphics.math.clamp, graphics.math.poly;
import qcheck._;

//debug=Illinois;
debug(Illinois) import std.stdio;

BezIota!(T, K) beziota(string dir, T, size_t K)(ref const Point!T[K] curve, T roundHint=T.max)
{
    T[K] cs = void;
    foreach(i; 0 .. K)
        cs[i] = mixin(Format!(q{curve[i].%s}, dir));
    return typeof(return)(cs, roundHint);
}

BezIota!(T, 2) beziota(T)(T c0, T c1, T roundHint=T.max)
{
    T[2] cs = void; cs[0] = c0; cs[1] = c1;
    return typeof(return)(cs, roundHint);
}

/*
 * Iterates t positions of a bernstein polynom in gridded distance.
 */
struct BezIota(T, size_t K) if (is(T : double) && K >= 2 && K <= 4)
{
    this(ref const T[K] cs, T roundHint=T.max)
    in
    {
        // require partial ordered input
        for (size_t i = 0; i < K; ++i)
            for (size_t j = 0; j < i + 1; ++j)
                assert(cs[i] <>= cs[j]);
    }
    body
    {
        _position = checkedTo!int(floor(cs[0]));
        immutable ongrid = _position == cs[0];
        immutable delta = cs[$-1] - cs[0];

        // empty
        if (delta == 0)
        {
            // no dimension and exactly on grid border => adjust towards roundHint
            if (ongrid && roundHint < cs[0])
            {
                --_position;
            }
            _pastend = _position;
        }
        else
        {
            if (delta > 0)
            {
                if (_position + 1 >= cs[$-1])
                {
                    _pastend = _position; // empty
                }
                else
                {
                    _pastend = checkedTo!int(ceil(cs[$-1]));
                    assert(_pastend > _position);
                }
            }
            else if (delta < 0)
            {
                if (ongrid)
                    --_position;

                if (_position <= cs[$-1])
                {
                    _pastend = _position; // empty
                }
                else
                {
                    _pastend = checkedTo!int(floor(cs[$-1]));
                    assert(_pastend < _position);
                }
            }
            else
                assert(0);

            if (!empty)
            {
                convertToPoly(cs, _coeffs);
            }
        }
    }

    @property bool empty() const
    {
        return _position + (_pastend > _position) == _pastend;
    }

    @property double front()
    {
        assert(!empty);
        if (isNaN(_curT))
        {
            _curT = findT();
            assert(fitsIntoRange!("()")(_curT, 0, 1), text(_curT, " ", _position, " ", _pastend, " ",  _coeffs));
        }
        return _curT;
    }

    void popFront()
    {
        _curT = _curT.nan;
        _position += direction;
    }

    @property size_t length() const
    {
        return abs(_pastend - _position) - (_pastend > _position);
    }

    @property int direction() const
    {
        immutable diff = _pastend - _position;
        return !!diff - 2 * !!(diff & (1 << 31));
    }

    @property int pos() const
    {
        return _position;
    }

    alias pos position;

    static if (K == 2)
    {
        double findT()
        {
            double t = void;
            auto rootcnt = polyRoots(_coeffs[0], _coeffs[1] - (_position + (_pastend > _position)), t);
            assert(rootcnt);
            return t;
        }
    }
    else static if (K == 3)
    {
        double findT()
        {
            double ts[2] = void;
            auto rootcnt = polyRoots(_coeffs[0], _coeffs[1], _coeffs[2] - (_position + (_pastend > _position)), ts);
            if (rootcnt == 1)
            {
                return ts[0];
            }
            else
            {
                assert(rootcnt == 2);
                if (ts[0] < ts[1] && ts[0] >= 0)
                {
                    assert(!fitsIntoRange!("()")(ts[1], 0, 1));
                    return ts[0];
                }
                else
                {
                    return ts[1];
                }
            }
        }
    }
    else static if (K == 4)
    {
        double findT()
        {
            immutable v = _position + (_pastend > _position);

            double evalT(double t)
            {
                return ((_coeffs[0] * t + _coeffs[1]) * t + _coeffs[2]) * t + _coeffs[3] - v;
            }

            return findRoot(&evalT, 0.0, 1.0);
        }
    }
    else
        static assert(0);

    static void convertToPoly(ref const T[K] cs, ref T[K] polycs)
    {
        static if (K == 2)
        {
            polycs[0] = cs[1] - cs[0];
            polycs[1] = cs[0];
        }
        else static if (K == 3)
        {
            polycs[0] = cs[0] - 2 * cs[1] + cs[2];
            polycs[1] = 2 * (-cs[0] + cs[1]);
            polycs[2] = cs[0];
        }
        else static if (K == 4)
        {
            polycs[0] = -cs[0] + 3 * (cs[1] - cs[2]) + cs[3];
            polycs[1] = 3 * (cs[0] - 2 * cs[1] + cs[2]);
            polycs[2] = 3 * (-cs[0] + cs[1]);
            polycs[3] = cs[0];
        }
        else
            static assert(0);
    }

    int _position;
    int _pastend;
    T[K] _coeffs;
    double _curT;
}


unittest {
  assert(beziota(1.0, 3.0).length == 1);
  assert(beziota(1.0 - 1e-10, 3.0).length == 2);
  assert(beziota(0.99, 3.0).length == 2);
  assert(beziota(1.1, 3.0).length == 1);
  assert(beziota(1.6, 3.0).length == 1);
  assert(beziota(1.0, 3.01).length == 2);
  assert(beziota(1.1, 3.01).length == 2);
  assert(beziota(1.6, 3.01).length == 2);
  assert(beziota(3.0, 1.0).length == 1);
  assert(beziota(3.1, 1.0).length == 2);
  assert(beziota(3.1, 0.9).length == 3);
  assert(beziota(3.0, 0.9).length == 2);
  assert(beziota(-1.0, -3.0).length == 1);
  assert(beziota(-1.0, -3.1).length == 2);
  assert(beziota(-1.1, -3.1).length == 2);
  assert(beziota(-1.6, -3.1).length == 2);

  assert(beziota(1.0, 3.0).position == 1);
  assert(beziota(1.0, -1.0).position == 0);
  assert(beziota(1.1, 3.0).position == 1);
  assert(beziota(1.6, 3.0).position == 1);
  assert(beziota(1.1, 3.01).position == 1);
  assert(beziota(3.0, 1.0).position == 2);
  assert(beziota(0.0, 1.0).position == 0);
  assert(beziota(0.0, -2.0).position == -1);
  assert(beziota(0.6, 3.0).position == 0);
  assert(beziota(1.0 - 1e-10, 3.0).position == 0);

  // test empty beziotas for correct position
  assert(beziota(0.0, 0.0).position == 0);
  assert(beziota(0.1, 0.1).position == 0);
  assert(beziota(0.6, 0.6).position == 0);
  assert(beziota(1.0, 1.0).position == 1);
  assert(beziota(1.0+1e-10, 1.0+1e-10).position == 1);
  assert(beziota(1.0-1e-10, 1.0-1e-10).position == 0);
  assert(beziota(0.0, 0.5).position == 0);
  assert(beziota(-0.1, 0.5).position == -1);

  foreach(t; beziota(0.300140381f, 0.0f))
    assert(fitsIntoRange!("()")(t, 0, 1));

  QCheckResult testBeziota(T, size_t K)(Point!T[K] pts)
  {
      if (!monotonic!"x"(pts) || !monotonic!"y"(pts))
          return QCheckResult.Discard;

      foreach(t; beziota!("x", T, K)(pts))
          assert(fitsIntoRange!("()")(t, 0, 1));
      foreach(t; beziota!("y", T, K)(pts))
          assert(fitsIntoRange!("()")(t, 0, 1));

      auto testf = (double a, double b) { assert(b > a); return b; };
      reduce!(testf)(0.0, beziota!("x", T, K)(pts));
      reduce!(testf)(0.0, beziota!("y", T, K)(pts));

      return QCheckResult.Ok;
  }

  // funny parser error w/o static
  static Point!T[K] gen(T, size_t K)()
  {
      auto xdir = sgn(getArbitrary!int());
      auto ydir = sgn(getArbitrary!int());

      Point!T[K] res = void;
      auto config = Config().minValue(-1_000).maxValue(1_000);
      res[0] = getArbitrary!(Point!T)(config);
      foreach(i; 1 .. K)
      {
          auto d = getArbitrary!(Vector!T)(config);
          res[i].x = res[i-1].x + xdir * abs(d.x);
          res[i].y = res[i-1].y + ydir * abs(d.y);
      }
      return res;
  }

  import std.typetuple;
  foreach(T; TypeTuple!(float, double))
  {
      foreach(K; TypeTuple!(2, 3, 4))
      {
          quickCheck!(testBeziota!(T , K), gen!(T, K))();
      }
  }
}

auto cartesianBezierWalker(T, size_t K)(ref const Point!T[K] curve, Point!T roundHint=Point!T(T.max, T.max))
{
    static struct Result
    {
        this(ref const Point!T[K] curve, Point!T roundHint)
        {
            _xwalk = beziota!("x")(curve, roundHint.x);
            _ywalk = beziota!("y")(curve, roundHint.y);
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

    return Result(curve, roundHint);
}

enum tolerance = 1e-4;
// debug = IllinoisStats;
debug(IllinoisStats)
{
    size_t sumIterations;
    size_t numRuns;
    static ~this()
    {
        std.stdio.writefln("mean iterations %s", 1.0 * sumIterations / numRuns);
    }
}

T findRoot(T, R)(scope R delegate(T) f, T a, T b)
{
    size_t iterations;
    FPTemporary!R fa = f(a);
    FPTemporary!R fb = f(b);
    FPTemporary!T gamma = 1.0;
    do
    {
        FPTemporary!T c = (gamma * b * fa - a * fb) / (gamma * fa - fb);
        FPTemporary!T fc = f(c);
        debug(Illinois) writeln("illinois step: ", iterations,
                                " a: ", a, " fa: ", fa,
                                " b: ", b, " fb: ", fb,
                                " c: ", c, " fc: ", fc);
        if (fabs(fc) !> tolerance)
        {
            debug(Illinois)
                writeln("converged after: ", iterations,
                        " at: ", c);
            debug(IllinoisStats)
            {
                .sumIterations += iterations + 1;
                ++.numRuns;
            }
            return c;
        }
        else
        {
            if (signbit(fc) != signbit(fb))
            {
                a = b;
                fa = fb;
                gamma = 1.0;
            }
            else
            {
                gamma = 0.5;
            }
            b = c;
            fb = fc;
        }
    } while (++iterations < 1000);
    assert(0, std.string.format(
               "Failed to converge. Interval [f(%s)=%s .. f(%s)=%s]",
               a, fa, b, fb));
}
