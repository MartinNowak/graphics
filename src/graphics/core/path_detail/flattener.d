module graphics.core.path_detail.flattener;

import std.math, std.traits, std.c.string;
import graphics.bezier.chop, graphics.core.path;
import guip.point;

static assert(is(ReturnType!(Path.IterDg) == int), "need to adopt Flattener::call()");

struct QuadCubicFlattener
{
    private Path.IterDg dg;
    this(Path.IterDg dg)
    {
        this.dg = dg;
    }

    int call(Path.Verb verb, FPoint[] pts)
    {
        final switch (verb) {
        case Path.Verb.Move, Path.Verb.Close:
            return this.dg(verb, pts);

        case Path.Verb.Line:
            return this.__line(pts);

        case Path.Verb.Quad:
            return this.__quad(pts);

        case Path.Verb.Cubic:
            return this.__cubic(pts);
        }
    }

    int __line(FPoint[] pts)
    {
        assert(pts.length == 2);

        if (degenerate(pts[0], pts[1]))
            return 0;
        else
        {
            Path.Verb verb = Path.Verb.Line;
            return this.dg(verb, pts);
        }
    }

    int __quad(FPoint[] pts)
    {
        assert(pts.length == 3);

        if (degenerate(pts[0], pts[1]))
        {
            return this.__line(pts[1 .. $]);
        }
        else if (degenerate(pts[1], pts[2]))
        {
            return this.__line(pts[0 .. $ - 1]);
        }
        else
        {
            if (tooCurvy(pts[1] - pts[0], pts[2] - pts[1]))
            {
                FPoint[3] ptss0 = void, ptss1 = void;
                memcpy(ptss1.ptr, pts.ptr, ptss1.sizeof);
                splitBezier(ptss0, ptss1, 0.5);
                if (auto res = this.__quad(ptss0))
                    return res;
                if (auto res = this.__quad(ptss1))
                    return res;
                return 0;
            }
            else
            {
                Path.Verb verb = Path.Verb.Quad;
                return this.dg(verb, pts);
            }
        }
    }

    int __cubic(FPoint[] pts)
    {
        assert(pts.length == 4);

        if (degenerate(pts[0], pts[1]))
        {
            return this.__quad(pts[1 .. $]);
        }
        else if (degenerate(pts[2], pts[3]))
        {
            return this.__quad(pts[0 .. $ - 1]);
        }
        else
        {
            if (tooCurvy(pts[1] - pts[0], pts[2] - pts[1]) ||
                tooCurvy(pts[2] - pts[1], pts[3] - pts[2]))
            {
                FPoint[4] ptss0 = void, ptss1 = void;
                memcpy(ptss1.ptr, pts.ptr, ptss1.sizeof);
                splitBezier(ptss0, ptss1, 0.5);
                if (auto res = this.__cubic(ptss0))
                    return res;
                if (auto res = this.__cubic(ptss1))
                    return res;
                return 0;
            }
            else
            {
                Path.Verb verb = Path.Verb.Cubic;
                return this.dg(verb, pts);
            }
        }
    }
}

private bool degenerate(FPoint pt1, FPoint pt2)
{
    enum tol = 1e-3;
    return distance(pt1, pt2) < tol;
}

private bool tooCurvy(FVector v1, FVector v2)
{
    // angle between v1 and v2 < +/-45 deg?
    //  const limit = SQRT1_2 * v1.length * v2.length;
    enum tol = cos(45 * 2 * PI / 360);
    return dotProduct(v1, v2) < tol * v1.length * v2.length;
}
