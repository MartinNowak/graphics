module skia.core.blitter;

//debug = WHITEBOX;
debug import std.stdio : writefln, writef;

private {
  import std.algorithm : max;
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
  import skia.core.rect;
  import skia.core.region;
  import skia.core.scan : AAScale;
  import skia.core.blitter_detail._;

  import skia.math._;
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
  //! TODO: should be constant 'in Bitmap mask'
  abstract void blitMask(float x, float y, in Bitmap mask);

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
  enum FullCovVal = ushort.max / S;
  static AARun[] aaRuns;
  int curIY = int.min;

  this(Bitmap bitmap, Paint paint) {
    super(bitmap, paint);
    this.color = paint.color;
    this.aaRuns.length = bitmap.width;
    this.resetRuns();
  }

  ~this() {
    this.flush();
  }

  override void blitFH(float y, float xStart, float xEnd) {
    auto iy = to!uint(truncate(y));
    if (iy != this.curIY) {
      this.flush();
      this.curIY = iy;
    }

    auto ixStart = checkedTo!ushort(truncate(xStart));
    auto ixEnd = checkedTo!ushort(truncate(xEnd));
    if (ixStart == ixEnd)
      this.addAADot(ixStart, checkedTo!ushort(
                      lrint((xEnd - xStart) * FullCovVal)));
    else {
      FPTemporary!float covStart = 1.0 - (xStart - ixStart);
      auto aaStart = checkedTo!ushort(lrint(covStart * FullCovVal));
      FPTemporary!float covEnd = xEnd - ixEnd;
      auto aaEnd = checkedTo!ushort(lrint(covEnd * FullCovVal));
      const ushort middleCount = checkedTo!ushort(ixEnd - ixStart - 1);
      this.addAASpan(ixStart, aaStart, middleCount, FullCovVal, aaEnd);
    }
  }

  void addAADot(ushort x, ushort aaVal) {
    breakSpan(this.aaRuns, x, cast(ushort)1);
    assert(this.aaRuns[x].length == 1, to!string(this.aaRuns[x+1].length));
    this.aaRuns[x].aaSum += aaVal;
  }
  void addAASpan(ushort x, ushort aaStart, ushort middleCount, ushort aaMiddle,
                 ushort aaEnd) {
    auto runs = this.aaRuns.save;
    if (aaStart) {
      breakSpan(runs, x, cast(ushort)1);
      runs.popFrontN(x);
      assert(runs.front.length == 1);
      runs.front.aaSum += aaStart;
      runs.popFront;
      x = 0;
    }
    if (middleCount) {
      breakSpan(runs, x, middleCount);
      runs.popFrontN(x);
      x = 0;
      while (middleCount > 0) {
        runs.front.aaSum += aaMiddle;
        auto n = runs.front.length;
        runs.popFrontN(n);
        middleCount -= n;
      }
      assert(middleCount == 0);
    }
    if (aaEnd) {
      breakSpan(runs, x, cast(ushort)1);
      runs.popFrontN(x);
      assert(runs.front.length == 1);
      runs.front.aaSum += aaEnd;
    }
  }

  static void breakSpan(Range)(Range range, ushort x, ushort count) {
    assert(count > 0);
    auto runs = range.save;

    void splitRuns(size_t pos) {
      while (pos > 0) {
        auto n = runs.front.length;
        assert(n > 0);
        if (pos < n) {
          runs.front.length = to!ushort(pos);
          runs[pos].length = to!ushort(n - pos);
          runs[pos].aaSum = runs.front.aaSum;
          runs.popFrontN(pos);
          break;
        }
        pos -= n;
        runs.popFrontN(n);
      }
    }

    splitRuns(x);
    splitRuns(count);
  }

  void flush() {
    auto runs = this.aaRuns.save;
    uint x = 0;
    while (!runs.empty && runs.front.length) {
      auto n = runs.front.length;
      auto alpha = to!ubyte(runs.front.aaSum >> 8);
      if (alpha) {
        auto color = this.color;
        color.a = to!ubyte((color.a * Color.getAlphaFactor(alpha)) >> 8);
        Color32(this.bitmap.getRange(x, x + n, this.curIY), PMColor(color));
      }
      runs.popFrontN(n);
      x += n;
    }
    this.resetRuns();
  }

  void resetRuns() {
    this.aaRuns.front.length = to!ushort(this.bitmap.width);
    this.aaRuns.front.aaSum = 0;
  }
}
