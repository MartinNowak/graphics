module graphics.core.path_detail.flattener;

import core.stdc.string;
import std.math, std.traits;
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

unittest
{
    // collect the verb stream a flattener emits for a path
    struct Collector
    {
        Path.Verb[] verbs;
        int abortAfter = 0; // 0 = no abort

        int opCall(ref Path.Verb verb, ref FPoint[] pts)
        {
            verbs ~= verb;
            if (abortAfter && verbs.length >= abortAfter)
                return 1;
            return 0;
        }
    }

    Collector c;
    Path p;

    // a straight, non-degenerate line passes through
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.lineTo(FPoint(10, 0));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Line]);

    // a degenerate line is dropped
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.lineTo(FPoint(0 + 1e-4f, 0));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move]);

    // a flat quad passes through untouched
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.quadTo(FPoint(5, 0), FPoint(10, 0));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Quad]);

    // a 90-degree corner quad is split into several flatter quads
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.quadTo(FPoint(10, 0), FPoint(10, 10));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs.length >= 3 && c.verbs[0] == Path.Verb.Move);
    foreach (v; c.verbs[1 .. $])
        assert(v == Path.Verb.Quad);

    // a quad with a degenerate handle degrades to a line
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.quadTo(FPoint(0, 0), FPoint(10, 10));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Line]);

    // and the other way round
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.quadTo(FPoint(10, 10), FPoint(10, 10));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Line]);

    // a flat cubic passes through
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.cubicTo(FPoint(3, 0), FPoint(7, 0), FPoint(10, 0));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Cubic]);

    // a curvy cubic is subdivided
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.cubicTo(FPoint(10, 0), FPoint(10, 1), FPoint(10, 10));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Cubic, Path.Verb.Cubic]);

    // a cubic with a degenerate start handle degrades to a quad,
    // which itself degrades to a line
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.cubicTo(FPoint(0, 0), FPoint(10, 10), FPoint(10, 10));
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Line]);

    // Move/Close pass through
    p = Path.init; c = Collector.init;
    p.moveTo(FPoint(0, 0));
    p.lineTo(FPoint(10, 0));
    p.close();
    p.apply!QuadCubicFlattener(&c.opCall);
    assert(c.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line, Path.Verb.Close]);

    // a non-zero return from the dg aborts iteration
    p = Path.init; c = Collector.init;
    c.abortAfter = 1;
    p.moveTo(FPoint(0, 0));
    p.lineTo(FPoint(10, 0));
    p.lineTo(FPoint(10, 10));
    int res = p.apply!QuadCubicFlattener(&c.opCall);
    assert(res != 0 && c.verbs.length == 1);
}
