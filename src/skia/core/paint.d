module skia.core.paint;

private {
  import std.bitmanip;
  import std.format : formattedWrite;
  import std.array : appender;

  import skia.core.color;
  import skia.core.drawlooper;
  import skia.core.path;
  import skia.core.patheffect;
  import skia.core.stroke;

  version(No_DefaultAntiAlias) {
    enum DefaultAntiAlias = false;
  } else {
    enum DefaultAntiAlias = true;
  }
}

class Paint
{
  Color color;
  DrawLooper drawLooper;

  //! TODO: review alignment
  PathEffect pathEffect;
  float strokeWidth;

  @property string toString() const {
    auto writer = appender!string();
    auto fmt = "Paint aa: %s fillStyle: %s enc: %s color: %col looper: %s";
    formattedWrite(writer, fmt, this.antiAlias, this.fillStyle,
                   this.textEncoding, this.color, this.drawLooper);
    return writer.data;
  }
  mixin(bitfields!(
      bool, "antiAlias", 1,
      bool, "filterBitmap", 1,
      bool, "dither", 1,
      bool, "underlineText", 1,
      bool, "strikeThruText", 1,
      bool, "fakeBoldText", 1,
      bool, "embeddedBitmapText", 1,
      bool, "autoHinting", 1));

  enum Fill { Fill, Stroke, FillAndStroke, }
  enum Cap { Butt, Square, Round, }
  enum Join { Miter, Round, Bevel, }
  enum Align { Left, Center, Right, }
  mixin(bitfields!(
      Fill, "fillStyle", 2,
      Cap, "capStyle", 2,
      Join, "joinStyle", 2,
      Align, "alignment", 2));

  enum TextEncoding { UTF8, UTF16, GlyphId, }
  enum TextBufferDirection : bool { Forward, Backward, }
  mixin(bitfields!(
      TextEncoding, "textEncoding", 2,
      TextBufferDirection, "textBufferDirection", 1,
      uint, "", 5));


  this(Color color) {
    this.color = color;
    this.capStyle = Cap.Butt;
    this.joinStyle = Join.Miter;
    this.antiAlias = DefaultAntiAlias;
  }

  Path getFillPath(in Path src, out bool doFill) const {
    float width = this.strokeWidth;

    final switch (this.fillStyle) {
    case Fill.Fill:
      width = -1; // mark it as no-stroke
      break;
    case Fill.Stroke:
      break;
    case Fill.FillAndStroke:
      if (width == 0)
        width = -1; // mark it as no-stroke
      break;
    }

    Path resultPath;
    resultPath = src;
    if (this.pathEffect) {
      // lie to the pathEffect if our style is strokeandfill, so that it treats us as just fill
      if (this.fillStyle == Fill.FillAndStroke)
        width = -1; // mark it as no-stroke

      auto effectPath = this.pathEffect.filterPath(resultPath, width);
      if (!effectPath.empty)
        resultPath = effectPath;

      // restore the width if we earlier had to lie, and if we're still set to no-stroke
      // note: if we're now stroke (width >= 0), then the pathEffect asked for that change
      // and we want to respect that (i.e. don't overwrite their setting for width)
      if (this.fillStyle == Fill.FillAndStroke && width < 0) {
        width = this.strokeWidth;
        if (width == 0)
          width = -1;
      }
    }

    if (width > 0 && !resultPath.empty) {
      auto stroker = Stroke(this, width);
      resultPath = stroker.strokePath(resultPath);
    }
    doFill = width != 0;
    return resultPath;  // return true if we're filled, or false if we're hairline (width == 0)
  }
}

unittest {
  scope auto paint = new Paint(Red);
  assert(paint.antiAlias == DefaultAntiAlias);
  assert(!paint.filterBitmap);
  assert(!paint.dither);
  assert(!paint.underlineText);
  assert(!paint.strikeThruText);
  assert(!paint.fakeBoldText);
  assert(!paint.embeddedBitmapText);
  assert(!paint.autoHinting);

  assert(paint.fillStyle == Paint.Fill.Fill);
  assert(paint.capStyle == Paint.Cap.Butt);
  assert(paint.joinStyle == Paint.Join.Miter);
  assert(paint.alignment == Paint.Align.Left);

  assert(paint.textEncoding == Paint.TextEncoding.UTF8);
  assert(paint.textBufferDirection == Paint.TextBufferDirection.Forward);

  paint.antiAlias = true;
  paint.dither = true;
  paint.fillStyle = Paint.Fill.FillAndStroke;
  paint.joinStyle = Paint.Join.Bevel;

  assert(paint.antiAlias);
  assert(!paint.filterBitmap);
  assert(paint.dither);
  assert(!paint.underlineText);

  assert(paint.fillStyle == Paint.Fill.FillAndStroke);
  assert(paint.capStyle == Paint.Cap.Butt);
  assert(paint.joinStyle == Paint.Join.Bevel);
  assert(paint.alignment == Paint.Align.Left);
}
