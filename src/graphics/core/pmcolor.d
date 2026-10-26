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

unittest
{
    // Opaque colors pass through the premultiplication untouched.
    auto opaque = PMColor(Color.Red);
    assert(opaque.r == Color.Red.r);
    assert(opaque.g == Color.Red.g);
    assert(opaque.b == Color.Red.b);
    assert(opaque.a == 255);

    // Fully transparent: channels premultiply to zero, alpha is kept.
    auto transparent = PMColor(color(0, 255, 0, 0));
    assert(transparent.r == 0 && transparent.g == 0 && transparent.b == 0);
    assert(transparent.a == 0);

    // Half transparent red: r = 255 * (128+1) >> 8 == 128
    auto half = PMColor(color(128, 255, 128, 0));
    assert(half.r == 128);
    assert(half.g == 64);
    assert(half.b == 0);
    assert(half.a == 128);
}

unittest
{
    assert(alphaScale(0u) == 1);
    assert(alphaScale(255u) == 256);
    assert(alphaScale(ubyte(128)) == 129);
    assert(invAlphaScale(0u) == 256);
    assert(invAlphaScale(255u) == 1);
    assert(invAlphaScale(ubyte(254)) == 2);

    assert(alphaMul(ubyte(200), 256) == 200);
    assert(alphaMul(ubyte(200), 0) == 0);
    assert(alphaMul(ubyte(200), 128) == 100);

    assert(alphaMul(color(255, 10, 20, 30), 256) == color(255, 10, 20, 30));
    assert(alphaMul(color(255, 10, 20, 30), 0) == Color(0));

    import std.exception : assertThrown;
    assertThrown(alphaScale(256u));
    assertThrown(invAlphaScale(256u));
}
