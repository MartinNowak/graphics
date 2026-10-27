module graphics.core.path;

import std.algorithm, std.array, std.complex, std.conv, std.math, std.numeric, std.range, std.traits, std.typetuple;
import graphics.math.poly;
import graphics.bezier.chop, graphics.core.path_detail._;
import guip.point, guip.rect;

public import graphics.core.path_detail._ : QuadCubicFlattener;

debug import std.stdio : writeln, printf;
version=CUBIC_ARC;

private enum CubicArcFactor = (SQRT2 - 1.0) * 4.0 / 3.0;

alias PathData!(FPoint, Path.Verb) MutablePathData;
alias PathData!(immutable FPoint, immutable Path.Verb) ImmutablePathData;

struct PathData(P, V) if(is(P : const(FPoint)) && is(V : const(Path.Verb)))
{
    Appender!(P[]) _points;
    Appender!(V[]) _verbs;

    @property bool empty() const
    {
        return verbs.length == 0 ||
            verbs.length == 1 && verbs[0] == Path.Verb.Move;
    }

    static if (!is(P == immutable) && !is(V == immutable))
    {
        void reset()
        {
            _points.clear();
            _verbs.clear();
        }
    }
    else
    {
        void reset()
        {
            _points = _points.init;
            _verbs = _verbs.init;
        }
    }

    @property const(P)[] points() const
    {
        return (cast()_points).data.save;
    }

    @property P lastPoint() const
    {
        return points[$-1];
    }

    @property const(V)[] verbs() const
    {
        return (cast()_verbs).data.save;
    }

    bool lastVerbWas(Path.Verb verb) const
    {
        return verbs.length == 0 ? false : verbs[$-1] == verb;
    }

    void primTo(const(FPoint)[] pts...)
    {
        // implicit moveTo when no preceded by point
        if (_verbs.data.empty)
        {
            _points.put(pts[$-1]);
            _verbs.put(Path.Verb.Move);
        }
        else
        {
            _points.put(pts);
            _verbs.put(cast(Path.Verb)pts.length);
        }
    }

    void relPrimTo(FVector[] pts...)
    {
        auto last = lastPoint;
        foreach(ref pt; pts)
            pt = pt + last;
        primTo(pts);
    }

    void moveTo(in FPoint pt)
    {
        // An SVG path like "M 0 0 Z M 10 10 ..." leaves a dangling Move when
        // close() skips an empty subpath: start the new subpath over rather
        // than asserting.
        if (lastVerbWas(Path.Verb.Move))
        {
            // Appender has no popBack: drop the dangling Move by rebuilding
            // the tail (paths are short; this is the rare "M Z M" idiom).
            auto pts = (cast()_points).data.dup, vbs = (cast()_verbs).data.dup;
            static if (!is(P == immutable) && !is(V == immutable))
            {
                _points.clear();
                _verbs.clear();
            }
            else
            {
                _points = _points.init;
                _verbs = _verbs.init;
            }
            _points.put(pts[0 .. $-1]);
            _verbs.put(vbs[0 .. $-1]);
        }
        _points.put(pt);
        _verbs.put(Path.Verb.Move);
    }

    void relMoveTo(in FVector pt)
    {
        moveTo(lastPoint + pt);
    }

    void lineTo(in FPoint pt)
    {
        primTo(pt);
    }

    void relLineTo(in FVector pt)
    {
        relPrimTo(pt);
    }

    void quadTo(in FPoint pt1, in FPoint pt2)
    {
        primTo(pt1, pt2);
    }

    void relQuadTo(in FVector pt1, in FVector pt2)
    {
        relPrimTo(pt1, pt2);
    }

    void cubicTo(in FPoint pt1, in FPoint pt2, in FPoint pt3)
    {
        primTo(pt1, pt2, pt3);
    }

    void relCubicTo(in FVector pt1, in FVector pt2, in FVector pt3)
    {
        relPrimTo(pt1, pt2, pt3);
    }

    void close()
    {
        if (_verbs.data.length > 0)
        {
            final switch (_verbs.data[$-1])
            {
            case Path.Verb.Line, Path.Verb.Quad, Path.Verb.Cubic:
                _verbs.put(Path.Verb.Close);
                break;

            case Path.Verb.Close:
                break;

            case Path.Verb.Move:
                // A "Z" directly after a "M" closes a zero-area
                // subpath; it draws nothing, so emit no Close verb.
                break;
            }
        }
    }

