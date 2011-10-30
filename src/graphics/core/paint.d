module graphics.core.paint;

private {
  import std.bitmanip;
  import std.string;

  import graphics.core.pmcolor;
  import graphics.core.path;
  import graphics.core.patheffect;
  import graphics.core.shader;
  import graphics.core.stroke;
  import graphics.core.fonthost._;

  version(No_DefaultAntiAlias) {
    enum DefaultAntiAlias = false;
  } else {
    enum DefaultAntiAlias = true;
  }
}

class Paint
{
  Color color;
  float strokeWidth=0.0f;

  PathEffect pathEffect;
  Shader shader;

  mixin(bitfields!(
          bool, "antiAlias", 1,
          bool, "filterBitmap", 1,
          //      bool, "dither", 1,
          Fill, "fillStyle", 2,
          Cap, "capStyle", 2,
          Join, "joinStyle", 2,
        ));

  enum Fill { Fill, Stroke, FillAndStroke, }
  enum Cap { Butt, Square, Round, }
  enum Join { Miter, Round, Bevel, }

  this(Color color=Color.Black) {
    this.color = color;
    this.capStyle = Cap.Butt;
    this.joinStyle = Join.Miter;
    this.antiAlias = DefaultAntiAlias;
  }

  override @property string toString() const {
    return std.string.format("Paint aa: %s fillStyle: %s color: %col",
                             this.antiAlias, this.fillStyle, this.color);
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

class TextPaint : Paint {

  mixin(bitfields!(
          TextAlign, "textAlign", 2,
          bool, "underlineText", 1,
          bool, "strikeThruText", 1,
          bool, "fakeBoldText", 1,
          bool, "embeddedBitmapText", 1,
          bool, "autoHinting", 1,
          uint, "", 1,
        ));

  TypeFace typeFace;
  float textSize = 12.0f;

  // Text direction not implemented. Encoding should always be utf string.
  version(none) {
    mixin(bitfields!(
            TextEncoding, "textEncoding", 2,
            TextBufferDirection, "textBufferDirection", 1,
            uint, "", 5));

    enum TextEncoding { UTF8, UTF16, GlyphId, }
    enum TextBufferDirection : bool { Forward, Backward, }
  }

  enum TextAlign { Left, Center, Right, }

  this(Color color=Color.Black, TypeFace typeFace=TypeFace.defaultFace()) {
    super(color);
    this.typeFace = typeFace;
  }

  struct FontMetrics {
    @property string toString() const {
      return std.string.format(
          "FontMetrics top:%f ascent:%f descent:%f bottom:%f leading:%f \n" ~
          "\txmin:%f xmax:%f underlinePos:%f underlineThickness:%f",
          top, ascent, descent, bottom, leading,
          xmin, xmax, underlinePos, underlineThickness);
    }
    float top;
    float ascent;
    float descent;
    float bottom;
    float leading;
    float xmin;
    float xmax;
    float underlinePos;
    float underlineThickness;
  };

  FontMetrics fontMetrics() const {
    auto cache = getGlyphCache(typeFace, textSize);
    return cache.fontMetrics();
  }
}

unittest {
  scope auto paint = new TextPaint(Color.Red);

  assert(paint.antiAlias == DefaultAntiAlias);
  assert(!paint.filterBitmap);
  //  assert(!paint.dither);
  assert(!paint.underlineText);
  assert(!paint.strikeThruText);
  assert(!paint.fakeBoldText);
  assert(!paint.embeddedBitmapText);
  assert(!paint.autoHinting);

  assert(paint.fillStyle == Paint.Fill.Fill);
  assert(paint.capStyle == Paint.Cap.Butt);
  assert(paint.joinStyle == Paint.Join.Miter);
  assert(paint.textAlign == TextPaint.TextAlign.Left);

  paint.antiAlias = true;
  //  paint.dither = true;
  paint.fillStyle = Paint.Fill.FillAndStroke;
  paint.joinStyle = Paint.Join.Bevel;

  assert(paint.antiAlias);
  assert(!paint.filterBitmap);
  //  assert(paint.dither);
  assert(!paint.underlineText);

  assert(paint.fillStyle == Paint.Fill.FillAndStroke);
  assert(paint.capStyle == Paint.Cap.Butt);
  assert(paint.joinStyle == Paint.Join.Bevel);
  assert(paint.textAlign == TextPaint.TextAlign.Left);
}
