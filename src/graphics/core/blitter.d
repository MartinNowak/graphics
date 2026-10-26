module graphics.core.blitter;

//debug = WHITEBOX;
debug import std.stdio;

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
import graphics.core.blitter_detail;

import graphics.math.clamp;

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
      assert(0, "no blitter implementation for bitmap config " ~ to!string(device.config));
    }
  }

  static Blitter ChooseSprite(Bitmap device, Paint paint, in Bitmap source, IPoint ioff) {
    switch (device.config) {
    case Bitmap.Config.ARGB_8888:
      return SpriteBlitter.CreateD32(device, source, paint, ioff);
    default:
      assert(0, "no sprite blitter implementation for bitmap config " ~ to!string(device.config));
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

    auto src = (cast(Bitmap)mask);
    auto w = src.width;
    auto colA = this.color.a;

    // Decode each mask row into runs of equal alpha; each run is one
    // constant-alpha Color32 fill.
    for (auto h = 0; h < mask.height; ++h) {
      auto dst = this.bitmap.getRange!PMColor(x, x + w, y + h);
      foreach (a, n; src.getRange!ubyte(0, w, h).group()) {
        if (a) {
          auto c = this.color;
          c.a = alphaMul(colA, alphaScale(a));
          Color32(dst[0..n], PMColor(c));
        }
        dst.popFrontExactly(n);
      }
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

  override void blitMask(int x, int y, in Bitmap mask) {
    assert(mask.config == Bitmap.Config.A8);

    auto src = (cast(Bitmap)mask);
    auto w = src.width;

    for (auto h = 0; h < mask.height; ++h) {
      auto dst = this.bitmap.getRange!PMColor(x, x + w, y + h);
      this.data.length = w;
      this.shader.getRange(x, y + h, this.data);
      foreach (a, n; src.getRange!ubyte(0, w, h).group()) {
        if (a)
          this.blitRowAlpha(dst[0..n], this.data[0..n], a);
        dst.popFrontExactly(n);
        this.data.popFrontExactly(n);
      }
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

unittest
{
    import graphics.core.testing : pixel, solidPaint;

    auto device = Bitmap(Bitmap.Config.ARGB_8888, 4, 4);
    device.eraseColor(Color.White);

    // solid-color blitter
    auto paint = solidPaint(Color.Red);
    auto b = Blitter.Choose(device, Matrix(), paint);
    assert(cast(ARGB32Blitter) b !is null);
    b.blitH(0, 0, 2);
    assert(pixel(device, 0, 0) == Color.Red && pixel(device, 1, 0) == Color.Red);
    assert(pixel(device, 2, 0) == PMColor(Color.White));

    // blitRect(x, y, w, h) fills a rect
    b.blitRect(1, 1, 2, 2);
    assert(pixel(device, 1, 1) == Color.Red);
    assert(pixel(device, 2, 2) == Color.Red);
    assert(pixel(device, 3, 2) == PMColor(Color.White));

    // blitAlphaH with a translucent global alpha
    device.eraseColor(Color.White);
    b.blitAlphaH(0, 0, 1, 128);
    auto px = pixel(device, 0, 0);
    // red premul * 129 >> 8 = 128; white * 128 >> 8 = 127
    assert(px.r == 128 + 127 && px.g == 127 && px.a == 128 + 127);

    // NoConfig devices get a NullBlitter
    auto empty = Bitmap(Bitmap.Config.NoConfig, 0, 0);
    assert(cast(NullBlitter) Blitter.Choose(empty, Matrix(), paint) !is null);

    // blitMask with an A8 mask: run of 255 then run of 0
    device.eraseColor(Color.White);
    Bitmap mask = Bitmap(Bitmap.Config.A8, 2, 1);
    mask.getRange!ubyte(0, 2, 0)[] = [255, 0];
    b.blitMask(0, 0, mask);
    assert(pixel(device, 0, 0) == Color.Red);
    assert(pixel(device, 1, 0) == PMColor(Color.White));
}

unittest
{
    // shader-driven blits
    auto device = Bitmap(Bitmap.Config.ARGB_8888, 3, 1);
    device.eraseColor(Color.Black);

    Paint paint;
    paint.shader = new ColorShader(Color.Green);
    auto b = Blitter.Choose(device, Matrix(), paint);
    auto sb = cast(ShaderARGB32Blitter) b;
    assert(sb !is null);
    b.blitH(0, 0, 3);
    foreach (px; device.getLine!PMColor(0))
        assert(px == Color.Green);

    // a mapping shader is fed the inverted device matrix
    Bitmap src = Bitmap(Bitmap.Config.ARGB_8888, 1, 1);
    src.getRange!PMColor(0, 1, 0)[] = [PMColor(Color.Blue)];
    src.opaque = true;
    paint.shader = new BitmapShader(src);
    assert(paint.shader.needsMatrix);
    Matrix m;
    m.setTranslate(1, 0); // device space shifted right; shader space = device - 1
    b = Blitter.Choose(device, m, paint);
    sb = cast(ShaderARGB32Blitter) b;
    assert(sb !is null);
    // mapPt(1, 0): inverted of translate(1,0) is translate(-1,0) -> (0,0) -> the single src pixel
    b.blitH(0, 1, 2);
    assert(device.getLine!PMColor(0)[1] == Color.Blue);

    // mask blit through a shader
    device.eraseColor(Color.Black);
    Bitmap mask = Bitmap(Bitmap.Config.A8, 2, 1);
    mask.getRange!ubyte(0, 2, 0)[] = [0, 255];
    b.blitMask(0, 0, mask);
    assert(device.getLine!PMColor(0)[0] == PMColor(Color.Black));
    assert(device.getLine!PMColor(0)[1] == Color.Blue);
}
