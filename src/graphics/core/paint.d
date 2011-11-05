module graphics.core.paint;

private {
  import std.bitmanip;
  import std.string;

  import graphics.core.pmcolor;
  import graphics.core.path;
  import graphics.core.shader;
  import graphics.core.stroke;
  import graphics.core.fonthost._;
}

class Paint
{
    Color color;
    Shader shader;

    this(Color color=Color.Black)
    {
        this.color = color;
    }

    override @property string toString() const
    {
        return std.string.format("Paint color: %s shader: %s", color, shader);
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
