module graphics.core.blitter;

//debug = WHITEBOX;
debug import std.stdio;

private {
  import std.algorithm;
  import std.conv : to, roundTo;
  import std.math : lrint, round, nearbyint;
  import std.numeric : FPTemporary;
  import std.array;
  import std.range;

  import guip.bitmap;
  import graphics.core.pmcolor;
  import graphics.core.matrix;
  import graphics.core.paint;
  import graphics.core.pmcolor;
  import graphics.core.shader;
  import guip.point;
  import guip.rect;
  import graphics.core.scan : AAScale;
  import graphics.core.blitter_detail._;

  import graphics.math._;
}

class Blitter
{
  void blitRect(IRect rect) {
    this.blitRect(rect.x, rect.y, rect.width, rect.height);
  }
  final void blitRect(int x, int y, int width, int height) {
    while (--height >= 0)
      this.blitH(y++, x, x + width);
  }
  abstract void blitH(int y, int xstart, int xend);
  abstract void blitAlphaH(int y, int xstart, int xend, ubyte alpha);
  abstract void blitMask(int x, int y, in Bitmap mask);

  static Blitter Choose(Bitmap device, in Matrix matrix, Paint paint) {
    switch(device.config) {
    case Bitmap.Config.NoConfig:
      return new NullBlitter();
    case Bitmap.Config.ARGB_8888:
      {
        if (paint.shader) {
          if (paint.shader.needsMatrix)
            return new ShaderARGB32Blitter(device, paint, matrix.inverted);
          else
            return new ShaderARGB32Blitter(device, paint);
        } else
          return new ARGB32Blitter(device, paint);
      }
    default:
      assert(0, "no blitter implementation for bitmap config " ~ std.conv.to!string(device.config));
    }
  }

  static Blitter ChooseSprite(Bitmap device, Paint paint, in Bitmap source, IPoint ioff) {
    switch (device.config) {
    case Bitmap.Config.RGB_565:
      return SpriteBlitter.CreateD16(device, source, paint, ioff);
    case Bitmap.Config.ARGB_8888:
      return SpriteBlitter.CreateD32(device, source, paint, ioff);
    default:
      assert(0, "no sprite blitter implementation for bitmap config " ~ std.conv.to!string(device.config));
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
  override void blitH(int y, int xstart, int xend) {
  }
  override void blitAlphaH(int y, int xstart, int xend, ubyte alpha) {
  }
  override void blitMask(int x, int y, in Bitmap mask) {
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
  Color color;
  PMColor pmColor;
  this(Bitmap bitmap, Paint paint) {
    super(bitmap);
    this.color = paint.color;
    this.pmColor = PMColor(this.color);
  }

  override void blitH(int y, int xstart, int xend) {
    Color32(this.bitmap.getRange!PMColor(xstart, xend, y), pmColor);
  }

  override void blitAlphaH(int y, int xstart, int xend, ubyte alpha) {
    auto color = this.color;
    color.a = alphaMul(color.a, alphaScale(alpha));
    Color32(this.bitmap.getRange!PMColor(xstart, xend, y), PMColor(color));
  }

  override void blitMask(int x, int y, in Bitmap mask) {
    assert(mask.config == Bitmap.Config.A8);
    for (auto h = 0; h < mask.height; ++h) {
      BlitAASpan(this.bitmap.getRange!PMColor(x, x + mask.width, y + h),
                 (cast(Bitmap)mask).getRange!ubyte(0, mask.width, h), this.color);
    }
  }
}

class ShaderARGB32Blitter : ARGB32Blitter {
  Shader shader;
  const void function(PMColor[], const(PMColor)[], ubyte) blitRow;
  const void function(PMColor[], const(PMColor)[], ubyte) blitRowAlpha;
  PMColor[] data;

  this(Bitmap bitmap, Paint paint) {
    super(bitmap, paint);
    this.shader = paint.shader;
    auto flags = shader.opaque ? 0 : BlitRowFlags32.SrcPixelAlpha;
    this.blitRow = blitRowFactory32(flags);
    this.blitRowAlpha = blitRowFactory32(flags | BlitRowFlags32.GlobalAlpha);
  }

  this(Bitmap bitmap, Paint paint, Matrix mat) {
    this(bitmap, paint);
    this.shader.matrix = mat;
  }

  override void blitH(int y, int xstart, int xend) {
    auto dst = this.bitmap.getRange!PMColor(xstart, xend, y);
    this.data.length = xend - xstart;
    this.shader.getRange(xstart, y, this.data);
    this.blitRow(dst, this.data, 255);
  }

  override void blitAlphaH(int y, int xstart, int xend, ubyte alpha) {
    auto dst = this.bitmap.getRange!PMColor(xstart, xend, y);
    this.data.length = xend - xstart;
    this.shader.getRange(xstart, y, this.data);
    this.blitRowAlpha(dst, this.data, alpha);
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
