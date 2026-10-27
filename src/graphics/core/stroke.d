module graphics.core.stroke;

import graphics.core.paint, graphics.core.path;
import guip.point;
import graphics.core.stroke_detail._;

struct Stroke
{
    float _radius;
    float _miterLimit;

    FVector _prevNormal;
    MutablePathData _outer;
    MutablePathData _inner;
    Path _result;

    Capper _capper;
    Joiner _joiner;

    this(float width, CapStyle caps, JoinStyle joins, float miterLimit = 4)
    {
        assert(width > 0);
        _radius = width * 0.5;
        _miterLimit = miterLimit;
        _capper = getCapper(caps);
        _joiner = getJoiner(joins);
    }

    void done()
    {
        if (!_outer.empty)
            finishContour(false);
    }

    void close()
    {
        // A subpath made entirely of degenerate segments leaves no contour
        // behind; per SVG it is then a zero-length subpath, which the butt
        // capper does not render.
        if (_outer.empty)
            return;
        finishContour(true);
    }

    FVector getNormal(FPoint pt1, FPoint pt2)
    {
        FVector normal = pt1 - pt2;
        normal = normal.scaledTo(_radius);
        normal = normal.rotatedCCW();
        return normal;
    }

    Path strokePath(in Path path)
    {
        if (_radius <= 0)
            return Path();

        foreach(verb, pts; path)
        {
            final switch(verb)
            {
            case Path.Verb.Move:
                moveTo(pts[0]);
                break;
            case Path.Verb.Line:
                lineTo(pts);
                break;
            case Path.Verb.Quad:
                quadTo(pts);
                break;
            case Path.Verb.Cubic:
                cubicTo(pts);
                break;
            case Path.Verb.Close:
                close();
            }
        }

        done();

        return _result;
    }

    void join(FPoint pt, FVector normalAfter)
    {
        if (!_outer.empty)
        {
            _joiner(pt, _prevNormal, normalAfter, _inner, _outer, _miterLimit);
        }
        else
        {
            _inner.moveTo(pt - normalAfter);
            _outer.moveTo(pt + normalAfter);
        }
    }

    void finishContour(bool close)
    {
        const opts = _outer.points;

        // Beziers whose first (or last) handle coincides with their
        // endpoint leave consecutive identical points in the offset
        // contour; the segment between them has zero length, so no
        // normal can be computed there. Skip such duplicates when
        // finding the direction of the first and last segments.
        size_t k = 1;
        while (k < opts.length && degenerate(opts[0], opts[k]))
            ++k;
        if (k == opts.length)
        {
            // The whole contour degenerates to a single point; there is
            // nothing to stroke.
            _inner.reset();
            _outer.reset();
            return;
        }

        size_t j = 0;
        if (!close)
        {
            j = opts.length - 2;
            while (j > 0 && degenerate(opts[j], opts[$-1]))
                --j;
            if (degenerate(opts[j], opts[$-1]))
            {
                // Like the k loop, but from the end; if even the first
                // point lies within tolerance of the last one, the whole
                // contour is point-like and the cap normal is undefined.
                _inner.reset();
                _outer.reset();
                return;
            }
        }

        if (close)
        {
            auto firstNormal = getNormal(opts[0], opts[k]);
            FPoint pt = (_inner.points[$-1] + opts[$-1]) * 0.5;
            join(pt, firstNormal);
            _outer.close();

            _outer.moveTo(_inner.points[$-1]);
            _outer.reversePathTo(_inner);
            _outer.close();
        }
        else
        {
            FVector normal = getNormal(opts[$-1], opts[j]);
            FPoint pt = (_inner.points[$-1] + opts[$-1]) * 0.5;
            _capper(pt, normal, _outer);

            _outer.reversePathTo(_inner);
            assert(_inner.points[0] == _outer.points[$-1]);

            auto firstNormal = getNormal(opts[0], opts[k]);
            pt = (_inner.points[0] + opts[0]) * 0.5;
            _capper(pt, firstNormal, _outer);
            _outer.close();
        }

        _result.addPath(_outer);
        _inner.reset();
        _outer.reset();
    }

    void moveTo(FPoint pt)
    {
        if (!_outer.empty)
        {
            finishContour(false);
        }
    }

    private static bool degenerate(FPoint pt1, FPoint pt2)
    {
        enum tol = 1e-3;
        return distance(pt1, pt2) < tol;
    }

