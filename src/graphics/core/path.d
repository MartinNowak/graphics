module graphics.core.path;

import std.algorithm, std.array, std.conv, std.math, std.numeric, std.range, std.traits, core.stdc.string;
import graphics.bezier.chop, graphics.core.matrix, graphics.core.patheffect, graphics.core.path_detail._;
import guip.point, guip.rect;

public import graphics.core.path_detail._ : QuadCubicFlattener;

debug import std.stdio : writeln, printf;
version=CUBIC_ARC;

// TODO: FPoint -> Point!T
struct Path
{
    Appender!(FPoint[]) _points;
    Appender!(Verb[]) _verbs;

private:
    FRect _bounds;
    PathEffect[] _pathEffects;
    bool _boundsIsClean;

public:

    void reset()
    {
        _points.clear();
        _verbs.clear();
        _boundsIsClean = false;
        _bounds = FRect();
    }

    enum Verb : ubyte
    {
        Move = 0,
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

    private enum CubicArcFactor = (SQRT2 - 1.0) * 4.0 / 3.0;

    string toString() const
    {
        string res;
        res ~= "Path, bounds: " ~ to!string(_bounds) ~ "\n";
        foreach(verb, pts; this)
        {
            res ~= to!string(verb) ~ ": ";
            foreach(FPoint pt; pts)
                res ~= to!string(pt) ~ ", ";
            res ~= "\n";
        };
        return res;
    }

    // TODO: less copying, maybe COW
    this(in Path path)
    {
        this = path;
    }

    // TODO: less copying, maybe COW
    void opAssign(in Path path)
    {
        _points.clear();
        _points.put(path.points);
        _verbs.clear();
        _verbs.put(path.verbs);
        _bounds = path._bounds;
        _boundsIsClean = path._boundsIsClean;
    }

    @property bool empty() const
    {
        return verbs.length == 0 ||
            verbs.length == 1 && verbs[0] == Verb.Move;
    }

    // TODO: check if const is needed
    @property FRect bounds() const
    {
        if (!_boundsIsClean)
        {
            auto pthis = cast(Path*)&this;
            pthis._bounds = calcBounds();
            pthis._boundsIsClean = true;
        }
        return _bounds;
    }

    @property IRect ibounds() const
    {
        return bounds.roundOut();
    }

    private FRect calcBounds() const
    {
        if (!points.empty)
        {
            return FRect.calcBounds(points);
        }
        else
        {
            return FRect.emptyRect();
        }
    }

    void addPathEffect(PathEffect effect)
    {
        _pathEffects ~= effect;
    }

    @property const(Path) filteredPath() const
    {
        Path result;
        result = this;
        foreach(effect; _pathEffects)
            result = effect(result);
        return result;
    }

    private void joinBounds(FRect bounds)
    {
        if (_boundsIsClean)
            _bounds.join(bounds);
    }

