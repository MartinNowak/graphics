module skia.core.pmcolor;

public import guip.color;
private import skia.math.clamp;

// Premultiplied color
struct PMColor
{
  Color _color;
  alias _color this;

  this(uint argb) {
    this.argb = argb;
  }

  this(Color color) {
    this._color = alphaMul(color, alphaScale(color.a));
    this.a = color.a;
  }
}

alias ubyte Alpha;

// This allows to shiftR 8 instead of divide by 255.
ushort alphaScale(uint alpha) {
  return alphaScale(checkedTo!ubyte(alpha));
}

ushort alphaScale(ubyte alpha) {
  return cast(ushort)(alpha + 1);
}

ushort invAlphaScale(uint alpha) {
  return invAlphaScale(checkedTo!ubyte(alpha));
}

ushort invAlphaScale(ubyte alpha) {
  return alphaScale(cast(ubyte)(255 - alpha));
}

ubyte alphaMul(ubyte alpha, uint scale) {
  assert(scale <= 256);
  return cast(ubyte)((alpha * scale) >> 8);
}

Color alphaMul(in Color color, uint scale) {
  assert(scale <= 256);
  enum rb_mask = ColorMask!("rb");

  auto c = color.argb;
  auto rb = ((c & rb_mask) * scale) >> 8;
  auto ag = ((c >> 8) & rb_mask) * scale;
  return Color((rb & rb_mask) | (ag & ~rb_mask));
}

enum : PMColor
{
  PMBlack     = PMColor(0xff000000),
  PMDarkGray  = PMColor(0xff444444),
  PMGray      = PMColor(0xff888888),
  PMLightGray = PMColor(0xffcccccc),
  PMWarmGray  = PMColor(0xffaab2b7),
  PMColdGray  = PMColor(0xff67748c),
  PMWhite     = PMColor(0xffffffff),
  PMRed       = PMColor(0xffff0000),
  PMGreen     = PMColor(0xff00ff00),
  PMBlue      = PMColor(0xff0000ff),
  PMYellow    = PMColor(0xffffff00),
  PMCyan      = PMColor(0xff00ffff),
  PMMagenta   = PMColor(0xffff00ff),
  PMOrange    = PMColor(0xffffa500),
}
