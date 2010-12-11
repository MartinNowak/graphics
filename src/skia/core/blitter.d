module skia.core.blitter;

//debug = WHITEBOX;
debug import std.stdio : writefln, writef;

private {
  import std.conv : to;
  import std.math : lrint;
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
  void blitFH(float x, int y, float width) {
    // assert(width > 0); // already asserted by conv
    this.blitH(to!int(lrint(x)), y, to!uint(lrint(width)));
  }

  static Blitter Choose(Bitmap bitmap, in Matrix matrix, Paint paint)
  {
    switch(bitmap.config) {
    case Config.NoConfig:
      return new NullBlitter();
    case Config.ARGB_8888:
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