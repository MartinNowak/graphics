module graphics.core.draw;

import std.array, std.conv;
import core.stdc.string;
import guip.point, guip.rect, guip.size, guip.bitmap;
import graphics.core.blitter, graphics.core.fonthost, graphics.core.glyph, graphics.core.matrix,
    graphics.core.paint, graphics.core.path, graphics.core.path_detail.path_measure,
    graphics.core.pmcolor, graphics.core.shader, graphics.core.wavelet.wavelet;
import graphics.math.clamp, graphics.math.poly;

struct Draw
{
public:
    Bitmap _bitmap;
    Matrix _matrix;
    IRect _clip;

    this(Bitmap bitmap)
    {
        _bitmap = bitmap;
    }

    this(Bitmap bitmap, in Matrix matrix, in IRect clip)
    {
        this(bitmap);
        _matrix = matrix;
        _clip = clip;
    }

    void drawPaint(Paint paint)
    {
        auto ir = _bitmap.bounds;
        if (ir.intersect(_clip))
            getBlitter(paint).blitRect(ir);
    }

    private Blitter getBlitter(Paint paint)
    {
        return Blitter.Choose(_bitmap, _matrix, paint);
    }

    private Blitter getBlitter(Paint paint, in Bitmap source, IPoint ioff)
    {
        return Blitter.ChooseSprite(_bitmap, paint, source, ioff);
    }

    void drawColor(in Color c)
    {
        _bitmap.eraseColor(PMColor(c));
    }

    void drawPath(in Path path, Paint paint)
    {
        if (_clip.empty || path.empty)
            return;

        scope Blitter blitter = getBlitter(paint);
        waveletBlitPath(path, _clip, _matrix, blitter);
    }

    void drawBitmap(in Bitmap source, Paint paint)
    {
        if (_clip.empty || source.bounds.empty ||
            source.config == Bitmap.Config.NoConfig ||
            paint.color.a == 0)
        {
            return;
        }

        auto ioff = IPoint(to!int(_matrix[0][2]), to!int(_matrix[1][2]));
        auto ir = IRect(ioff, ioff + source.size);

        if (_matrix.translativeOnly && source.config != Bitmap.Config.A8)
        {
            if (ir.intersect(_clip))
            {
                scope auto blitter = getBlitter(paint, source, ioff);
                blitter.blitRect(ir);
            }
        }
        else
        {
            if (source.config == Bitmap.Config.A8)
            {
                // TODO: need to apply transformation
                scope auto blitter = this.getBlitter(paint);
                blitter.blitMask(ioff.x, ioff.y, source);
            }
            else
            {
                Shader oldshader = paint.shader;
                scope(exit) paint.shader = oldshader;
                paint.shader = new BitmapShader(source);

                ir = IRect(source.size);
                drawRect(fRect(ir), paint);
            }
        }
    }

    void drawRect(in FRect rect, Paint paint)
    {
        FRect fr = rect;
        if (_clip.empty || !fr.intersect(fRect(_clip)))
            return;

        Path path;
        path.addRect(fr);
        drawPath(path, paint);
    }