    void addPath(P, V)(in PathData!(P, V) data)
    {
        _verbs.put(data.verbs);
        _points.put(data.points);
    }

    void reversePathTo(in PathData data)
    {
        if (data.empty)
            return;

        _verbs.reserve(verbs.length + data.verbs.length);
        _points.reserve(points.length + data.points.length);

        //! skip initial moveTo
        assert(verbs.front == Path.Verb.Move);
        auto vs = data.verbs[1..$].retro;
        auto rpts = data.points[0..$-1].retro;

        for (; !vs.empty; vs.popFront)
        {
            auto verb = vs.front;
            switch (verb)
            {
            case Path.Verb.Line:
                primTo(rpts[0]);
                rpts.popFront;
                break;

            case Path.Verb.Quad:
                primTo(rpts[0], rpts[1]);
                popFrontN(rpts, 2);
                break;

            case Path.Verb.Cubic:
                primTo(rpts[0], rpts[1], rpts[2]);
                popFrontN(rpts, 3);
                break;

            default:
                assert(0, "bad verb in reversePathTo: " ~ to!string(data.verbs));
            }
        }
        assert(rpts.empty);
    }

    void addRect(in FRect rect, Path.Direction dir = Path.Direction.CW)
    {
        FPoint[4] quad = rect.toQuad;

        if (dir == Path.Direction.CCW)
            swap(quad[1], quad[3]);

        moveTo(quad[0]);
        foreach(ref pt; quad[1..$])
        {
            lineTo(pt);
        }
        close();
    }

    void addRoundRect(FRect rect, float rx, float ry, Path.Direction dir = Path.Direction.CW)
    {
        if (rect.empty)
            return;

        immutable  skip_hori = 2 * rx >= rect.width;
        immutable  skip_vert = 2 * ry >= rect.height;
        if (skip_hori && skip_vert)
            return addOval(rect, dir);

        if (skip_hori)
            rx = 0.5 * rect.width;
        if (skip_vert)
            ry = 0.5 * rect.height;

        immutable sx = rx * CubicArcFactor;
        immutable sy = ry * CubicArcFactor;

        moveTo(FPoint(rect.right - rx, rect.top));

        if (dir == Path.Direction.CCW)
        {
            // top
            if (!skip_hori)
                lineTo(FPoint(rect.left + rx, rect.top));

            // top-left
            cubicTo(
                FPoint(rect.left + rx - sx, rect.top),
                FPoint(rect.left, rect.top + ry - sy),
                FPoint(rect.left, rect.top + ry)
            );

            // left
            if (!skip_vert)
                lineTo(FPoint(rect.left, rect.bottom - ry));

            // bot-left
            cubicTo(
                FPoint(rect.left, rect.bottom - ry + sy),
                FPoint(rect.left + rx - sx, rect.bottom),
                FPoint(rect.left + rx, rect.bottom)
            );

            // bottom
            if (!skip_hori)
                lineTo(FPoint(rect.right - rx, rect.bottom));

            // bot-right
            cubicTo(
                FPoint(rect.right - rx + sx, rect.bottom),
                FPoint(rect.right, rect.bottom - ry + sy),
                FPoint(rect.right, rect.bottom - ry)
            );

            if (!skip_vert)
                lineTo(FPoint(rect.right, rect.top + ry));

            // top-right
            cubicTo(
                FPoint(rect.right, rect.top + ry - sy),
                FPoint(rect.right - rx + sx, rect.top),
                FPoint(rect.right - rx, rect.top)
            );
        } // CCW
        else
        {
            // top-right
            cubicTo(
                FPoint(rect.right - rx + sx, rect.top),
                FPoint(rect.right, rect.top + ry - sy),
                FPoint(rect.right, rect.top + ry)
            );

            if (!skip_vert)
                lineTo(FPoint(rect.right, rect.bottom - ry));

            // bot-right
            cubicTo(
                FPoint(rect.right, rect.bottom - ry + sy),
                FPoint(rect.right - rx + sx, rect.bottom),
                FPoint(rect.right - rx, rect.bottom)
            );

            // bottom
            if (!skip_hori)
                lineTo(FPoint(rect.left + rx, rect.bottom));

            // bot-left
            cubicTo(
                FPoint(rect.left + rx - sx, rect.bottom),
                FPoint(rect.left, rect.bottom - ry + sy),
                FPoint(rect.left, rect.bottom - ry)
            );

            // left
            if (!skip_vert)
                lineTo(FPoint(rect.left, rect.top + ry));

            // top-left
            cubicTo(
                FPoint(rect.left, rect.top + ry - sy),
                FPoint(rect.left + rx - sx, rect.top),
                FPoint(rect.left + rx, rect.top)
            );

            // top
            if (!skip_hori)
                this.lineTo(FPoint(rect.right - rx, rect.top));
        } // CW

        close();
  }

