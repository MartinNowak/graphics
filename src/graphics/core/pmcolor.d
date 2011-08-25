module graphics.core.pmcolor;

public import guip.color;
private import graphics.math.clamp;

// Premultiplied color
struct PMColor
{
  Color _color;
  alias _color this; // TODO: remove to avoid implicit conversions

  immutable PMColor Black     = PMColor(Color.Black);
  immutable PMColor DarkGray  = PMColor(Color.DarkGray);
  immutable PMColor Gray      = PMColor(Color.Gray);
  immutable PMColor LightGray = PMColor(Color.LightGray);
  immutable PMColor WarmGray  = PMColor(Color.WarmGray);
  immutable PMColor ColdGray  = PMColor(Color.ColdGray);
  immutable PMColor White     = PMColor(Color.White);
  immutable PMColor Red       = PMColor(Color.Red);
  immutable PMColor Green     = PMColor(Color.Green);
  immutable PMColor Blue      = PMColor(Color.Blue);
  immutable PMColor Yellow    = PMColor(Color.Yellow);
  immutable PMColor Cyan      = PMColor(Color.Cyan);
  immutable PMColor Magenta   = PMColor(Color.Magenta);
  immutable PMColor Orange    = PMColor(Color.Orange);

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