    void drawText(string text, FPoint pt, TextPaint paint)
    {
        if (text.empty || _clip.empty ||
            paint.color.a == 0)
            return;

        auto backUp = _matrix;
        scope(exit) _matrix = backUp;

        auto cache = getGlyphCache(paint.typeFace, paint.textSize);

        float hOffset = 0;
        if (paint.textAlign != TextPaint.TextAlign.Left)
        {
            auto length = measureText(text, cache);
            if (paint.textAlign == TextPaint.TextAlign.Center)
                length *= 0.5;
            hOffset = length;
        }

        _matrix = _matrix.preTranslate(pt.x, pt.y);
        Matrix scaledMatrix = _matrix;
        // TODO: scale matrix according to freetype outline relation
        // auto scale = PathGlyphStream.getScale();
        // scaledMatrix.preScale(scale, scale);

        FPoint pos = FPoint(0, 0);
        foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path))
        {
            Matrix m;
            m.setTranslate(pos.x - hOffset, 0);
            _matrix = scaledMatrix * m;
            drawPath(gl.path, paint);
            pos += gl.advance;
        }
    }

    void drawTextOnPath(string text, in Path follow, TextPaint paint)
    {
        auto meas = PathMeasure(follow);

        float hOffset = 0;
        if (paint.textAlign != TextPaint.TextAlign.Left)
        {
            auto length = meas.length;
            if (paint.textAlign == TextPaint.TextAlign.Center)
                length *= 0.5;
            hOffset = length;
        }

        //! TODO: scaledMatrix

        auto cache = getGlyphCache(paint.typeFace, paint.textSize);
        FPoint pos = FPoint(0, 0);
        foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path))
        {
            Matrix m;
            m.setTranslate(pos.x + hOffset, 0);
            this.drawPath(morphPath(gl.path, meas, m), paint);
            pos += gl.advance;
        }
    }

    private Path morphPath(in Path path, in PathMeasure meas, in Matrix matrix)
    {
        Path dst;

        foreach(verb, pts; path)
        {
            final switch(verb)
            {
            case Path.Verb.Move:
                FPoint[1] mpts = void;
                mpts[0] = pts[0];
                morphPoints(mpts, meas, matrix);
                dst.moveTo(mpts[0]);
                break;

            case Path.Verb.Line:
                //! use quad to allow curvature
                FPoint[2] mpts = void;
                mpts[0] = (pts[0] + pts[1]) * 0.5f;
                mpts[1] = pts[1];
                morphPoints(mpts, meas, matrix);
                dst.quadTo(mpts[0], mpts[1]);
                break;

            case Path.Verb.Quad:
                FPoint[2] mpts = void;
                memcpy(mpts.ptr, pts.ptr, 2 * FPoint.sizeof);
                morphPoints(mpts, meas, matrix);
                dst.quadTo(mpts[0], mpts[1]);
                break;

            case Path.Verb.Cubic:
                FPoint[3] mpts = void;
                memcpy(mpts.ptr, pts.ptr, 3 * FPoint.sizeof);
                morphPoints(mpts, meas, matrix);
                dst.cubicTo(mpts[0], mpts[1], mpts[2]);
                break;

            case Path.Verb.Close:
                dst.close();
                break;
            }
        }
        return dst;
    }

    private void morphPoints(size_t K)(ref FPoint[K] pts, in PathMeasure meas, in Matrix matrix)
    {
        matrix.mapPoints(pts);

        for (size_t i = 0; i < K; ++i)
        {
            FVector normal;
            auto pos = meas.getPosAndNormalAtDistance(pts[i].x, normal);
            pts[i] = pos - normal * pts[i].y;
        }
    }
};

void waveletBlitPath(in Path path, IRect clip, ref const Matrix mat, Blitter blitter)
{
    FRect bounds = mat.mapRect(path.bounds);
    auto ir = bounds.roundOut;

    debug
    {
        auto outer = ir;
        // mapRect is exact for axis-aligned boxes but control points of
        // curved segments can round a hair outside it; give the check a
        // pixel of tolerance so it flags real escapes, not float noise.
        outer.left -= 2;
        outer.top -= 2;
        outer.right += 2;
        outer.bottom += 2;
        void checkPoints(FPoint[] pts)
        {
            foreach(pt; pts)
            {
                assert(fitsIntoRange!("[]")(pt.x, outer.left, outer.right)
                       && fitsIntoRange!("[]")(pt.y, outer.top, outer.bottom), std.conv.text(pt, " ", outer));
            }
        }
    }

    if (!ir.intersect(clip))
        return;
    WaveletRaster wr = WaveletRaster(ir);

    // Fills integrate closed contours: applyFilled synthesizes the
    // implicit closing edge for subpaths whose "Z" was left out.
    foreach(verb, pts; mat.perspective ? &path.applyFilled!(QuadCubicFlattener) : &path.applyFilled!())
    {
        final switch(verb)
        {
        case Path.Verb.Move:
        case Path.Verb.Close:
            break;

        case Path.Verb.Line:
            foreach(i; SIota!(0, 2))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[2]*)pts.ptr);
            break;
        case Path.Verb.Quad:
            foreach(i; SIota!(0, 3))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[3]*)pts.ptr);
            break;
        case Path.Verb.Cubic:
            foreach(i; SIota!(0, 4))
                pts[i] = mat * pts[i];
            debug checkPoints(pts);
            wr.insertEdge(*cast(FPoint[4]*)pts.ptr);
            break;
        }
    }

    // Pass 1: reconstruct the wavelet into the rasterizer's row-major
    // 8-bit alpha scratch bitmap. The quadtree's Z-order traversal only
    // touches one byte per pixel here, so it cannot thrash the
    // framebuffer.
    wr.blit();

    // Pass 2: hand the scratchpad to the blitter as an A8 mask. One
    // linear scanline pass, per-pixel alpha, the framebuffer streamed
    // exactly once.
    blitter.blitMask(ir.left, ir.top, wr.scratch);
}

