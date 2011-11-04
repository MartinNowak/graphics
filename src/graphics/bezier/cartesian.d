module graphics.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings,
    std.numeric, std.range, std.traits;
import graphics.math.clamp, graphics.math.poly;
import qcheck._;

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
    this(ref const T[K] cs, in T roundHint=T.max)
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
        }

        convertToPoly(cs, _coeffs);
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
        int res = 0;
        if (_pastend > _position)
            res = 1;
        else if (_pastend < _position)
            res = -1;
        return res;
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

            double dg(double t) { return poly!T(_coeffs, t) - v; }
            return findRootIllinois(&dg, 0.0, 1.0);
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

auto cartesianBezierWalker(T, size_t K)(
    ref const Point!T[K] curve,
    in Point!T roundHint,
    BezierCState!(float, K)* cstate
)
{
    static struct Result
    {
        this(ref const Point!T[K] curve, in Point!T roundHint, BezierCState!(float, K)* cstate)
        {
            _xwalk = beziota!("x")(curve, cast(T)roundHint.x);
            _ywalk = beziota!("y")(curve, cast(T)roundHint.y);
            _cstate = cstate;
        }

        bool empty() const
        {
            return _xwalk.empty && _ywalk.empty;
        }

        int opApply(scope int delegate(ref IPoint pos) dg)
        {
            int opApplyRes;

            int callDg(T nt, bool usex, bool usey)
            {
                if (usex)
                {
                    _cstate.p1.x = _xwalk.pos + (_xwalk._pastend > _xwalk.pos);
                    _xwalk.popFront;
                }
                else
                {
                    _cstate.p1.x = poly!T(_xwalk._coeffs, nt);
                }

                if (usey)
                {
                    _cstate.p1.y = _ywalk.pos + (_ywalk._pastend > _ywalk.pos);
                    _ywalk.popFront;
                }
                else
                {
                    _cstate.p1.y = poly!T(_ywalk._coeffs, nt);
                }

                static if (K >= 3)
                {
                    _cstate.d1.x = polyDer!T(_xwalk._coeffs, nt);
                    _cstate.d1.y = polyDer!T(_ywalk._coeffs, nt);
                }

                IPoint pos = void;
                pos.x = _xwalk.pos;
                pos.y = _ywalk.pos;
                if (auto res = dg(pos))
                    return res;

                // must not be altered by client
                _cstate.p0 = _cstate.p1;
                static if (K >= 3)
                    _cstate.d0 = _cstate.d1;
                return 0;
            }

            while (!opApplyRes)
            {
                if (_xwalk.empty)
                    goto LfinishY;
                else if (_ywalk.empty)
                    goto LfinishX;
                else if (approxEqual(_xwalk.front, _ywalk.front, 1e-6, 1e-6))
                {
                    immutable nt = 0.5 * (_xwalk.front + _ywalk.front);
                    opApplyRes = callDg(nt, true, true);
                }
                else if (_xwalk.front < _ywalk.front)
                {
                    immutable nt = _xwalk.front;
                    opApplyRes = callDg(nt, true, false);
                }
                else if (_ywalk.front < _xwalk.front)
                {
                    immutable nt = _ywalk.front;
                    opApplyRes = callDg(nt, false, true);
                }
                else
                    assert(0);
            }

        LfinishY:
            while (!_ywalk.empty && !opApplyRes)
            {
                immutable nt = _ywalk.front;
                opApplyRes = callDg(nt, false, true);
            }
            goto LReturn;

        LfinishX:
            while (!_xwalk.empty && !opApplyRes)
            {
                immutable nt = _xwalk.front;
                opApplyRes = callDg(nt, true, false);
            }

        LReturn:
            return opApplyRes;
        }

        @property IPoint pos() const
        {
            return IPoint(_xwalk.pos, _ywalk.pos);
        }

        BezierCState!(float, K)* _cstate; // from calling frame
        BezIota!(T, K) _xwalk, _ywalk;
    }
    return Result(curve, roundHint, cstate);
}
