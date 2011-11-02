module graphics.core.draw;

private {
  import std.array;
  import guip.bitmap;
  import graphics.core.blitter;
  import graphics.core.pmcolor;
  import graphics.core.glyph;
  import graphics.core.matrix;
  import graphics.core.paint;
  import graphics.core.path;
  import graphics.core.shader;
  import graphics.core.path_detail.path_measure;
  import graphics.core.fonthost._;
  import guip.point;
  import guip.rect;
  import guip.size;
  import Scan = graphics.core.scan;
}

// debug=PRINTF;
debug(PRINTF) private import std.stdio : printf;

struct Draw {
public:
  Bitmap bitmap;
  Matrix matrix;
  IRect clip;
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
    if (!this.clip.empty)
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
        paint.color.a == 0) {
        return;
    }

    auto ioff = IPoint(to!int(this.matrix[0][2]), to!int(this.matrix[1][2]));
    auto ir = IRect(ioff, ioff + source.size);

    if (this.justTranslation && source.config != Bitmap.Config.A8) {
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
        paint.color.a == 0)
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
        };
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
