module skia.core.blitter;

//debug = WHITEBOX;
debug import std.stdio : writefln, writef;

private {
  import std.algorithm : max;
  import std.conv : to, roundTo;
  import std.math : lrint, round, nearbyint;
  import std.array;

  import skia.core.bitmap;
  import skia.core.color;
  import skia.core.device;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.rect;
  import skia.core.region;
  import skia.core.scan : AAScale;
  import skia.core.blitter_detail._;

  import skia.math.clamp;
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
      this.blitFH(y++, x, x + width);
  }
  abstract void blitFH(float y, float xStart, float xEnd);

  static Blitter Choose(Bitmap bitmap, in Matrix matrix, Paint paint)
  {
    switch(bitmap.config) {
    case Bitmap.Config.NoConfig:
      return new NullBlitter();
    case Bitmap.Config.ARGB_8888:
      {
        if (paint.antiAlias)
          return new ARGB32BlitterAA!(AAScale)(bitmap, paint);
        else
          return new ARGB32Blitter(bitmap, paint);
      }
    }
  }

  final protected int round(float f) {
    //! TODO: investigate faster, but correct rounding modes.
    return roundTo!int(f);
  }
  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }
}


////////////////////////////////////////////////////////////////////////////////

class NullBlitter : Blitter {
  override void blitFH(float y, float xStart, float xEnd) {
  }
}


////////////////////////////////////////////////////////////////////////////////

class RasterBlitter : Blitter {
  Bitmap bitmap;
  this(Bitmap bitmap) {
    this.bitmap = bitmap;
  }
  final auto getBitmapRange(float xS, float xE, float y) {
    return this.bitmap.getRange(this.round(xS), this.round(xE), this.round(y));
  }
}


////////////////////////////////////////////////////////////////////////////////

class ARGB32Blitter : RasterBlitter {
  PMColor pmColor;
  this(Bitmap bitmap, Paint paint) {
    super(bitmap);
    pmColor = PMColor(paint.color);
  }
  override void blitFH(float y, float xStart, float xEnd) {
    Color32(this.getBitmapRange(xStart, xEnd, y), pmColor);
  }
}

template binShift(byte val, byte res=0) {
  static if(val == 1)
    alias res binShift;
  else
    alias binShift!(val>>1, res+1) binShift;
}

unittest {
  static assert(binShift!2 == 1);
  static assert(binShift!3 == 1);
  static assert(binShift!4 == 2);
  static assert(binShift!16 == 4);
  static assert(binShift!15 == 3);
}

class ARGB32BlitterAA(byte S) : ARGB32Blitter {
  enum Shift = binShift!S;
  Color color;
  ubyte[] aaLine;
  ubyte vertCnt;

  this(Bitmap bitmap, Paint paint) {
    super(bitmap, paint);
    this.aaLine.length = bitmap.width;
    this.color = paint.color;
    // this.lineBuffer[] = PMWhite;
  }

  override void blitFH(float y, float xStart, float xEnd) {
    auto ixStart = to!int(ceil(xStart + 1e-5f));
    aaLine[ixStart - 1] += to!ubyte(clampToRange((ixStart - xStart) * 255, 0, 255)) >> Shift;
    auto ixEnd = to!int(floor(xEnd - 1e-5f));
    if (ixStart < ixEnd)
      aaLine[ixEnd] += to!ubyte(clampToRange((xEnd - ixEnd) * 255, 0, 255)) >> Shift;
    if (xEnd > xStart) {
      for (auto i = ixStart; i < ixEnd; ++i)
        aaLine[i] += 255 >> Shift;
    }
    ++this.vertCnt;
    if (this.vertCnt == S) {
      this.vertCnt = 0;
      //! finished line => blit to bitmap
      Color32(this.bitmap.getLine(to!int(y)),
              this.aaLine, this.color);
      this.aaLine[] = 0;
    }
  }
}