    void addOval(FRect oval, Path.Direction dir = Path.Direction.CW)
    {
        immutable cx = oval.centerX;
        immutable cy = oval.centerY;
        immutable rx = 0.5 * oval.width;
        immutable ry = 0.5 * oval.height;

        version(CUBIC_ARC)
        {
            immutable sx = rx * CubicArcFactor;
            immutable sy = ry * CubicArcFactor;

            moveTo(FPoint(cx + rx, cy));
            if (dir == Path.Direction.CCW)
            {
                cubicTo(FPoint(cx + rx, cy - sy), FPoint(cx + sx, cy - ry), FPoint(cx     , cy - ry));
                cubicTo(FPoint(cx - sx, cy - ry), FPoint(cx - rx, cy - sy), FPoint(cx - rx, cy     ));
                cubicTo(FPoint(cx - rx, cy + sy), FPoint(cx - sx, cy + ry), FPoint(cx     , cy + ry));
                cubicTo(FPoint(cx + sx, cy + ry), FPoint(cx + rx, cy + sy), FPoint(cx + rx, cy     ));
            }
            else
            {
                cubicTo(FPoint(cx + rx, cy + sy), FPoint(cx + sx, cy + ry), FPoint(cx     , cy + ry));
                cubicTo(FPoint(cx - sx, cy + ry), FPoint(cx - rx, cy + sy), FPoint(cx - rx, cy     ));
                cubicTo(FPoint(cx - rx, cy - sy), FPoint(cx - sx, cy - ry), FPoint(cx     , cy - ry));
                cubicTo(FPoint(cx + sx, cy - ry), FPoint(cx + rx, cy - sy), FPoint(cx + rx, cy     ));
            }
        }
        else
        {
            enum TAN_PI_8 = tan(PI_4 * 0.5);
            immutable sx = rx * TAN_PI_8;
            immutable sy = ry * TAN_PI_8;
            immutable mx = rx * SQRT1_2;
            immutable my = ry * SQRT1_2;
            immutable L = oval.left;
            immutable T = oval.top;
            immutable R = oval.right;
            immutable B = oval.bottom;

            moveTo(FPoint(R, cy));
            if (dir == Path.Direction.CCW)
            {
                quadTo(FPoint(R      ,  cy - sy), FPoint(cx + mx, cy - my));
                quadTo(FPoint(cx + sx,  T      ), FPoint(cx     , T      ));
                quadTo(FPoint(cx - sx,  T      ), FPoint(cx - mx, cy - my));
                quadTo(FPoint(L      ,  cy - sy), FPoint(L      , cy     ));
                quadTo(FPoint(L      ,  cy + sy), FPoint(cx - mx, cy + my));
                quadTo(FPoint(cx - sx,  B      ), FPoint(cx     , B      ));
                quadTo(FPoint(cx + sx,  B      ), FPoint(cx + mx, cy + my));
                quadTo(FPoint(R      ,  cy + sy), FPoint(R      , cy     ));
            }
            else
            {
                quadTo(FPoint(R      ,  cy + sy), FPoint(cx + mx, cy + my));
                quadTo(FPoint(cx + sx,  B      ), FPoint(cx     , B      ));
                quadTo(FPoint(cx - sx,  B      ), FPoint(cx - mx, cy + my));
                quadTo(FPoint(L      ,  cy + sy), FPoint(L      , cy     ));
                quadTo(FPoint(L      ,  cy - sy), FPoint(cx - mx, cy - my));
                quadTo(FPoint(cx - sx,  T      ), FPoint(cx     , T      ));
                quadTo(FPoint(cx + sx,  T      ), FPoint(cx + mx, cy - my));
                quadTo(FPoint(R      ,  cy - sy), FPoint(R      , cy     ));
            }
        }

        close();
    }

