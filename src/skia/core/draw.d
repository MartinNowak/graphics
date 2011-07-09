module skia.core.draw;

private {
  import std.array;

  import guip.bitmap;
  import skia.core.bounder;
  import skia.core.blitter;
  import skia.core.pmcolor;
  import skia.core.device;
  import skia.core.glyph;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.path;
  import skia.core.shader;
  import skia.core.path_detail.path_measure;
  import skia.core.fonthost._;
  import guip.point;
  import guip.rect;
  import guip.size;
  import Scan = skia.core.scan;

  import skia.math.fixed_ary;
}

// debug=PRINTF;
debug(PRINTF) private import std.stdio : printf;

struct Draw {
public:
  Bitmap bitmap;
  Matrix matrix;
  IRect clip;
  Device device;
  Bounder bounder;
  // DrawProcs drawProcs;

  this(Bitmap bitmap) {
    this.bitmap = bitmap;
  }

  this(Bitmap bitmap, in Matrix matrix, in IRect clip) {
    this(bitmap);
    this.matrix = matrix;
    this.clip = clip;
  }

  void drawPaint(Paint paint) {
    if (this.clip.empty
        || this.bounder && !this.bounder.doIRect(this.bitmap.bounds, paint))
      return;

    /**
     *  If we don't have a shader (i.e. we're just a solid color) we
     *  may be faster to operate directly on the device bitmap, rather
     *  than invoking a blitter. Esp. true for xfermodes, which
     *  require a colorshader to be present, which is just redundant
     *  work. Since we're drawing everywhere in the clip, we don't
     *  have to worry about antialiasing.
     */
    /*
    uint32_t procData = 0;  // to avoid the warning
    BitmapXferProc proc = ChooseBitmapXferProc(*fBitmap, paint, &procData);
    if (proc) {
        if (D_Dst_BitmapXferProc == proc)// nothing to do
            return;

        SkRegion::Iterator iter(*fClip);
        while (!iter.done()) {
            CallBitmapXferProc(*fBitmap, iter.rect(), proc, procData);
            iter.next();
        }
    } else {
    */
    Scan.fillIRect(this.bitmap.bounds, this.clip, this.getBlitter(paint));
  }

  private Blitter getBlitter(Paint paint) {
    return Blitter.Choose(this.bitmap, this.matrix, paint);
  }

  private Blitter getBlitter(Paint paint, in Bitmap source, IPoint ioff) {
    return Blitter.ChooseSprite(this.bitmap, paint, source, ioff);
  }

  void drawColor(in Color c) {
    this.bitmap.eraseColor(PMColor(c));
  }

  void drawPath(in Path path, Paint paint) {
    if (this.clip.empty)
      return;

    if (path.empty) {
      assert(!path.inverseFillType);
      return;
    }

    bool doFill;
    Path toBlit;
    if (paint.pathEffect || paint.fillStyle != Paint.Fill.Fill) {
      toBlit = paint.getFillPath(path, doFill);
    } else {
      doFill = true;
      toBlit = path;
    }

    toBlit.transform(this.matrix);
    if (this.bounder
        && !this.bounder.doPath(toBlit, paint, doFill))
        return;

    scope Blitter blitter = this.getBlitter(paint);

    if (doFill) {
      return paint.antiAlias ?
        Scan.antiFillPath(toBlit, this.clip, blitter)
        : Scan.fillPath(toBlit, this.clip, blitter);
    } else {
      return paint.antiAlias ?
        Scan.antiHairPath(toBlit, this.clip, blitter)
        : Scan.hairPath(toBlit, this.clip, blitter);
    }
  }

  @property bool justTranslation() const {
    // TODO: approx translation
    return this.matrix.rectStaysRect && !(this.matrix.affine || this.matrix.scaling);
  }

