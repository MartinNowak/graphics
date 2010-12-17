module skia.core.paint;

private {
  import std.bitmanip;
  import std.format : formattedWrite;
  import std.array : appender;

  import skia.core.color;
  import skia.core.drawlooper;

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
  enum Join { Miter, Join, Bevel, }
  enum Align { Left, Center, Right, }
  mixin(bitfields!(
      uint, "fillStyle", 2,
      uint, "capStyle", 2,
      uint, "joinStyle", 2,
      uint, "alignment", 2));

  enum TextEncoding { UTF8, UTF16, GlyphId, }
  enum TextBufferDirection : bool { Forward, Backward, }
  mixin(bitfields!(
      uint, "textEncoding", 2,
      bool, "textBufferDirection", 1,
      uint, "", 5));


  this(Color color) {
    this.color = color;
    this.capStyle = Cap.Butt;
    this.joinStyle = Join.Miter;
    this.antiAlias = DefaultAntiAlias;
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