unittest
{
    import graphics.core.testing : blackBitmap, inked, pixel, polyline, solidPaint;

    // drawColor ignores the clip and repaints the whole bitmap
    auto bm = blackBitmap(4, 4);
    Draw(bm).drawColor(Color.Green);
    assert(pixel(bm, 0, 0) == Color.Green && pixel(bm, 3, 3) == Color.Green);

    auto paint = solidPaint(Color.Red);

    // drawPaint fills the intersection of the device and the clip
    auto d = Draw(bm, Matrix(), IRect(0, 0, 2, 2));
    d.drawPaint(paint);
    assert(pixel(bm, 1, 1) == Color.Red);
    assert(pixel(bm, 2, 2) == PMColor(Color.Green)); // outside the clip

    // drawRect rasterizes through the wavelet path pipeline
    bm.eraseColor(Color.Black);
    auto d1 = Draw(bm, Matrix(), bm.bounds);
    d1.drawRect(FRect(1, 1, 3, 3), paint);
    assert(pixel(bm, 1, 1) == Color.Red);
    assert(pixel(bm, 2, 2) == Color.Red);
    assert(pixel(bm, 3, 3) == PMColor(Color.Black));

    // drawPath: a right triangle covering the upper-left half
    bm.eraseColor(Color.Black);
    Path tri;
    tri.moveTo(FPoint(0, 0));
    tri.lineTo(FPoint(4, 0));
    tri.lineTo(FPoint(0, 4));
    tri.close();
    d1.drawPath(tri, paint);
    assert(pixel(bm, 1, 1) == Color.Red);            // (1.5,1.5): x+y < 4
    assert(pixel(bm, 3, 3) == PMColor(Color.Black)); // (3.5,3.5)

    // the draw matrix moves the geometry
    bm.eraseColor(Color.Black);
    Matrix m;
    m.setTranslate(2, 0);
    Draw(bm, m, bm.bounds).drawPath(tri, paint);
    assert(pixel(bm, 3, 1) == Color.Red);            // (3.5,1.5) in [2,6]x[0,4]
    assert(pixel(bm, 1, 1) == PMColor(Color.Black)); // left of x=2

    // an empty clip or empty path draws nothing at all
    bm.eraseColor(Color.Black);
    Draw(bm, Matrix(), IRect()).drawPath(tri, paint);
    Draw(bm, Matrix(), bm.bounds).drawPath(Path(), paint);
    assert(pixel(bm, 2, 2) == PMColor(Color.Black));

    // drawBitmap with a translative-only matrix blits the source as a sprite
    bm.eraseColor(Color.Black);
    Bitmap src = Bitmap(Bitmap.Config.ARGB_8888, 2, 2);
    src.eraseColor(Color.Blue);
    Matrix mt;
    mt.setTranslate(1, 1);
    auto white = solidPaint(Color.White);
    Draw(bm, mt, bm.bounds).drawBitmap(src, white);
    assert(pixel(bm, 1, 1) == Color.Blue);
    assert(pixel(bm, 2, 2) == Color.Blue);
    assert(pixel(bm, 0, 0) == PMColor(Color.Black));

    // a zero-alpha paint skips the sprite blit entirely
    bm.eraseColor(Color.Black);
    Draw(bm, Matrix(), bm.bounds).drawBitmap(src, solidPaint(color(0, 255, 0, 0)));
    assert(pixel(bm, 0, 0) == PMColor(Color.Black));

    // drawBitmap through a scaled matrix goes the BitmapShader route; the
    // shader samples at pixel corners rounded to nearest, so the far edge
    // samples outside the source and stays transparent (pixel 3,3 not asserted)
    bm.eraseColor(Color.Black);
    Matrix ms;
    ms = ms.preScale(2, 2); // not translativeOnly
    Draw(bm, ms, bm.bounds).drawBitmap(src, white);
    assert(pixel(bm, 0, 0) == Color.Blue, text(pixel(bm, 0, 0)));
    assert(pixel(bm, 2, 2) == Color.Blue, text(pixel(bm, 2, 2)));

    // text drawing, if the system's default face is usable
    TypeFace face;
    try face = TypeFace.defaultFace();
    catch (Exception e) {} // host without usable fonts: nothing to check
    if (face.valid)
    {
        bm.eraseColor(Color.Black);
        auto tp = TextPaint(Color.White, face);
        Draw(bm, Matrix(), bm.bounds).drawText("I", FPoint(1, 3), tp);
        assert(bm.inked);

        bm.eraseColor(Color.Black);
        auto follow = polyline(FPoint(0, 2), FPoint(4, 2));
        Draw(bm, Matrix(), bm.bounds).drawTextOnPath("i", follow, tp);
        assert(bm.inked);
    }
}

