module graphics.core.paint;

import std.bitmanip, std.string;
import graphics.core.pmcolor, graphics.core.path, graphics.core.shader, graphics.core.stroke, graphics.core.fonthost;

struct Paint
{
    Color color=Color.Black;
    Shader shader;

    @property string toString()
    {
        return std.string.format("Paint color: %s shader: %s", color, shader);
    }
}

struct TextPaint
{
    Paint _paint;
    alias _paint this;

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
    version(none)
    {
        mixin(bitfields!(
                  TextEncoding, "textEncoding", 2,
                  TextBufferDirection, "textBufferDirection", 1,
                  uint, "", 5));

        enum TextEncoding { UTF8, UTF16, GlyphId, }
        enum TextBufferDirection : bool { Forward, Backward, }
    }

    enum TextAlign { Left, Center, Right, }

    this(Color color/*=Color.Black*/, TypeFace typeFace=TypeFace.defaultFace())
    {
        this.color = color;
        this.typeFace = typeFace;
    }

    struct FontMetrics
    {
        @property string toString() const
        {
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

    FontMetrics fontMetrics() const
    {
        auto cache = getGlyphCache(typeFace, textSize);
        return cache.fontMetrics();
    }
}

unittest
{
    Paint p;
    p.shader = null;
    assert(p.color == Color.Black);
    assert(p.toString.length > 0);

    p.color = Color.Red;
    auto s = p.toString;
    import std.algorithm : canFind;
    assert(s.canFind("Paint color"));

    // TextPaint wraps Paint and carries its own flags
    TextPaint tp;
    tp.shader = null;
    tp.color = Color.Green;
    tp.textSize = 42.0f;
    tp.textAlign = TextPaint.TextAlign.Center;
    tp.underlineText = true;
    tp.strikeThruText = true;
    tp.fakeBoldText = true;
    tp.embeddedBitmapText = false;
    tp.autoHinting = true;

    Paint up = tp; // implicit conversion through alias this
    assert(up.color == Color.Green);
    assert(tp.textSize == 42.0f);
    assert(tp.textAlign == TextPaint.TextAlign.Center);
    assert(tp.underlineText && tp.strikeThruText && tp.fakeBoldText);
    assert(tp.autoHinting && !tp.embeddedBitmapText);

    // font metrics against the system's default face, if any is available
    auto face = TypeFace.defaultFace();
    if (face.valid)
    {
        import std.math : isFinite;
        auto tp2 = TextPaint(Color.Black, face);
        auto fm = tp2.fontMetrics;
        assert(isFinite(fm.ascent) && isFinite(fm.descent), fm.toString);
        assert(isFinite(fm.leading) && isFinite(fm.xmin) && isFinite(fm.xmax), fm.toString);
        assert(fm.toString.length > 0);
    }
}