    void arcTo(FPoint center, FPoint endPt, Path.Direction dir = Path.Direction.CW)
    {
        // implicit moveTo when no preceded by point
        if (_verbs.data.empty)
        {
            _points.put(endPt);
            _verbs.put(Path.Verb.Move);
            return;
        }

        auto startPt = this.lastPoint;
        immutable FVector start = startPt - center;
        immutable FVector   end = endPt   - center;
        FPTemporary!float     radius = (start.length + end.length) * 0.5;
        FPTemporary!float startAngle = atan2(start.y, start.x);
        FPTemporary!float   endAngle = atan2(end.y, end.x);
        FPTemporary!float sweepAngle = endAngle - startAngle;

        // unwrap angle
        if (sweepAngle < 0)
            sweepAngle += 2*PI;
        if (dir == Path.Direction.CCW)
            sweepAngle -= 2*PI;

        assert(abs(sweepAngle) <= 2*PI);
        FPTemporary!float midAngle = startAngle + 0.5 * sweepAngle;
        immutable cossin = expi(midAngle);
        auto middle = FVector(cossin.re, cossin.im);

        if (abs(sweepAngle) > PI_4)
        {   //! recurse
            middle = middle.scaledTo(radius);
            FPoint middlePt = center + middle;
            arcTo(center, middlePt, dir);
            arcTo(center, endPt, dir);
        }
        else
        {   //! based upon a deltoid, calculate length of the long axis.
            FPTemporary!float hc = 0.5 * (startPt - endPt).length;
            FPTemporary!float b = hc / sin(0.5 * (PI - abs(sweepAngle)));
            FPTemporary!float longAxis = sqrt(radius * radius + b * b);
            middle = middle.scaledTo(longAxis);
            quadTo(center + middle, endPt);
        }
    }

    void addArc(FPoint center, FPoint startPt, FPoint endPt, Path.Direction dir = Path.Direction.CW)
    {
        moveTo(center);
        lineTo(startPt);
        arcTo(center, endPt, dir);
        lineTo(center);
    }
}

// TODO: FPoint -> Point!T
struct Path
{
    ImmutablePathData _data;

    alias _data this;

    enum Verb : ubyte
    {
        Move  = 0,
        Line  = 1,
        Quad  = 2,
        Cubic = 3,
        Close = 4,
    }

    enum Direction
    {
        CW,
        CCW,
    }

    string toString() const
    {
        string res;
        res ~= "Path, bounds: " ~ to!string(bounds) ~ "\n";
        foreach(verb, pts; this)
        {
            res ~= to!string(verb) ~ ": ";
            foreach(FPoint pt; pts)
                res ~= to!string(pt) ~ ", ";
            res ~= "\n";
        }
        return res;
    }

    @property FRect bounds() const
    {
        if (points.empty)
        {
            return FRect.emptyRect();
        }
        else
        {
            return FRect.calcBounds(points);
        }
    }

    @property IRect ibounds() const
    {
        return bounds.roundOut();
    }

    alias int delegate(ref Verb, ref FPoint[]) IterDg;
    int apply(Flattener=void)(scope IterDg dg) const
    {
        if (_data.empty)
            return 0;

        FPoint moveTo=void, lastPt=void;
        FPoint[4] tmpPts=void;

        auto vs = verbs.save;
        auto pts = points.save;
        static if (!is(Flattener == void))
            auto flattener = Flattener(dg);

        int emit(Verb verb, FPoint[] pts)
        {
            static if (!is(Flattener == void))
                return flattener.call(verb, pts);
            else
                return dg(verb, pts);
        }

        while (!vs.empty)
        {
            Verb verb = vs.front; vs.popFront();

            final switch (verb)
            {
            case Path.Verb.Move:
                moveTo = lastPt = tmpPts[0] = pts.front;
                pts.popFront;
                if (auto res = emit(Path.Verb.Move, tmpPts[0 .. 1]))
                    return res;
                break;

            case Path.Verb.Close:
                if (lastPt != moveTo)
                {
                    tmpPts[0] = lastPt;
                    tmpPts[1] = moveTo;
                    if (auto res = emit(Path.Verb.Line, tmpPts[0 .. 2]))
                        return res;
                    lastPt = moveTo;
                }
                if (auto res = emit(Path.Verb.Close, tmpPts[0 .. 0]))
                    return res;
                break;

            foreach(v; TypeTuple!(Path.Verb.Line, Path.Verb.Quad, Path.Verb.Cubic))
            case v:
            {
                tmpPts[0] = lastPt;
                foreach(i; SIota!(0, v))
                    tmpPts[i+1] = pts[i];
                lastPt = pts[v-1];
                pts.popFrontN(v);
                if (auto res = emit(verb, tmpPts[0 .. v+1]))
                    return res;
                break;
            }
            }
        }
        return 0;
    }