  void drawBitmap(in Bitmap source, Paint paint) {
    if (this.clip.empty || source.bounds.empty ||
        source.config == Bitmap.Config.NoConfig ||
        (paint.color.a == 0 && paint.xferMode is null)) {
        return;
    }

    auto ioff = IPoint(to!int(this.matrix[0][2]), to!int(this.matrix[1][2]));
    auto ir = IRect(ioff, ioff + source.size);

    if (this.justTranslation && source.config != Bitmap.Config.A8) {
      if (this.bounder !is null && !this.bounder.doIRect(ir, paint))
        return;

      if (ir.intersect(this.clip)) {
        scope auto blitter = this.getBlitter(paint, source, ioff);
        blitter.blitRect(ir);
      }
    } else {

      if (source.config == Bitmap.Config.A8) {
        // TODO: need to apply transformation
        scope auto blitter = this.getBlitter(paint);
        blitter.blitMask(ioff.x, ioff.y, source);
      } else {
        Shader oldshader = paint.shader;
        scope(exit) paint.shader = oldshader;
        paint.shader = new BitmapShader(source);

        ir = IRect(source.size);
        drawRect(fRect(ir), paint);
      }
    }
  }

  void drawRect(in FRect rect, Paint paint) {
    Path path;
    path.addRect(rect);
    this.drawPath(path, paint);
    /+
    FRect transRect;
    this.matrix.mapRect(fRect(rect), transRect);

    if (this.bounder && !this.bounder.doIRect(transRect, paint))
      return;

    auto doFill = paint.fillStyle == Paint.Fill.Fill
      || paint.fillStyle == Paint.Fill.FillAndStroke;

    // TODO: quickReject on clip before building blitter
    Blitter blitter = this.getBlitter(paint);

    if (doFill) {
      return paint.antiAlias ?
        Scan.antiFillRect(transRect, this.clip, blitter)
        : Scan.fillRect(transRect, this.clip, blitter);
    } else {
      return paint.antiAlias ?
        Scan.antiHairRect(transRect, this.clip, blitter)
        : Scan.hairRect(transRect, this.clip, blitter);
    }
    +/
  }

