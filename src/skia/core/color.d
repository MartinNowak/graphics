module skia.core.color;

private {
  debug import std.stdio;
  import std.conv : to;
  import std.algorithm;
  import std.string : toupper;
  import std.ctype : isxdigit;
}

uint getShift(char m) {
  final switch(m) {
  case 'a': return 24;
  case 'r': return 16;
  case 'g': return 8;
  case 'b': return 0;
  }
}
template Shift(char m) {
  enum Shift = getShift(m);
}

template StringToMask(string s) {
  static if (s.length)
    enum StringToMask = (0xFF << Shift!(s[0])) | StringToMask!(s[1..$]);
  else
    enum StringToMask = 0;
}

template ColorMask(string s) {
  static assert(s.length <=4 && s.length > 0);
  enum ColorMask = StringToMask!(s);
}

unittest {
  static assert(ColorMask!("rb") == 0x00ff00ff);
  static assert(ColorMask!("ab") == 0xff0000ff);
  static assert(ColorMask!("ag") == 0xff00ff00);
}

private enum hexLetters = "0123456789ABCDEF";

private char[2] toHexDigit(ubyte n) {
  return [hexLetters[(n >> 4) & 0xF], hexLetters[n & 0xF]];
}

uint fromHexDigit(dchar c) {
  assert(isxdigit(c));
  return c <= '9' ? (c & 0xF) : 9 + (c & 0xF);
}

struct Color
{
  uint argb;

  @property string toString() const {
    version (VERBOSE) {
      return "Color a: " ~ to!string(this.a) ~
        " r: " ~ to!string(this.r) ~
        " g: " ~ to!string(this.g) ~
        " b: " ~ to!string(this.b);
    } else {
      auto ret = "0x" ~ toHexDigit(this.a) ~ toHexDigit(this.r)
        ~ toHexDigit(this.g) ~ toHexDigit(this.b);
      return ret.idup;
    }
  }
  this(uint argb) {
    this.argb = argb;
  }

  this(string argbHex) {
    argbHex = argbHex.toupper();
    if (argbHex.startsWith("0X")) {
      argbHex = argbHex[2 .. $];
    }
    assert(argbHex.length == 8);
    this.argb = cast(uint)reduce!("(a << 4) + b")(
      0, map!fromHexDigit(argbHex));
  }

  unittest {
    auto argbHex = "80000000";
    assert(Color("00000001").argb == 1);
    assert(Color("80000000").argb == (1u << 31));
    const uint exp = 10u * (1<<28) + 10u * (1<<24) + 11u * (1<<20) + 11u * (1<<16)
      + 12u * (1<<12) + 12u * (1<<8) + 13u * (1<<4) + 13u;
    assert(Color("AABBCCDD").argb == exp);
  }

  this(ubyte a, ubyte r, ubyte g, ubyte b) {
    this.a = a;
    this.r = r;
    this.g = g;
    this.b = b;
  }

  static ushort getAlphaFactor(uint alpha) {
    assert(alpha <= 255);
    // This allows to shiftR 8 instead of divide by 255.
    return cast(ushort)(alpha + 1);
  }
  static ubyte getInvAlphaFactor(uint alpha) {
    assert(alpha <= 255);
    return cast(ubyte)(256 - getAlphaFactor(alpha));
  }
  Color mulAlpha(uint scale) const {
    assert(scale <= 256);
    enum rb_mask = ColorMask!("rb");

    auto c = this.argb;
    auto rb = ((c & rb_mask) * scale) >> 8;
    auto ag = ((c >> 8) & rb_mask) * scale;
    return Color((rb & rb_mask) | (ag & ~rb_mask));
  }
  Color opBinary(string op)(Color rhs) const
    if (op == "+") {
      return Color(this.argb + rhs.argb);
  }

  mixin SetGet!("a");
  mixin SetGet!("r");
  mixin SetGet!("g");
  mixin SetGet!("b");

private:
  mixin template SetGet(string s)
  {
    mixin("@property ubyte "~s~"() const { return get!('"~s~"'); }");
    mixin("@property ref Color "~s~"(ubyte v) { return set!('"~s~"')(v); }");
  }

  ref Color set(char m)(ubyte val)
  {
    static const KShift = Shift!(m);
    this.argb = this.argb & ~(0xff << KShift) | (val << KShift);
    return this;
  }

  const(ubyte) get(char m)() const {
    static const KShift = Shift!(m);
    return this.argb >> KShift & 0xff;
  }
}

// Premultiplied color
struct PMColor
{
  Color _color;
  alias _color this;

  this(uint argb) {
    this.argb = argb;
  }

  this(Color color) {
    this._color = color.mulAlpha(Color.getAlphaFactor(color.a));
    this.a = color.a;
  }
}

alias ubyte Alpha;

enum : Color
{
  Black     = Color(0xff000000),
  DarkGray  = Color(0xff444444),
  Gray      = Color(0xff888888),
  LightGray = Color(0xffcccccc),
  WarmGray  = Color(0xffaab2b7),
  ColdGray  = Color(0xff67748c),
  White     = Color(0xffffffff),
  Red       = Color(0xffff0000),
  Green     = Color(0xff00ff00),
  Blue      = Color(0xff0000ff),
  Yellow    = Color(0xffffff00),
  Cyan      = Color(0xff00ffff),
  Magenta   = Color(0xffff00ff),
  Orange    = Color(0xffffa500),
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

unittest
{
  Color c;
  c.a = 10;
  c.r = 20;
  c.g = 30;
  c.b = 40;
  auto ShiftVal = (10 << 24) | (20 << 16) | (30 << 8) | (40 << 0);
  assert(c.argb == ShiftVal);
  assert(Black.a == 255 && Black.r == 0 && Black.g == 0 && Black.b == 0);
  assert(Red.r == 255);
  assert(Green.g == 255);
  assert(Blue.b == 255);
  assert(Magenta.g == 0);
}
