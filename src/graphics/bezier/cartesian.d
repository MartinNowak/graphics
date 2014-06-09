module graphics.bezier.cartesian;

import guip.point, guip.rect, guip.size;
import graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import std.algorithm, std.conv, std.exception, std.math, std.metastrings,
    std.numeric, std.range, std.traits;
import graphics.math.clamp, graphics.math.poly;

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

double floor(double d)
{
    version (X86_64) static double asmFloor(double d)
    {
        asm { naked; cvttsd2si EAX, XMM0; cvtsi2sd XMM0, EAX; ret; }
    }
    auto res = asmFloor(d);
    if (d < 0 && res != d)
        return res - 1.0;
    return res;
}

unittest
{
    assert(floor(-0.1) == -1.0);
    assert(floor(-0.5) == -1.0);
    assert(floor(-0.9) == -1.0);
    assert(floor(-5.3) == -6.0);
    assert(floor(0.1) == 0.0);
    assert(floor(0.5) == 0.0);
    assert(floor(0.9) == 0.0);
    assert(floor(5.3) == 5.0);
}

double ceil(double d)
{
    version (X86_64) static double asmFloor(double d)
    {
        asm { naked; cvttsd2si EAX, XMM0; cvtsi2sd XMM0, EAX; ret; }
    }
    auto res = asmFloor(d);
    if (d > 0 && res != d)
        return res + 1.0;
    return res;
}

unittest
{
    assert(ceil(-0.1) == -0.0);
    assert(ceil(-0.5) == -0.0);
    assert(ceil(-0.9) == -0.0);
    assert(ceil(-5.3) == -5.0);
    assert(ceil(0.1) == 1.0);
    assert(ceil(0.5) == 1.0);
    assert(ceil(0.9) == 1.0);
    assert(ceil(5.3) == 6.0);
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
                else if (approxEqual(_xwalk.front, _ywalk.front, 1e-6, 1e-6))
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
