module graphics.core.blitter_detail.sprite_blitter;

private {
  import guip.bitmap;
  import graphics.core.blitter;
  import graphics.core.blitter_detail.blit_row_factory;
  import graphics.core.pmcolor;
  import graphics.core.paint;
  import guip.point;
  import guip.rect;
}

class SpriteBlitter : Blitter {

  static SpriteBlitter CreateD32(Bitmap device, in Bitmap source,
                                 Paint paint, IPoint ioff) {
    assert(device.config == Bitmap.Config.ARGB_8888);

    auto alpha = paint.color.a;
    switch (source.config) {
    case Bitmap.Config.ARGB_8888:
      return createSpriteBlitter_D32_S32(device, source, ioff, alpha);

    default:
      return null;
    }
  }

  this (Bitmap device, in Bitmap source, IPoint ioff, ubyte alpha) {
    this.device = device;
    this.source = source;
    this.ioff = ioff;
    this.alpha = alpha;
  }

protected:

  override void blitH(int y, int xstart, int xend) {
    assert(false, "how did we get here?");
  }
  override void blitAlphaH(int y, int xstart, int xend, ubyte alpha) {
    assert(false, "how did we get here?");
  }
  override void blitMask(int x, int y, in Bitmap mask) {
    assert(false, "how did we get here?");
  }

  Bitmap device;
  const Bitmap source;
  IPoint ioff;
  ubyte alpha;
}

static SpriteBlitter createSpriteBlitter_D32_S32(Bitmap device, in Bitmap source,
                                   IPoint ioff, ubyte alpha) {
  if (alpha == 255) {
    if (!source.opaque)
      return new Sprite_D32_S32!(S32A_Opaque_BlitRow32)(device, source, ioff, alpha);
    else
      return new Sprite_D32_S32!(S32_Opaque_BlitRow32)(device, source, ioff, alpha);
  } else {
    if (!source.opaque)
      return new Sprite_D32_S32!(S32A_Blend_BlitRow32)(device, source, ioff, alpha);
    else
      return new Sprite_D32_S32!(S32_Blend_BlitRow32)(device, source, ioff, alpha);
  }
}

class Sprite_D32_S32(alias blitRow) : SpriteBlitter {
public:
  this (Bitmap device, in Bitmap source, IPoint ioff, ubyte alpha) {
    super(device, source, ioff, alpha);
    assert(this.source.config == Bitmap.Config.ARGB_8888);
  }

  override void blitRect(IRect rect) {
    assert(!rect.empty);
    auto curTop = rect.top;
    while (curTop < rect.bottom) {
      auto dst = this.device.getRange!(PMColor)(rect.left, rect.right, curTop);
      auto src = this.source.getRange!(PMColor)(
        rect.left - this.ioff.x, rect.right - this.ioff.x, curTop - this.ioff.y);
      blitRow(dst, src, this.alpha);
      ++curTop;
    }
  }
}

unittest
{
    auto device = Bitmap(Bitmap.Config.ARGB_8888, 4, 4);
    device.eraseColor(Color.White);

    Bitmap source = Bitmap(Bitmap.Config.ARGB_8888, 2, 2);
    source.opaque = true;
    foreach (y; 0 .. 2)
        source.getRange!PMColor(0, 2, y)[] = [PMColor(Color.Red), PMColor(Color.Red)];

    // opaque source, full alpha -> straight copy at ioff
    Paint paint;
    paint.shader = null;
    paint.color = Color.Black; // a = 255
    auto s = SpriteBlitter.CreateD32(device, source, paint, IPoint(1, 1));
    assert(s !is null);
    s.blitRect(IRect(1, 1, 3, 3));
    assert(device.getLine!PMColor(1)[1] == Color.Red);
    assert(device.getLine!PMColor(2)[2] == Color.Red);
    assert(device.getLine!PMColor(0)[0] == PMColor(Color.White));
    assert(device.getLine!PMColor(3)[3] == PMColor(Color.White));

    // an A8 source has no sprite blitter
    Bitmap a8 = Bitmap(Bitmap.Config.A8, 2, 2);
    assert(SpriteBlitter.CreateD32(device, a8, paint, IPoint(0, 0)) is null);

    // non-opaque source, translucent global alpha blends
    device.eraseColor(Color.White);
    source.opaque = false;
    foreach (y; 0 .. 2)
        source.getRange!PMColor(0, 2, y)[] = [PMColor(Color.Red), PMColor(Color.Red)];
    paint.color = color(128, 255, 255, 255);
    s = SpriteBlitter.CreateD32(device, source, paint, IPoint(0, 0));
    s.blitRect(IRect(0, 0, 2, 2));
    // S32_Blend with alpha 128: src (255,0,0,255)*129>>8 = (128,..,a128)
    // dst white *128>>8 = 127
    auto px = device.getLine!PMColor(0)[0];
    assert(px.r == 255 && px.g == 127 && px.b == 127 && px.a == 255);
}