    alias int delegate(ref Verb, ref FPoint[]) IterDg;
    int apply(Flattener=void)(scope IterDg dg) const
    {
        if (empty)
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
            case Verb.Move:
                moveTo = lastPt = tmpPts[0] = pts.front;
                pts.popFront;
                if (auto res = emit(Verb.Move, tmpPts[0 .. 1]))
                    return res;
                break;

            case Verb.Line, Verb.Quad, Verb.Cubic:
                tmpPts[0] = lastPt;
                memcpy(tmpPts.ptr + 1, pts.ptr, verb * FPoint.sizeof);
                lastPt = pts[verb - 1];
                popFrontN(pts, verb);
                if (auto res = emit(verb, tmpPts[0 .. verb + 1]))
                    return res;
                break;

            case Verb.Close:
                if (lastPt != moveTo)
                {
                    tmpPts[0] = lastPt;
                    tmpPts[1] = moveTo;
                    if (auto res = emit(Verb.Line, tmpPts[0 .. 2]))
                        return res;
                    lastPt = moveTo;
                }
                if (auto res = emit(Verb.Close, tmpPts[0 .. 0]))
                    return res;
            }
        }
        return 0;
    }

    alias apply!() opApply;

    bool isClosedContour()
    {
        auto r = verbs.save;

        if (r.front == Verb.Move)
            r.popFront;

        for (; !r.empty; r.popFront)
        {
            if (r.front == Verb.Move)
                break;
            if (r.front == Verb.Close)
                return true;
        }
        return false;
    }

    @property const(FPoint)[] points() const
    {
        return (cast()_points).data.save;
    }

    @property FPoint lastPoint() const
    {
        return points[$-1];
    }

    @property Verb[] verbs() const
    {
        return (cast()_verbs).data.save;
    }

    bool lastVerbWas(Verb verb) const
    {
        return verbs.length == 0 ? false : verbs[$-1] == verb;
    }

    void primTo(const(FPoint)[] pts...)
    {
        // implicit moveTo when no preceded by point
        if (_verbs.data.empty)
        {
            _points.put(pts[$-1]);
            _verbs.put(Verb.Move);
        }
        else
        {
            _points.put(pts);
            _verbs.put(cast(Verb)pts.length);
            _boundsIsClean = false;
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
        if (lastVerbWas(Verb.Move))
        {
            _points.data[$-1] = pt;
        }
        else
        {
            _points.put(pt);
            _verbs.put(Verb.Move);
        }
        _boundsIsClean = false;
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
            case Verb.Line, Verb.Quad, Verb.Cubic:
                _verbs.put(Verb.Close);
                break;

            case Verb.Close:
                break;

            case Verb.Move:
                assert(0, "Can't close path when last operation was a moveTo");
            }
        }
    }

    void addPath(in Path path)
    {
        _verbs.put(path.verbs);
        _points.put(path.points);
        _boundsIsClean = false;
    }

    void reversePathTo(in Path path)
    {
        if (path.empty)
            return;

        debug auto initialLength= this.verbs.length;
        _verbs.reserve(verbs.length + path.verbs.length);
        _points.reserve(points.length + path.points.length);

        //! skip initial moveTo
        assert(verbs.front == Verb.Move);
        auto vs = path.verbs[1..$].retro;
        auto rpts = path.points[0..$-1].retro;

        for (; !vs.empty; vs.popFront)
        {
            auto verb = vs.front;
            switch (verb)
            {
            case Verb.Line:
                primTo(rpts[0]);
                rpts.popFront;
                break;

            case Verb.Quad:
                primTo(rpts[0], rpts[1]);
                popFrontN(rpts, 2);
                break;

            case Verb.Cubic:
                primTo(rpts[0], rpts[1], rpts[2]);
                popFrontN(rpts, 3);
                break;

            default:
                assert(0, "bad verb in reversePathTo: " ~ to!string(path.verbs));
            }
        }
        assert(rpts.empty);
    }

    unittest
    {
        Path rev;
        rev.moveTo(FPoint(100, 100));
        rev.quadTo(FPoint(40,60), FPoint(0, 0));
        Path path;
        path.moveTo(FPoint(0, 0));
        path.reversePathTo(rev);
        assert(path.verbs == [Verb.Move, Verb.Quad], to!string(path.verbs));
        assert(path.points == [FPoint(0, 0), FPoint(40, 60), FPoint(100, 100)], to!string(path.points));
    }

    void addRect(in FRect rect, Direction dir = Direction.CW)
    {
        FPoint[4] quad = rect.toQuad;

        if (dir == Direction.CCW)
            swap(quad[1], quad[3]);

        moveTo(quad[0]);
        foreach(ref pt; quad[1..$])
        {
            lineTo(pt);
        }
        close();
    }

    void addRoundRect(FRect rect, float rx, float ry, Direction dir = Direction.CW)
    {
        scope(success) joinBounds(rect);
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

        if (dir == Direction.CCW)
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

    void addOval(FRect oval, Direction dir = Direction.CW)
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
            if (dir == Direction.CCW)
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
            if (dir == Direction.CCW)
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

    void arcTo(FPoint center, FPoint endPt, Direction dir = Direction.CW)
    {
        // implicit moveTo when no preceded by point
        if (_verbs.data.empty)
        {
            _points.put(endPt);
            _verbs.put(Verb.Move);
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
        if (dir == Direction.CCW)
            sweepAngle -= 2*PI;

        assert(abs(sweepAngle) <= 2*PI);
        FPTemporary!float midAngle = startAngle + 0.5 * sweepAngle;
        immutable cossin = expi(midAngle);
        auto middle = FVector(cossin.re, cossin.im);

        if (abs(sweepAngle) > PI_4)
        {   //! recurse
            middle.setLength(radius);
            FPoint middlePt = center + middle;
            arcTo(center, middlePt, dir);
            arcTo(center, endPt, dir);
        }
        else
        {   //! based upon a deltoid, calculate length of the long axis.
            FPTemporary!float hc = 0.5 * (startPt - endPt).length;
            FPTemporary!float b = hc / sin(0.5 * (PI - abs(sweepAngle)));
            FPTemporary!float longAxis = sqrt(radius * radius + b * b);
            middle.setLength(longAxis);
            quadTo(center + middle, endPt);
        }
    }

    void addArc(FPoint center, FPoint startPt, FPoint endPt, Direction dir = Direction.CW)
    {
        moveTo(center);
        lineTo(startPt);
        arcTo(center, endPt, dir);
        lineTo(center);
    }

    Path transformed(in Matrix matrix) const
    {
        Path res;
        res = this;
        res.transform(matrix);
        return res;
    }

    void transform(in Matrix matrix)
    {
        if (matrix.perspective)
        {
            Path tmp;
            tmp._verbs.reserve(this._verbs.data.length);
            tmp._points.reserve(this._points.data.length);

            foreach(verb, pts; &apply!QuadCubicFlattener)
            {
                tmp._verbs.put(verb);
                tmp._points.put(pts);
            };
            this = tmp;
        }
        else
        {
            if (matrix.rectStaysRect && this.points.length > 1)
            {
                FRect mapped;
                matrix.mapRect(this.bounds, mapped);
                this._bounds = mapped;
            }
            else
            {
                _boundsIsClean = false;
            }
        }
        matrix.mapPoints(this._points.data);
    }

    unittest
    {
        Path p;
        p._verbs.put(Verb.Move);
        p._points.put(FPoint(1, 1));
        p._verbs.put(Verb.Line);
        p._points.put(FPoint(1, 3));
        p._verbs.put(Verb.Quad);
        p._points.put([FPoint(2, 4), FPoint(3, 3)]);
        p._verbs.put(Verb.Cubic);
        p._points.put([FPoint(4, 2), FPoint(2, -1), FPoint(0, 0)]);
        p._verbs.put(Verb.Close);

        Verb[] verbExp = [Verb.Move, Verb.Line, Verb.Quad, Verb.Cubic, Verb.Line, Verb.Close];
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
    }
}
