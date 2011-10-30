module graphics.core.stroke;

import graphics.core.paint, graphics.core.path;
import guip.point;
import graphics.core.stroke_detail._;

struct Stroke
{
    float radius;
    //  float invMiterLimit;

    FVector prevNormal;
    Path outer;
    Path inner;
    Path result;

    Capper capper;
    Joiner joiner;
    bool fillSrcPath;

    this(in Paint paint, float width)
    {
        assert(width > 0);
        this.radius = width * 0.5;
        this.capper = getCapper(paint.capStyle);
        this.joiner = getJoiner(paint.joinStyle);
        this.fillSrcPath = paint.fillStyle == Paint.Fill.FillAndStroke;
    }

    void done()
    {
        if (!this.outer.empty)
            this.finishContour(false);
    }

    void close()
    {
        assert(!this.outer.empty);
        this.finishContour(true);
    }

    FVector getNormal(FPoint pt1, FPoint pt2)
    {
        FVector normal = pt1 - pt2;
        normal.setLength(radius);
        normal.rotateCCW();
        return normal;
    }

    Path strokePath(in Path path)
    {
        if (radius <= 0)
            return Path();

        path.forEach!QuadCubicFlattener((Path.Verb verb, in FPoint[] pts)
        {
            final switch(verb)
            {
            case Path.Verb.Move:
                this.moveTo(pts[0]);
                break;
            case Path.Verb.Line:
                this.lineTo(pts);
                break;
            case Path.Verb.Quad:
                this.quadTo(pts);
                break;
            case Path.Verb.Cubic:
                this.cubicTo(pts);
                break;
            case Path.Verb.Close:
                this.close();
            }
        });

        this.done();

        if (this.fillSrcPath)
            this.result.addPath(path);

        return this.result;
    }

    void join(FPoint pt, FVector normalAfter)
    {
        if (!this.outer.empty)
        {
            this.joiner(pt, this.prevNormal, normalAfter, this.inner, this.outer);
        }
        else
        {
            this.inner.moveTo(pt - normalAfter);
            this.outer.moveTo(pt + normalAfter);
        }
    }

    void finishContour(bool close)
    {
        if (close)
        {
            auto firstNormal = this.getNormal(this.outer.points[0], this.outer.points[1]);
            FPoint pt = (this.inner.lastPoint + this.outer.lastPoint) * 0.5;
            this.join(pt, firstNormal);
            this.outer.close();

            this.outer.moveTo(this.inner.lastPoint);
            this.outer.reversePathTo(this.inner);
            this.outer.close();
        }
        else
        {
            FVector normal = this.getNormal(this.outer.pointsRetro[0], this.outer.pointsRetro[1]);
            FPoint pt = (this.inner.lastPoint + this.outer.lastPoint) * 0.5;
            this.capper(pt, normal, this.outer);

            this.outer.reversePathTo(this.inner);

            auto firstNormal = this.getNormal(this.outer.points[0], this.outer.points[1]);
            pt = (this.outer.pointsRetro[0] + this.outer.points[0]) * 0.5;
            this.capper(pt, firstNormal, this.outer);
            this.outer.close();
        }

        this.result.addPath(this.outer);
        this.inner.reset();
        this.outer.reset();
    }

    void moveTo(FPoint pt)
    {
        if (!this.outer.empty)
        {
            this.finishContour(false);
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
        this.join(pts[0], normal);

        this.outer.lineTo(pts[1] + normal);
        this.inner.lineTo(pts[1] - normal);

        this.prevNormal = normal;
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
        this.join(pts[0], normalAB);

        auto normalBC = getNormal(pts[1], pts[2]);
        auto normalB = getNormal(pts[0], pts[2]);

        this.outer.quadTo(pts[1] + normalB, pts[2] + normalBC);
        this.inner.quadTo(pts[1] - normalB, pts[2] - normalBC);

        this.prevNormal = normalBC;
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
        this.join(pts[0], normalAB);

        auto normalCD = getNormal(pts[2], pts[3]);
        auto normalB = getNormal(pts[0], pts[2]);
        auto normalC = getNormal(pts[1], pts[3]);

        this.outer.cubicTo(pts[1] + normalB, pts[2] + normalC, pts[3] + normalCD);
        this.inner.cubicTo(pts[1] - normalB, pts[2] - normalC, pts[3] - normalCD);

        this.prevNormal = normalCD;
    }
}
