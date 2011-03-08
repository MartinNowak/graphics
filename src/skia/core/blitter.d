module skia.core.blitter;

//debug = WHITEBOX;
debug import std.stdio;

private {
  import std.algorithm;
  import std.conv : to, roundTo;
  import std.math : lrint, round, nearbyint;
  import std.numeric : FPTemporary;
  import std.array;
  import std.range;

  import skia.core.bitmap;
  import skia.core.color;
  import skia.core.device;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.scan : AAScale;
  import skia.core.blitter_detail._;

  import skia.util.span;
  import skia.util.format;
  import skia.math._;
}

class Blitter
{
  void blitRect(IRect rect) {
    this.blitRect(rect.x, rect.y, rect.width, rect.height);
  }
  final void blitRect(int x, int y, int width, int height) {
    while (--height >= 0)
      this.blitFH(y++, x, x + width);
  }
  abstract void blitFH(float y, float xStart, float xEnd);
  //! TODO: should be constant 'in Bitmap mask'
  abstract void blitMask(float x, float y, in Bitmap mask);

  static Blitter Choose(Bitmap device, in Matrix matrix, Paint paint) {
    switch(device.config) {
    case Bitmap.Config.NoConfig:
      return new NullBlitter();
    case Bitmap.Config.ARGB_8888:
      {
        if (paint.antiAlias)
          return new ARGB32BlitterAA!(AAScale)(device, paint);
        else
          return new ARGB32Blitter(device, paint);
      }
    }
  }

  static Blitter ChooseSprite(Bitmap device, Paint paint, in Bitmap source, IPoint ioff) {
    SpriteBlitter blitter;

    switch (device.config) {
    case Bitmap.Config.RGB_565:
      blitter = SpriteBlitter.CreateD16(device, source, paint, ioff);
      break;
    case Bitmap.Config.ARGB_8888:
      blitter = SpriteBlitter.CreateD32(device, source, paint, ioff);
      break;
    default:
      blitter = null;
      break;
    }

    return blitter;
  }

  final protected int round(float f) {
    return checkedTo!int(lrint(f));
  }
  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }
}


////////////////////////////////////////////////////////////////////////////////

class NullBlitter : Blitter {
  override void blitFH(float y, float xStart, float xEnd) {
  }
  override void blitMask(float x, float y, in Bitmap mask) {
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
  Color color;
  PMColor pmColor;
  this(Bitmap bitmap, Paint paint) {
    super(bitmap);
    this.color = paint.color;
    this.pmColor = PMColor(this.color);
  }
  override void blitFH(float y, float xStart, float xEnd) {
    Color32(this.getBitmapRange(xStart, xEnd, y), pmColor);
  }
  override void blitMask(float x, float y, in Bitmap mask) {
    assert(mask.config == Bitmap.Config.A8);
    auto ix = checkedTo!int(truncate(x));
    auto iy = checkedTo!int(truncate(y));
    for (auto h = 0; h < mask.height; ++h) {
      BlitAASpan(this.bitmap.getRange(ix, ix + mask.width, iy + h),
                 (cast(Bitmap)mask).getRange!ubyte(0, mask.width, h), this.color);
    }
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

struct AARun {
  ushort length;
  ushort aaSum;
}

class ARGB32BlitterAA(byte S) : ARGB32Blitter {
  enum Shift = binShift!S;
  enum ushort FullCovVal = ushort.max / S;
  alias SpanAccumulator!(ushort, ushort, Policy.PreAllocate) AAAcc;
  alias Span!(ushort, ushort) AASpan;
  static AAAcc aaAcc;
  //  AAAcc aaAcc;
  int curIY = int.min;

  this(Bitmap bitmap, Paint paint) {
    super(bitmap, paint);
    this.color = paint.color;
    this.resetRuns();
  }

  ~this() {
    this.flush();
  }

  override void blitFH(float y, float xStart, float xEnd) {
    assert(xEnd > xStart);
    auto iy = to!uint(truncate(y));
    if (iy != this.curIY) {
      this.flush();
      this.curIY = iy;
    }

    auto ixStart = checkedTo!ushort(truncate(xStart));
    auto ixEnd = checkedTo!ushort(truncate(xEnd));

    if (ixStart == ixEnd) {
      auto aaVal = checkedTo!ushort((xEnd - xStart) * FullCovVal);
      this.aaAcc += AASpan(ixStart, checkedTo!ushort(ixStart + 1), aaVal);
    } else {
      if (xStart > ixStart) {
        auto aaVal = checkedTo!ushort((1 + ixStart - xStart) * FullCovVal);
        this.aaAcc += AASpan(ixStart, checkedTo!ushort(ixStart + 1), aaVal);
        ++ixStart;
      }
      if (xEnd > ixEnd) {
        auto aaVal = checkedTo!ushort((xEnd - ixEnd) * FullCovVal);
        this.aaAcc += AASpan(ixEnd, checkedTo!ushort(ixEnd + 1), aaVal);
      }
      if (ixEnd > ixStart) {
        this.aaAcc += AASpan(ixStart, ixEnd, FullCovVal);
      }
    }
  }

  void flush() {
    foreach(AASpan sp; aaAcc[]) {
      auto alpha = checkedTo!ubyte(sp.value >> 8);
      if (alpha) {
        auto color = this.color;
        color.a = alphaMul(color.a, alphaScale(alpha));
        Color32(this.bitmap.getRange(sp.start, sp.end, this.curIY), PMColor(color));
      }
    }
    this.resetRuns();
  }

  void resetRuns() {
    this.aaAcc.reset(AASpan(0, to!ushort(this.bitmap.width), 0));
  }
}

unittest {
  auto bitmap = Bitmap(Bitmap.Config.ARGB_8888, 10, 1);
  bitmap.eraseColor(PMColor(Black));
  auto paint = new Paint(White);
  scope auto aaBlitter = new ARGB32BlitterAA!4(bitmap, paint);

  aaBlitter.blitFH(0.f, 0.f, 10.f);
  aaBlitter.flush();
  // TODO: should be 0xFF3F3F3F
  assert(equal(bitmap.getLine(0), repeat(Color("0xFE3F3F3F"), 10)));

  bitmap.eraseColor(PMColor(Black));
  aaBlitter.blitFH(0.f, 1.f, 8.f);
  aaBlitter.blitFH(0.25f, 1.25f, 7.75f);
  aaBlitter.blitFH(0.5f, 1.5f, 7.5f);
  aaBlitter.blitFH(0.75f, 1.75f, 7.25f);

  aaBlitter.flush();
  // TODO: should be 0xFF9F9F9F
  auto exp = [Black, Color("0xFE9F9F9F")]
    ~ array(repeat(White, 5)) ~ [Color("0xFE9F9F9F"), Black, Black];
  assert(equal(bitmap.getLine(0), exp));
}

