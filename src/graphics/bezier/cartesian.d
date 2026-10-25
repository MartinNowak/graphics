module graphics.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.numeric, std.range, std.traits;
import graphics.math.clamp, graphics.math.poly;

BezIota!(T, K) beziota(string dir, T, size_t K)(ref const Point!T[K] curve, T roundHint=T.max)
{
    T[K] cs = void;
    foreach(i; 0 .. K)
        cs[i] = __traits(getMember, curve[i], dir);
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
        foreach (c; cs)
            assert(!c.isNaN);
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
            // The crossing can legitimately land on a segment endpoint
            // (the curve touches the grid line at t = 0|1); clamp the
            // floating-point noise just outside [0, 1].
            assert(fitsIntoRange!("[]")(_curT, 0, 1), text(_curT, " ", _position, " ", _pastend, " ",  _coeffs));
            _curT = clampToRange(_curT, 0.0, 1.0);
        }
        return _curT;
    }

    void popFront()
    {
        // If front() was evaluated, use it as the lower bound for the next step!
        if (!isNaN(_curT))
        {
            _prevT = _curT;
            _prevVal = _position + (direction > 0);
        }
        _curT = double.nan;
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

    double findT()
    {
        immutable v = _position + (_pastend > _position);
        // f(t) = poly(t) - v is monotone on [x0, 1] and v is strictly
        // interior to the segment range => exactly one root in (x0, 1).
        double x0 = isNaN(_prevT) ? 0.0 : _prevT;
        double y0 = (isNaN(_prevT) ? _coeffs[$-1] : _prevVal) - v; // == -direction when warm
        // 1e-6 in t-space, matching the walker's isClose(..., 1e-6, 1e-6) merge
        return findRootNewton(_coeffs, v, x0, 1.0, y0, 1e-6);
    }

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
    double _curT = double.nan;
    double _prevT = double.nan;
    T _prevVal = 0.0;
}

auto cartesianBezierWalker(T, size_t K)(
    ref const Point!T[K] curve,
    in Point!T roundHint,
)
{
    static struct Result
    {
        this(ref const Point!T[K] curve, in Point!T roundHint)
        {
            _xwalk = beziota!("x")(curve, cast(T)roundHint.x);
            _ywalk = beziota!("y")(curve, cast(T)roundHint.y);
        }

        bool empty() const
        {
            return _xwalk.empty && _ywalk.empty;
        }

        int opApply(scope int delegate(float t1, ref IPoint pos) dg)
        {
            int opApplyRes;

            int callDg(T t1)
            {
                IPoint pos = void;
                pos.x = _xwalk.pos;
                pos.y = _ywalk.pos;
                if (auto res = dg(t1, pos))
                    return res;
                return 0;
            }

            while (!opApplyRes)
            {
                if (_xwalk.empty)
                    goto LfinishY;
                else if (_ywalk.empty)
                    goto LfinishX;
                else if (isClose(_xwalk.front, _ywalk.front, 1e-6, 1e-6))
                {
                    immutable nt = 0.5 * (_xwalk.front + _ywalk.front);
                    _xwalk.popFront;
                    _ywalk.popFront;
                    opApplyRes = callDg(nt);
                }
                else if (_xwalk.front < _ywalk.front)
                {
                    immutable nt = _xwalk.front;
                    _xwalk.popFront;
                    opApplyRes = callDg(nt);
                }
                else if (_ywalk.front < _xwalk.front)
                {
                    immutable nt = _ywalk.front;
                    _ywalk.popFront;
                    opApplyRes = callDg(nt);
                }
                else
                    assert(0);
            }

        LfinishY:
            while (!_ywalk.empty && !opApplyRes)
            {
                immutable nt = _ywalk.front;
                _ywalk.popFront;
                opApplyRes = callDg(nt);
            }
            goto LReturn;

        LfinishX:
            while (!_xwalk.empty && !opApplyRes)
            {
                immutable nt = _xwalk.front;
                _xwalk.popFront;
                opApplyRes = callDg(nt);
            }

        LReturn:
            return opApplyRes;
        }

        @property IPoint pos() const
        {
            return IPoint(_xwalk.pos, _ywalk.pos);
        }

        BezIota!(T, K) _xwalk, _ywalk;
    }
    return Result(curve, roundHint);
}

unittest
{
    // walks a BezIota; asserts t is strictly increasing and in [0, 1]
    void checkWalk(T, size_t K)(ref BezIota!(T, K) walk)
    {
        double prev = 0.0;
        while (!walk.empty)
        {
            auto t = walk.front;
            assert(fitsIntoRange!("[]")(t, 0, 1), text(t));
            assert(t > prev, text(t, " ", prev));
            prev = t;
            walk.popFront();
        }
    }

    // cold start (first grid line, _prevT is NaN), increasing direction;
    // endpoint exactly on a grid line (3.0): that grid line is not walked
    {
        Point!double[2] pts = [Point!double(0, 0.1), Point!double(0, 3.0)];
        auto walk = beziota!("y", double, 2)(pts);
        checkWalk!double(walk);
        auto fresh = beziota!("y", double, 2)(pts);
        size_t n = 0;
        while (!fresh.empty)
        {
            fresh.popFront();
            ++n;
        }
        assert(n == 2, text(n));
    }

    // decreasing direction (_position > _pastend), start and end exactly on
    // grid lines (3.0, 1.0): only the interior line v=2 is walked
    {
        Point!double[4] pts = [Point!double(0, 3.0), Point!double(0, 2.5),
                              Point!double(0, 2.0), Point!double(0, 1.0)];
        auto walk = beziota!("y", double, 4)(pts);
        size_t n = 0;
        while (!walk.empty)
        {
            walk.popFront();
            ++n;
        }
        assert(n == 1, text(n));
    }

    // warm starts, decreasing direction (p(t) = -1.5t^2 - 1.5t + 3.5):
    // crossings at v=3, v=2, v=1
    {
        Point!double[4] pts = [Point!double(0, 3.5), Point!double(0, 3.0),
                              Point!double(0, 2.0), Point!double(0, 0.5)];
        auto walk = beziota!("y", double, 4)(pts);
        checkWalk!double(walk);
    }

    // warm start with p'(x0) == 0: cubic vertex at the previous root,
    // very flat near it (slow Newton, bisection fallback):
    // p(t) = 10(t-0.5)^3 + 4, crossings at v=3, v=4 (vertex), v=5
    {
        Point!double[4] pts = [Point!double(0, 2.75), Point!double(0, 5.25),
                              Point!double(0, 2.75), Point!double(0, 5.25)];
        auto walk = beziota!("y", double, 4)(pts);
        checkWalk!double(walk);
    }
}