    alias apply!() opApply;

    bool isClosedContour()
    {
        auto r = verbs.save;

        if (r.front == Path.Verb.Move)
            r.popFront;

        for (; !r.empty; r.popFront)
        {
            if (r.front == Path.Verb.Move)
                break;
            if (r.front == Path.Verb.Close)
                return true;
        }
        return false;
    }

    unittest
    {
        // primitives: the first one implies a moveTo; relative variants map
        // through the last point; close() only emits when it makes sense
        Path p;
        assert(p.empty);
        assert(p.bounds == FRect.emptyRect);
        assert(!p.lastVerbWas(Path.Verb.Move));

        p.lineTo(FPoint(5, 5));
        assert(p.verbs == [Path.Verb.Move]);
        assert(p.points == [FPoint(5, 5)]);
        assert(p.lastVerbWas(Path.Verb.Move));

        p.relLineTo(FVector(5, 0));
        assert(p.points[$-1] == FPoint(10, 5));
        p.relMoveTo(FVector(-10, -5));
        assert(p.points[$-1] == FPoint(0, 0));
        p.relQuadTo(FVector(5, 0), FVector(5, 5));
        assert(p.points[$-3 .. $] == [FPoint(0, 0), FPoint(5, 0), FPoint(5, 5)]);
        p.relCubicTo(FVector(-1, 0), FVector(-1, -1), FVector(-5, -5));
        assert(p.points[$-1] == FPoint(0, 0));

        // SVG "M 0 0 Z M 10 10": close() skips the empty subpath, so the
        // following moveTo must not see a dangling Move verb.
        p = Path.init;
        p.moveTo(FPoint(0, 0));
        p.close(); // empty subpath: no verb emitted
        p.moveTo(FPoint(1, 1)); // replaces the dangling Move
        assert(p.points == [FPoint(1, 1)]);
        assert(p.verbs == [Path.Verb.Move]);
        p.lineTo(FPoint(2, 2));
        assert(p.verbs == [Path.Verb.Move, Path.Verb.Line]);

        p = Path.init;
        p.moveTo(FPoint(0, 0));
        p.close(); // Move -> no Close verb
        assert(p.verbs == [Path.Verb.Move]);
        p.lineTo(FPoint(1, 0));
        p.close();
        p.close(); // idempotent
        assert(p.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Close]);
    }

    unittest
    {
        // shape adders: verbs, bounds, winding direction and the
        // radius-capping branches of addRoundRect
        Path p;
        p.addRect(FRect(0, 0, 10, 20));
        assert(p.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line,
                           Path.Verb.Line, Path.Verb.Close]);
        assert(p.bounds == FRect(0, 0, 10, 20));

        Path q;
        q.addRect(FRect(0, 0, 10, 20), Path.Direction.CCW);
        assert(q.verbs == p.verbs);
        assert(q.bounds == p.bounds);
        assert(q.points != p.points);

        // addOval: four cubic arcs (CUBIC_ARC) plus move/close, both windings
        p = Path.init;
        p.addOval(FRect(0, 0, 10, 20));
        assert(p.verbs.length == 6);
        assert(p.verbs[0] == Path.Verb.Move);
        assert(p.verbs[$-1] == Path.Verb.Close);
        assert(p.verbs[1 .. $-1].all!(v => v == Path.Verb.Cubic));
        assert(p.points.length == 13);
        assert(p.bounds == FRect(0, 0, 10, 20));

        p = Path.init;
        p.addOval(FRect(0, 0, 10, 10), Path.Direction.CCW);
        assert(p.verbs.length == 6 && p.lastVerbWas(Path.Verb.Close));

        // rounded rect: four corners, straight edges in between
        p = Path.init;
        p.addRoundRect(FRect(0, 0, 100, 60), 10, 10);
        assert(p.verbs[0] == Path.Verb.Move && p.verbs[$-1] == Path.Verb.Close);
        assert(count!(v => v == Path.Verb.Cubic)(p.verbs) == 4);
        assert(count!(v => v == Path.Verb.Line)(p.verbs) == 4);
        assert(p.bounds == FRect(0, 0, 100, 60));

        p = Path.init;
        p.addRoundRect(FRect(0, 0, 100, 60), 10, 10, Path.Direction.CCW);
        assert(count!(v => v == Path.Verb.Cubic)(p.verbs) == 4);
        assert(count!(v => v == Path.Verb.Line)(p.verbs) == 4);

        // one radius wider than half its extent: it caps at half, the other
        // keeps its straight edges
        p = Path.init;
        p.addRoundRect(FRect(0, 0, 20, 60), 12, 5); // rx capped
        assert(!p.empty && p.bounds == FRect(0, 0, 20, 60));
        p = Path.init;
        p.addRoundRect(FRect(0, 0, 100, 20), 5, 12); // ry capped
        assert(!p.empty && p.bounds == FRect(0, 0, 100, 20));

        // a fully round rect degrades into an oval
        p = Path.init;
        p.addRoundRect(FRect(0, 0, 100, 60), 50, 30);
        assert(!p.verbs.canFind(Path.Verb.Quad) && p.verbs.length == 6);

        // empty rect adds nothing
        p = Path.init;
        p.addRoundRect(FRect.emptyRect(), 5, 5);
        assert(p.empty);
    }

    unittest
    {
        // arcTo on an empty path emits a lone moveTo
        Path p;
        p.arcTo(FPoint(0, 0), FPoint(10, 0));
        assert(p.verbs == [Path.Verb.Move]);

        // small sweep stays one quad
        p = Path.init;
        p.moveTo(FPoint(10, 0));
        p.arcTo(FPoint(0, 0), FPoint(9.24f, 3.83f)); // ~22.5 deg
        assert(p.verbs == [Path.Verb.Move, Path.Verb.Quad]);

        // 90 degree sweep is subdivided into several quads
        p = Path.init;
        p.moveTo(FPoint(10, 0));
        p.arcTo(FPoint(0, 0), FPoint(0, 10));
        assert(p.verbs.length >= 3);
        assert(p.verbs[1 .. $].all!(v => v == Path.Verb.Quad));

        // addArc: pie slice, CW and CCW
        p = Path.init;
        p.addArc(FPoint(0, 0), FPoint(10, 0), FPoint(0, 10));
        assert(p.verbs[0] == Path.Verb.Move && p.verbs[1] == Path.Verb.Line);
        assert(p.verbs[$-1] == Path.Verb.Line);
        assert(p.bounds.contains(FPoint(0, 0)));

        Path ccw;
        ccw.addArc(FPoint(0, 0), FPoint(10, 0), FPoint(0, 10), Path.Direction.CCW);
        assert(ccw.verbs[0] == Path.Verb.Move && ccw.verbs[1] == Path.Verb.Line);
        assert(ccw.verbs[$-1] == Path.Verb.Line);

        // addPath concatenates
        Path a, b;
        a.moveTo(FPoint(0, 0));
        a.lineTo(FPoint(1, 1));
        b.moveTo(FPoint(2, 2));
        b.lineTo(FPoint(3, 3));
        a.addPath(b);
        assert(a.verbs.length == 4);
        assert(a.points[$-1] == FPoint(3, 3));
    }

    unittest
    {
        // apply(): every verb is emitted with its start point prepended, and
        // Close synthesizes a closing line
        Path p;
        p._verbs.put(Path.Verb.Move);
        p._points.put(FPoint(1, 1));
        p._verbs.put(Path.Verb.Line);
        p._points.put(FPoint(1, 3));
        p._verbs.put(Path.Verb.Quad);
        p._points.put([FPoint(2, 4), FPoint(3, 3)]);
        p._verbs.put(Path.Verb.Cubic);
        p._points.put([FPoint(4, 2), FPoint(2, -1), FPoint(0, 0)]);
        p._verbs.put(Path.Verb.Close);

        Verb[] verbExp = [Path.Verb.Move, Path.Verb.Line, Path.Verb.Quad, Path.Verb.Cubic, Path.Verb.Line, Path.Verb.Close];
        FPoint[][] ptsExp = [
            [FPoint(1,1)],
            [FPoint(1,1), FPoint(1,3)],
            [FPoint(1,3), FPoint(2,4), FPoint(3,3)],
            [FPoint(3,3), FPoint(4,2), FPoint(2,-1), FPoint(0,0)],
            [FPoint(0,0), FPoint(1,1)],
            [],
        ];

        foreach(verb, pts; p)
        {
            assert(verb == verbExp[0]);
            assert(pts == ptsExp[0]);
            verbExp.popFront();
            ptsExp.popFront();
        }

        assert(p.isClosedContour() == true);
        assert(p.empty() == false);

        // a nonzero callback return aborts the walk at each emit site:
        // Move, primitive, synthesized closing line, Close
        Path tri;
        tri.moveTo(FPoint(0, 0));
        tri.lineTo(FPoint(1, 0));
        tri.close();
        foreach (abortAt; 1 .. 5)
        {
            int seen;
            auto res = tri.apply((ref Path.Verb verb, ref FPoint[] pts) {
                ++seen;
                return seen == abortAt ? 7 : 0;
            });
            assert(res == 7 && seen == abortAt);
        }

        // two subpaths without a Close: not a closed contour
        Path twoSubpaths;
        twoSubpaths.moveTo(FPoint(0, 0));
        twoSubpaths.lineTo(FPoint(1, 0));
        twoSubpaths.moveTo(FPoint(2, 0));
        twoSubpaths.lineTo(FPoint(3, 0));
        assert(!twoSubpaths.isClosedContour);
    }

    unittest
    {
        // reversePathTo skips the source's initial moveTo and flips Quad,
        // Line and Cubic segments; an empty source is a no-op
        Path quad;
        quad.moveTo(FPoint(100, 100));
        quad.quadTo(FPoint(40, 60), FPoint(0, 0));
        Path path;
        path.moveTo(FPoint(0, 0));
        path.reversePathTo(quad);
        assert(path.verbs == [Path.Verb.Move, Path.Verb.Quad], to!string(path.verbs));
        assert(path.points == [FPoint(0, 0), FPoint(40, 60), FPoint(100, 100)], to!string(path.points));

        Path mixed;
        mixed.moveTo(FPoint(0, 0));
        mixed.lineTo(FPoint(4, 0));
        mixed.cubicTo(FPoint(5, 1), FPoint(6, 2), FPoint(7, 0));
        path = Path.init;
        path.reversePathTo(Path.init);
        assert(path.empty);
        path.moveTo(FPoint(9, 9));
        path.reversePathTo(mixed);
        assert(path.verbs == [Path.Verb.Move, Path.Verb.Cubic, Path.Verb.Line]);
        assert(path.lastPoint == FPoint(0, 0));
    }

    unittest
    {
        // MutablePathData instantiation: its mutable reset() plus a walk
        // through the verb helpers
        MutablePathData md;
        assert(md.empty);
        md.lineTo(FPoint(1, 1)); // a primitive with no preceding point emits a Move
        assert(md.verbs == [Path.Verb.Move] && md.lastPoint == FPoint(1, 1));
        md.lineTo(FPoint(3, 3));
        assert(md.lastVerbWas(Path.Verb.Line) && md.lastPoint == FPoint(3, 3));
        md.relMoveTo(FVector(1, 0));
        md.relLineTo(FVector(1, 1));
        md.relQuadTo(FVector(0, 1), FVector(1, 1));
        md.relCubicTo(FVector(1, 0), FVector(1, 1), FVector(1, 2));
        assert(md.lastVerbWas(Path.Verb.Cubic) && md.lastPoint == FPoint(7, 7));
        md.close();
        assert(md.lastVerbWas(Path.Verb.Close));
        md.reset();
        assert(md.empty && md.points.length == 0 && md.verbs.length == 0);
    }

    unittest
    {
        // Path helpers: ibounds, toString, resetting the immutable data
        Path p;
        p.moveTo(FPoint(0.5, 0));
        p.lineTo(FPoint(4, 2));
        p.close();
        assert(p.ibounds == IRect(0, 0, 4, 2));
        auto s = p.toString;
        assert(s.canFind("Path, bounds:") && s.canFind("Close"));
        p._data.reset();
        assert(p.empty && p.bounds == FRect.emptyRect);
    }
}