unittest
{
    import graphics.core.testing : blackBitmap, pixel, solidPaint;

    // Fill closes every subpath implicitly: a path with two unclosed
    // subpaths must rasterize pixel-identically to the same path with
    // both subpaths explicitly closed. (Before applyFilled the interior
    // subpath fed an open chain to the line integral and mis-filled;
    // this holds under non-zero, which is the only rule in this step.)
    auto bm = blackBitmap(8, 8);
    auto paint = solidPaint(Color.Red);
    auto d = Draw(bm, Matrix(), bm.bounds);

    Path open, explicit;
    open.moveTo(FPoint(0, 0));
    open.lineTo(FPoint(7, 0));
    open.lineTo(FPoint(0, 7));
    open.moveTo(FPoint(2, 2)); // unclosed interior subpath
    open.lineTo(FPoint(5, 2));
    open.lineTo(FPoint(2, 5));

    explicit.moveTo(FPoint(0, 0));
    explicit.lineTo(FPoint(7, 0));
    explicit.lineTo(FPoint(0, 7));
    explicit.close();
    explicit.moveTo(FPoint(2, 2));
    explicit.lineTo(FPoint(5, 2));
    explicit.lineTo(FPoint(2, 5));
    explicit.close();

    bm.eraseColor(Color.Black);
    d.drawPath(open, paint);
    PMColor[] allFirst, allSecond;
    foreach (y; 0 .. bm.height)
        allFirst ~= bm.getLine!PMColor(y).dup;
    bm.eraseColor(Color.Black);
    d.drawPath(explicit, paint);
    foreach (y; 0 .. bm.height)
        allSecond ~= bm.getLine!PMColor(y).dup;
    assert(allFirst == allSecond, "unclosed subpaths must fill like explicitly closed ones");
    assert(pixel(bm, 1, 1) == Color.Red); // big triangle interior painted
    assert(pixel(bm, 3, 3) == PMColor(Color.Red)); // interior subpath painted
}

unittest
{
    // Regression test: the matrix returned by preTranslate used to be
    // discarded, so drawText always landed at the origin no matter what
    // pt said. Draw a glyph well right of the origin and check the ink
    // follows pt.x.
    TypeFace face;
    try face = TypeFace.defaultFace();
    catch (Exception e) {} // host without usable fonts: nothing to verify here
    if (!face.valid)
        return;

    auto bm = Bitmap(Bitmap.Config.ARGB_8888, 16, 16);
    bm.eraseColor(Color.Black);
    Draw(bm, Matrix(), bm.bounds).drawText("H", FPoint(8, 12), TextPaint(Color.White, face));

    bool ink;
    int minX = int.max;
    foreach (y; 0 .. bm.height)
        foreach (x, px; bm.getLine!PMColor(y))
            if (px.r || px.g || px.b) { ink = true; if (x < minX) minX = to!int(x); }
    assert(ink, "drawText drew nothing");
    assert(minX >= 6, text(minX)); // pt.x was 8; the buggy version starts near 0
}
