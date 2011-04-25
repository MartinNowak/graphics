module skia.core.glyph;

import std.conv;
import skia.core.path, skia.core.fonthost._, skia.util.format;
import freetype.freetype, guip.bitmap, guip.point, guip.size;
debug import std.stdio;

////////////////////////////////////////////////////////////////////////////////

static float measureText(string text, GlyphCache cache) {
  auto pos = FPoint(0, 0);
  foreach(gl; cache.glyphStream(text, Glyph.LoadFlag.Metrics))
    pos += gl.advance;
  return pos.x;
}

struct Glyph {

  @property string toString() const {
    return fmtString("Glyph bmpPos:%s adv:%s path:%s", bmpPos, advance, path.bounds);
  }

  Bitmap bmp;
  FPoint bmpPos;

  Path path;

  FPoint advance;
  FSize size;
  float rsbDelta, lsbDelta;

  enum LoadFlag { NoFlag=0, Metrics=(1<<0), Bitmap=(1<<1), Path=(1<<2) }
  LoadFlag loaded;
}
