module skia.core.color;
import std.stdio;
private uint getShift(string m) {
  final switch (m) {
  case "a": return 24;
  case "r": return 16;
  case "g": return 8;
  case "b": return 0;
  }
}


struct Color
{
  uint argb;

  this(uint argb) {
    this.argb = argb;
  }

  this(ubyte a, ubyte r, ubyte g, ubyte b) {
    this.a = a;
    this.r = r;
  }

  mixin SetGet!("a");
  mixin SetGet!("r");
  mixin SetGet!("g");
  mixin SetGet!("b");

private:
  mixin template SetGet(string s)
  {
    mixin("@property ubyte "~s~"() { return get!(\""~s~"\"); }");
    mixin("@property ref Color "~s~"(ubyte v) { return set!(\""~s~"\")(v); }");
  }

  ref Color set(string m)(ubyte val)
  {
    static const KShift = getShift(m);
    this.argb = this.argb & ~(0xff << KShift) | (val << KShift);
    return this;
  }

  const(ubyte) get(string m)() const {
    static const KShift = getShift(m);
    return this.argb >> KShift & 0xff;
  }

  ref Color setByte(uint i)(ubyte v)
  {
    rgba = rgba & ~(0xff << 16) | (v << 16); return this;
  }
}


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
