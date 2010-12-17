module skia.core.blitter;

//debug = WHITEBOX;
debug import std.stdio : writefln, writef;

private {
  import std.conv : to;
  import std.math : lrint, round, nearbyint;
  import std.array;

  import skia.core.bitmap;
  import skia.core.color;
  import skia.core.device;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.rect;
  import skia.core.region;
}

class Blitter
{
  void blitRegion(in Region clip) {
    clip.forEach(&this.blitRect);
  }

  void blitRect(in IRect rect) {
    this.blitRect(rect.x, rect.y, rect.width, rect.height);
  }
  void blitRect(int x, int y, int width, int height) {
    while (--height >= 0)
      this.blitH(x, y++, width);
  }
  abstract void blitH(int x, int y, uint width);
  void blitFH(float x, float y, float width) {
    // assert(width > 0); // already asserted by conv
    // TODO: review rounding functions, find out why lrint doesn't work.
    this.blitH(to!int(round(x)), to!int(round(y)),
               to!uint(round(width)));
    // this.blitH(to!int(lrint(x)), to!int(lrint(y)), to!uint(lrint(width)));
  }

  void scaleAlpha(float fScale) {}
  static Blitter Choose(Bitmap bitmap, in Matrix matrix, Paint paint)
  {
    switch(bitmap.config) {
    case Bitmap.Config.NoConfig:
      return new NullBlitter();
    case Bitmap.Config.ARGB_8888:
      return new ARGB32Blitter(bitmap, paint);
    }
  }

  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }
}


////////////////////////////////////////////////////////////////////////////////

class NullBlitter : Blitter {
  override void blitH(int x, int y, uint width) {
  }
}


////////////////////////////////////////////////////////////////////////////////

class RasterBlitter : Blitter {
  Bitmap bitmap;
  this(Bitmap bitmap) {
    this.bitmap = bitmap;
  }
}


////////////////////////////////////////////////////////////////////////////////

class ARGB32Blitter : RasterBlitter {
  PMColor pmColor;
  this(Bitmap bitmap, Paint paint) {
    super(bitmap);
    pmColor = PMColor(paint.color);
  }
  override void blitH(int x, int y, uint width) {
    BlitRow.Color32(this.bitmap.getRange(x, y), width, pmColor);
  }
  // used when drawing anti-aliased and the y step is not 1
  override void scaleAlpha(float fScale) {
    auto scale = Color.getAlphaFactor(to!int((255 * fScale)));
    this.pmColor = this.pmColor.mulAlpha(scale);
  }
}


struct BlitRow {
  static void Color32(Range)(Range range, int width, PMColor pmColor) {
    if (pmColor.a == 255) {
      range[0 .. width] = pmColor;
    } else {
      auto scale = Color.getInvAlphaFactor(pmColor.a);
      while (width--) {
        range.front = range.front.mulAlpha(scale) + pmColor;
        range.popFront;
      }
    }
  }
}