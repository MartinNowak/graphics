module graphics.core.stroke;

import graphics.core.paint, graphics.core.path;
import guip.point;
import graphics.core.stroke_detail._;

struct Stroke
{
    float _radius;
    //  float invMiterLimit;

    FVector _prevNormal;
    Path _outer;
    Path _inner;
    Path _result;

    Capper _capper;
    Joiner _joiner;
    bool _fillSrcPath;

    this(in Paint paint, float width)
    {
        assert(width > 0);
        _radius = width * 0.5;
        _capper = getCapper(paint.capStyle);
        _joiner = getJoiner(paint.joinStyle);
        _fillSrcPath = paint.fillStyle == Paint.Fill.FillAndStroke;
    }

    void done()
    {
        if (!_outer.empty)
            finishContour(false);
    }

    void close()
    {
        assert(!_outer.empty);
        finishContour(true);
    }

    FVector getNormal(FPoint pt1, FPoint pt2)
    {
        FVector normal = pt1 - pt2;
        normal.setLength(_radius);
        normal.rotateCCW();
        return normal;
    }

    Path strokePath(in Path path)
    {
        if (_radius <= 0)
            return Path();

        path.forEach!QuadCubicFlattener((Path.Verb verb, in FPoint[] pts)
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
        });

        done();

        if (_fillSrcPath)
            _result.addPath(path);

        return _result;
    }

    void join(FPoint pt, FVector normalAfter)
    {
        if (!_outer.empty)
        {
            _joiner(pt, _prevNormal, normalAfter, _inner, _outer);
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

        if (close)
        {
            auto firstNormal = getNormal(opts[0], opts[1]);
            FPoint pt = (_inner.points[$-1] + opts[$-1]) * 0.5;
            join(pt, firstNormal);
            _outer.close();

            _outer.moveTo(_inner.points[$-1]);
            _outer.reversePathTo(_inner);
            _outer.close();
        }
        else
        {
            FVector normal = getNormal(opts[$-1], opts[$-2]);
            FPoint pt = (_inner.points[$-1] + opts[$-1]) * 0.5;
            _capper(pt, normal, _outer);

            _outer.reversePathTo(_inner);
            assert(_inner.points[0] == _outer.points[$-1]);

            auto firstNormal = getNormal(opts[0], opts[1]);
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

    void lineTo(in FPoint[] pts)
    in
    {
        assert(pts.length == 2);
        assert(!degenerate(pts[0], pts[1]));
    }
    body
    {
        auto normal = getNormal(pts[0], pts[1]);
        join(pts[0], normal);

        _outer.lineTo(pts[1] + normal);
        _inner.lineTo(pts[1] - normal);

        _prevNormal = normal;
    }

    void quadTo(in FPoint[] pts)
    in
    {
        assert(pts.length == 3);
        assert(!degenerate(pts[0], pts[1]));
        assert(!degenerate(pts[1], pts[2]));
    }
    body
    {
        auto normalAB = getNormal(pts[0], pts[1]);
        join(pts[0], normalAB);

        auto normalBC = getNormal(pts[1], pts[2]);
        auto normalB = getNormal(pts[0], pts[2]);

        _outer.quadTo(pts[1] + normalB, pts[2] + normalBC);
        _inner.quadTo(pts[1] - normalB, pts[2] - normalBC);

        _prevNormal = normalBC;
    }

    void cubicTo(in FPoint[] pts)
    in
    {
        assert(pts.length == 4);
        assert(!degenerate(pts[0], pts[1]));
        assert(!degenerate(pts[2], pts[3]));
    }
    body
    {
        auto normalAB = getNormal(pts[0], pts[1]);
        join(pts[0], normalAB);

        auto normalCD = getNormal(pts[2], pts[3]);
        auto normalB = getNormal(pts[0], pts[2]);
        auto normalC = getNormal(pts[1], pts[3]);

        _outer.cubicTo(pts[1] + normalB, pts[2] + normalC, pts[3] + normalCD);
        _inner.cubicTo(pts[1] - normalB, pts[2] - normalC, pts[3] - normalCD);

        _prevNormal = normalCD;
    }
}
