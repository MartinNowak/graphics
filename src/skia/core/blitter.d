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
      this.blitH(y++, x, x + width);
  }
  abstract void blitH(int y, int xStart, int xEnd);
  void blitFH(float y, float xStart, float xEnd) {
    // assert(width > 0); // already asserted by conv
    // TODO: review rounding functions, find out why lrint doesn't work.
    this.blitH(roundTo!int(y), roundTo!int(xStart), roundTo!int(xEnd));
    // this.blitH(to!int(lrint(x)), to!int(lrint(y)), to!uint(lrint(width)));
  }

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

  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }
}


////////////////////////////////////////////////////////////////////////////////

class NullBlitter : Blitter {
  override void blitH(int y, int xStart, int xEnd) {
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
  override void blitH(int y, int xStart, int xEnd) {
    BlitRow.Color32(this.bitmap.getRange(y, xStart, xEnd), pmColor);
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
    auto xc = max(0.0001f, xStart);
    auto ixStart = to!int(ceil(xc));
    aaLine[ixStart - 1] += to!ubyte((ixStart - xc) * 255) >> Shift;
    auto xec = min(aaLine.length - 0.0001f, xEnd);
    auto ixEnd = to!int(floor(xec));
    if (ixStart < ixEnd)
      aaLine[ixEnd] += to!ubyte((xec - ixEnd) * 255) >> Shift;
    if (xEnd > xStart) {
      for (auto i = ixStart; i < ixEnd; ++i)
        aaLine[i] += 255 >> Shift;
    }
    ++this.vertCnt;
    if (this.vertCnt == S) {
      this.vertCnt = 0;
      //! finished line => blit to bitmap
      BlitRow.Color32(this.bitmap.getLine(to!int(y)),
                      this.aaLine, this.color);
      this.aaLine[] = 0;
    }
  }
}


struct BlitRow {
  static void Color32(Range)(Range range, PMColor pmColor) {
    if (pmColor.a == 255) {
      while (!range.empty) {
        range.front = pmColor;
        range.popFront;
      }
    } else {
      auto scale = Color.getInvAlphaFactor(pmColor.a);
      while (!range.empty) {
        range.front = range.front.mulAlpha(scale) + pmColor;
        range.popFront;
      }
    }
  }

  static void Color32(Range, Range2)(Range output, Range2 alpha, Color color) {
    auto colorA = color.a;
    while (!alpha.empty) {
      if (alpha.front > 0) {
        auto combA = (colorA + 1) * (alpha.front + 1) >> 8;
        auto srcA = Color.getAlphaFactor(combA);
        auto dstA = Color.getInvAlphaFactor(combA);
        output.front = output.front.mulAlpha(dstA) + color.mulAlpha(srcA);
      }
      output.popFront; alpha.popFront;
    }
  }

}