  void drawText(string text, FPoint pt, TextPaint paint) {
    if (text.empty || this.clip.empty ||
        (paint.color.a == 0 && paint.xferMode is null))
      return;

    // TODO: underline handling

    auto cache = getGlyphCache(paint.typeFace, paint.textSize);

    FPoint start = this.matrix.mapPoint(pt);
    if (paint.textAlign != TextPaint.TextAlign.Left) {
      auto length = measureText(text, cache);
      if (paint.textAlign == TextPaint.TextAlign.Center)
        length *= 0.5;
      start.x = start.x - length;
    }
    scope Blitter blitter = this.getBlitter(paint);

    foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Bitmap)) {
      auto pos = start + gl.bmpPos;
      auto ipos = pos.round();
      blitter.blitMask(ipos.x, ipos.y, gl.bmp);
      start += gl.advance;
    }
  }

  void drawTextAsPaths(string text, FPoint pt, TextPaint paint) {
    if (text.empty || this.clip.empty ||
        (paint.color.a == 0 && paint.xferMode is null))
      return;

    auto backUp = this.matrix;
    scope(exit) this.matrix = backUp;

    auto cache = getGlyphCache(paint.typeFace, paint.textSize);

    float hOffset = 0;
    if (paint.textAlign != TextPaint.TextAlign.Left) {
      auto length = measureText(text, cache);
      if (paint.textAlign == TextPaint.TextAlign.Center)
        length *= 0.5;
      hOffset = length;
    }

    this.matrix.preTranslate(pt.x, pt.y);
    Matrix scaledMatrix = this.matrix;
    // TODO: scale matrix according to freetype outline relation
    // auto scale = PathGlyphStream.getScale();
    // scaledMatrix.preScale(scale, scale);

    FPoint pos = FPoint(0, 0);
    foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path)) {
      Matrix m;
      m.setTranslate(pos.x - hOffset, 0);
      this.matrix = scaledMatrix * m;
      this.drawPath(gl.path, paint);
      pos += gl.advance;
    }
  }

  void drawTextOnPath(string text, in Path follow, TextPaint paint) {
    auto meas = PathMeasure(follow);

    float hOffset = 0;
    if (paint.textAlign != TextPaint.TextAlign.Left) {
      auto length = meas.length;
      if (paint.textAlign == TextPaint.TextAlign.Center)
        length *= 0.5;
      hOffset = length;
    }

    //! TODO: scaledMatrix

    auto cache = getGlyphCache(paint.typeFace, paint.textSize);
    FPoint pos = FPoint(0, 0);
    foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics | Glyph.LoadFlag.Path)) {
      Matrix m;
      m.setTranslate(pos.x + hOffset, 0);
      this.drawPath(morphPath(gl.path, meas, m), paint);
      pos += gl.advance;
    }
  }

  private Path morphPath(in Path path, in PathMeasure meas, in Matrix matrix) {
    Path dst;

    path.forEach((Path.Verb verb, in FPoint[] pts) {
        final switch(verb) {
        case Path.Verb.Move:
          FPoint[1] mpts = morphPoints(fixedAry!1(pts), meas, matrix);
          dst.moveTo(mpts[0]);
          break;

        case Path.Verb.Line:
          //! use quad to allow curvature
          FPoint[2] mpts = fixedAry!2(pts);
          mpts[0] = (mpts[0] + mpts[1]) * 0.5f;
          mpts = morphPoints(mpts, meas, matrix);
          dst.quadTo(mpts[0], mpts[1]);
          break;

        case Path.Verb.Quad:
          FPoint[2] mpts = morphPoints(fixedAry!2(pts[1..$]), meas, matrix);
          dst.quadTo(mpts[0], mpts[1]);
          break;

        case Path.Verb.Cubic:
          FPoint[3] mpts = morphPoints(fixedAry!3(pts[1..$]), meas, matrix);
          dst.cubicTo(mpts[0], mpts[1], mpts[2]);
          break;

        case Path.Verb.Close:
          dst.close();
          break;
        }
      });
    return dst;
  }

  private FPoint[K] morphPoints(size_t K)(FPoint[K] pts, in PathMeasure meas, in Matrix matrix) {
    FPoint[K] dst;
    FPoint[K] trans = pts;

    matrix.mapPoints(trans);

    for (auto i = 0; i < K; ++i) {
      FVector normal;
      auto pos = meas.getPosAndNormalAtDistance(trans[i].x, normal);
      dst[i] = pos - normal * trans[i].y;
    }
    return dst;
  }
  /++

  void    drawPoints(SkCanvas::PointMode, size_t count, const SkPoint[],
		     const SkPaint&) const;
  /*  To save on mallocs, we allow a flag that tells us that srcPath is
      mutable, so that we don't have to make copies of it as we transform it.
  */
  void    drawBitmap(const SkBitmap&, const SkMatrix&, const SkPaint&) const;
  void    drawSprite(const SkBitmap&, int x, int y, const SkPaint&) const;
  void    drawPosText(const char text[], size_t byteLength,
		      const SkScalar pos[], SkScalar constY,
		      int scalarsPerPosition, const SkPaint& paint) const;
  void    drawTextOnPath(const char text[], size_t byteLength,
			 const SkPath&, const SkMatrix*, const SkPaint&) const;
  void    drawVertices(SkCanvas::VertexMode mode, int count,
		       const SkPoint vertices[], const SkPoint textures[],
		       const SkColor colors[], SkXfermode* xmode,
		       const uint16_t indices[], int ptCount,
		       const SkPaint& paint) const;


  /** Helper function that creates a mask from a path and an optional maskfilter.
      Note however, that the resulting mask will not have been actually filtered,
      that must be done afterwards (by calling filterMask). The maskfilter is provided
      solely to assist in computing the mask's bounds (if the mode requests that).
  */
  static bool DrawToMask(const SkPath& devPath, const SkIRect* clipBounds,
			 SkMaskFilter* filter, const SkMatrix* filterMatrix,
			 SkMask* mask, SkMask::CreateMode mode);

private:
  void    drawText_asPaths(const char text[], size_t byteLength,
			   SkScalar x, SkScalar y, const SkPaint&) const;
  void    drawDevMask(const SkMask& mask, const SkPaint&) const;
  void    drawBitmapAsMask(const SkBitmap&, const SkPaint&) const;

public:
  const Bitmap mBitmap;        // required
  const Matrix mMatrix;        // required
  const Region mClip;          // required
  Device       mDevice;        // optional
  Bounder      mBounder;       // optional
  DrawProcs    mProcs;         // optional

#ifdef SK_DEBUG
    void    validate(int width, int height) const;
#endif
+/
};