    // A bezier with a degenerate handle (control point coinciding with an
    // endpoint) is valid SVG, but its tangent vanishes at that endpoint;
    // fall back to the outward control points for the tangent direction.
    // The tolerance of degenerate() is not transitive, so all candidates
    // can lie within tolerance of from even though the segment guards in
    // quadTo and cubicTo passed; such a segment spans no more than twice
    // the tolerance, so return the farthest candidate to keep the chord
    // non-zero. An assert here would be stripped from release builds and
    // leave the return value undefined.
    private static FPoint tangent(FPoint from, in FPoint[] cands)
    {
        assert(cands.length);
        FPoint farthest = cands[0];
        double farthestDist = 0.0;
        foreach(cand; cands)
        {
            if (!degenerate(from, cand))
                return cand;
            auto dist = distance(from, cand);
            if (dist > farthestDist)
            {
                farthestDist = dist;
                farthest = cand;
            }
        }
        // Unreachable: full coincidence of all candidates with from is
        // rejected by the guards in quadTo and cubicTo.
        assert(farthestDist > 0.0);
        return farthest;
    }

    void lineTo(in FPoint[] pts)
    {
        assert(pts.length == 2);
        if (degenerate(pts[0], pts[1]))
            return;
        auto normal = getNormal(pts[0], pts[1]);
        join(pts[0], normal);

        _outer.lineTo(pts[1] + normal);
        _inner.lineTo(pts[1] - normal);

        _prevNormal = normal;
    }

    void quadTo(in FPoint[] pts)
    {
        assert(pts.length == 3);
        if (degenerate(pts[0], pts[1]) && degenerate(pts[0], pts[2]))
            return;
        auto normalAB = getNormal(pts[0], tangent(pts[0], [pts[1], pts[2]]));
        join(pts[0], normalAB);

        auto normalBC = getNormal(tangent(pts[2], [pts[1], pts[0]]), pts[2]);
        auto normalB = getNormal(pts[0], tangent(pts[0], [pts[2], pts[1]]));

        _outer.quadTo(pts[1] + normalB, pts[2] + normalBC);
        _inner.quadTo(pts[1] - normalB, pts[2] - normalBC);

        _prevNormal = normalBC;
    }

    void cubicTo(in FPoint[] pts)
    {
        assert(pts.length == 4);
        if (degenerate(pts[0], pts[1]) && degenerate(pts[0], pts[2]) &&
            degenerate(pts[0], pts[3]))
            return;
        auto normalAB = getNormal(pts[0], tangent(pts[0], [pts[1], pts[2], pts[3]]));
        join(pts[0], normalAB);

        auto normalCD = getNormal(tangent(pts[3], [pts[2], pts[1], pts[0]]), pts[3]);
        auto normalB = getNormal(pts[0], tangent(pts[0], [pts[2], pts[1], pts[3]]));
        auto normalC = getNormal(tangent(pts[3], [pts[1], pts[2], pts[0]]), pts[3]);

        _outer.cubicTo(pts[1] + normalB, pts[2] + normalC, pts[3] + normalCD);
        _inner.cubicTo(pts[1] - normalB, pts[2] - normalC, pts[3] - normalCD);

        _prevNormal = normalCD;
    }
}

unittest
{
    import std.math : isFinite;

    // Degenerate segments are valid SVG, but must never let a zero-length
    // chord reach getNormal: dividing by a zero length leaks NaN through
    // the whole contour.
    Path path;
    path.moveTo(FPoint(10, 10));
    path.lineTo(FPoint(10, 10)); // zero-length line
    path.cubicTo(FPoint(10, 10), FPoint(80, 80), FPoint(80, 10)); // degenerate start handle
    path.cubicTo(FPoint(80, 10), FPoint(80, 10), FPoint(80, 10)); // end collapses to a point
    path.quadTo(FPoint(80, 10), FPoint(20, 60)); // degenerate start handle
    path.quadTo(FPoint(20, 60), FPoint(20, 60)); // degenerate end handle
    path.lineTo(FPoint(20, 60)); // zero-length line

    path.moveTo(FPoint(200.0009, 100));
    // Tolerance drift: every control point is within tolerance of the
    // curve end, but dist(start, handle) exceeds it, so the segment-wide
    // guard passes while the tangent candidates at the end do not.
    path.cubicTo(FPoint(199.9991, 100), FPoint(200.0007, 100.0007), FPoint(200, 100));
    path.close();

    path.moveTo(FPoint(120, 120));
    path.lineTo(FPoint(120, 120));
    path.close(); // closes a contour whose only segment was dropped

    auto stroker = Stroke(4, CapStyle.Butt, JoinStyle.Miter);
    bool sawPoints = false;
    foreach(verb, pts; stroker.strokePath(path))
        foreach(pt; pts)
        {
            assert(isFinite(pt.x) && isFinite(pt.y));
            sawPoints = true;
        }
    assert(sawPoints);
}
