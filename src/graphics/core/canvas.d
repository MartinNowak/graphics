module graphics.core.canvas;

import guip.bitmap, guip.point, guip.rect;
import graphics.core.pmcolor, graphics.core.draw, graphics.core.matrix, graphics.core.paint, graphics.core.path;

/**
*/
class Canvas
{
private:
    Bitmap _bitmap;
    MCRec[] _mcRecs;

    static struct MCRec
    {
        IRect _clip;
        Matrix _matrix;
    }

public:
    /** Construct a canvas with the specified device to draw into.
     * Params:
     *     bitmap   Specifies the bitmap for the canvas to draw into.
     */
    this(Bitmap bitmap)
    {
        _mcRecs ~= MCRec(bitmap.bounds);
        _bitmap = bitmap;
    }

    debug @property final size_t saveCount() const
    {
        return _mcRecs.length;
    }

    @property void bitmap(Bitmap bitmap)
    {
        _bitmap = bitmap;
        auto bounds = bitmap.bounds;
        foreach(ref rec; _mcRecs)
            rec._clip.intersect(bounds);
        curMCRec._clip = bounds;
    }

    @property inout(Bitmap) bitmap() inout
    {
        return _bitmap;
    }

    @property ref inout(Matrix) matrix() inout
    {
        return curMCRec._matrix;
    }

    void resetMatrix()
    {
        matrix.reset();
    }

    /****************************************
     * Draw functions
     */
    void drawPaint(Paint paint)
    {
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawPaint(paint);
    }

    void drawColor(in Color c)
    {
        drawPaint(Paint(c));
    }

    void drawARGB(ubyte a, ubyte r, ubyte g, ubyte b)
    {
        drawColor(color(a, r, g, b));
    }

    void drawPath(in Path path, Paint paint)
    {
        // TODO: quickReject
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawPath(path, paint);
    }

    /**
       Blends the given bitmap at the current position to the canvas.
    */
    void drawBitmap(in Bitmap bitmap, Paint paint)
    {
        //! TODO: quickReject
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawBitmap(bitmap, paint);
    }

    void drawRect(in FRect rect, Paint paint)
    {
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawRect(rect, paint);
    }

    void drawRect(in IRect rect, Paint paint)
    {
        drawRect(fRect(rect), paint);
    }

    final void drawRoundRect(in IRect rect, int rx, int ry, Paint paint)
    {
        return drawRoundRect(fRect(rect), rx, ry, paint);
    }

    void drawRoundRect(in FRect rect, float rx, float ry, Paint paint)
    {
        if (rx > 0 && ry > 0)
        {
            Path path;
            path.addRoundRect(rect, rx, ry, Path.Direction.CW);
            drawPath(path, paint);
        }
        else
        {
            drawRect(rect, paint);
        }
    }

    final void drawOval(in IRect rect, Paint paint)
    {
        drawOval(fRect(rect), paint);
    }

    void drawOval(in FRect rect, Paint paint)
    {
        Path path;
        path.addOval(rect);
        drawPath(path, paint);
    }

    final void drawCircle(IPoint c, float radius, Paint paint)
    {
        return drawCircle(fPoint(c), radius, paint);
    }

    void drawCircle(FPoint c, float radius, Paint paint)
    {
        auto topL = FPoint(c.x - radius, c.y - radius);
        auto botR = topL + FPoint(2*radius, 2*radius);
        auto rect = FRect(topL, botR);

        Path path;
        path.addOval(rect);
        drawPath(path, paint);
    }

    final void drawText(string text, float x, float y, TextPaint paint)
    {
        return drawText(text, FPoint(x, y), paint);
    }

    void drawText(string text, FPoint pt, TextPaint paint)
    {
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawText(text, pt, paint);
    }

    final void drawText(string text, IPoint pt, TextPaint paint)
    {
        return drawText(text, fPoint(pt), paint);
    }

    void drawTextOnPath(string text, in Path path, TextPaint paint)
    {
        auto draw = Draw(_bitmap, curMCRec._matrix, curMCRec._clip);
        draw.drawTextOnPath(text, path, paint);
    }

    private bool quickReject(in IRect rect) const
    {
        if (curMCRec._clip.empty)
            return true;

        FRect mapped = curMCRec._matrix.mapRect(fRect(rect));
        auto ir = mapped.roundOut();
        return !ir.intersects(curMCRec._clip);
    }

    private bool quickReject(in Path path) const
    {
        return path.empty || quickReject(path.bounds.roundOut());
    }

    /*
     * Sets the current clipping to an Intersection with rect. Returns
     * true if resulting clipping is non-empty.
     */
    bool clipRect(in IRect rect)
    {
        FRect mapped = curMCRec._matrix.mapRect(fRect(rect));
        auto ir = mapped.round();
        if (curMCRec._clip.intersect(ir))
            return true;
        curMCRec._clip = IRect();
        return false;
    }

    // transformations

    final void translate(IPoint pt)
    {
        translate(pt.x, pt.y);
    }

    final void translate(FPoint pt)
    {
        translate(pt.x, pt.y);
    }

    void translate(float dx, float dy)
    {
        matrix = matrix.preTranslate(dx, dy);
    }

    final void scale(FVector v)
    {
        scale(v.x, v.y);
    }

    void scale(float xs, float ys)
    {
        matrix = matrix.preScale(xs, ys);
    }

    void rotate(float deg)
    {
        matrix = matrix.preRotate(deg);
    }

    final void rotate(float deg, FPoint pt)
    {
        rotate(deg, pt.x, pt.y);
    }

    void rotate(float deg, float px, float py)
    {
        matrix = matrix.preRotate(deg, px, py);
    }

    void skewX(float sx)
    {
        matrix = matrix.preSkewX(sx);
    }

    void skewY(float sy)
    {
        matrix = matrix.preSkewY(sy);
    }

    /****************************************
     * Stub
     */
    size_t save()
    {
        return internalSave();
    }

    void restore()
    {
        assert(_mcRecs.length > 0);
        _mcRecs = _mcRecs[0 .. $-1];
    }

    void restoreCount(size_t sc)
    {
        assert(sc <= _mcRecs.length);
        _mcRecs = _mcRecs[0 .. sc];
    }

    private size_t internalSave()
    {
        _mcRecs ~= curMCRec;
        return _mcRecs.length - 1;
    }

    @property private ref inout(MCRec) curMCRec() inout
    {
        assert(_mcRecs.length > 0);
        return _mcRecs[$ - 1];
    }
}
