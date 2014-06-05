module graphics.core.pmcolor;

public import guip.color;
private import graphics.math.clamp;

// Premultiplied color
struct PMColor
{
  Color _color;
  alias _color this; // TODO: remove to avoid implicit conversions

    static immutable PMColor
        Black     = PMColor(Color.Black),
        DarkGray  = PMColor(Color.DarkGray),
        Gray      = PMColor(Color.Gray),
        LightGray = PMColor(Color.LightGray),
        WarmGray  = PMColor(Color.WarmGray),
        ColdGray  = PMColor(Color.ColdGray),
        White     = PMColor(Color.White),
        Red       = PMColor(Color.Red),
        Green     = PMColor(Color.Green),
        Blue      = PMColor(Color.Blue),
        Yellow    = PMColor(Color.Yellow),
        Cyan      = PMColor(Color.Cyan),
        Magenta   = PMColor(Color.Magenta),
        Orange    = PMColor(Color.Orange);

  this(Color color) {
    this._color = alphaMul(color, alphaScale(color.a));
    this.a = color.a;
  }
}

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
