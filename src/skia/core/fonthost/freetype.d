module skia.core.fonthost.freetype;

private {
  import std.c.string : memcpy;
  import freetype.freetype;
  import freetype.outline;

  import guip.bitmap;
  import skia.core.path;
  import guip.point;
}

// TODO: Fix immutable cache objects
//alias immutable(BitmapGlyph) STBitmapGlyph;
//alias immutable(PathGlyph) STPathGlyph;

alias BitmapGlyph STBitmapGlyph;
alias PathGlyph STPathGlyph;

STBitmapGlyph[dchar] bitmapGlyphCache;
STPathGlyph[dchar] pathGlyphCache;
FT_Library library;
FT_Face face;

// TODO: Add font loading interface
static this() {
  FT_Error error = FT_Init_FreeType(cast(FT_Library*)&library);
  error = FT_New_Face(cast(FT_Library)library,
                      //"/usr/local/lib/X11/fonts/bitstream-vera/VeraSe.ttf".ptr,
                      //"/usr/local/lib/X11/fonts/TrueType/bkai00mp.ttf".ptr,
                      //"/usr/local/lib/X11/fonts/dejavu/DejaVuSansCondensed.ttf".ptr,
                      "/home/dawg/RUNNING ON EMPTY.ttf".ptr,
                      0, cast(FT_Face*)&face);
  error = FT_Set_Pixel_Sizes(cast(FT_Face)face, 0, 12);
  assert(!error);
}

enum Scale26D6 = 1.0f / 64;
FPoint ScaleFT_Vector(FT_Vector vec) {
  return FPoint(vec.x, vec.y) * Scale26D6;
}

STBitmapGlyph getBitmapGlyph(dchar ch) {
  return cast(STBitmapGlyph)bitmapGlyphCache.get(ch, loadBitmapGlyph(ch));
}

STPathGlyph getPathGlyph(dchar ch) {
  return cast(STPathGlyph)pathGlyphCache.get(ch, loadPathGlyph(ch));
}

struct BitmapGlyph {
  FPoint topLeftOffset;
  FPoint advance;
  Bitmap _bitmap;
  FT_UInt faceIndex;
  alias _bitmap this;

  this(FT_GlyphSlot glyph, FT_UInt faceIndex) {
    this.setConfig(Bitmap.Config.A8, glyph.bitmap.width, glyph.bitmap.rows);
    memcpy(this.getBuffer!(ubyte)().ptr, glyph.bitmap.buffer,
           this.width * this.height * ubyte.sizeof);

    this.topLeftOffset = FPoint(glyph.bitmap_left, -glyph.bitmap_top);
    this.advance = ScaleFT_Vector(glyph.advance);
    this.faceIndex = faceIndex;
  }

  @property string toString() {
    string res;
    for(auto h = 0; h < this.height; ++h) {
      for(auto w = 0; w < this.width; ++w)
        res ~= to!string(this.getBuffer!ubyte()[h*w + w]) ~ "|";
      res ~= "\n";
    }
    return res;
  }
}


struct PathGlyph
{
  FPoint advance;
  FT_UInt faceIndex;
  Path _path;
  alias _path this;

  this(FT_GlyphSlot glyph, FT_UInt faceIndex) {
    this.advance = ScaleFT_Vector(glyph.advance);
    this.faceIndex = faceIndex;
  }

  @property string toString() {
    return this.advance.toString() ~ this._path.toString();
  }
}

private:

STBitmapGlyph loadBitmapGlyph(dchar ch) {
  auto glyphIndex = FT_Get_Char_Index(cast(FT_Face)face, ch);
  auto error = FT_Load_Glyph(cast(FT_Face)face, glyphIndex, FT_LOAD.Render);
  if (!error) {
    auto bitmapGlyph = cast(STBitmapGlyph)BitmapGlyph(face.glyph, glyphIndex);
    bitmapGlyphCache[ch] = bitmapGlyph;
    return bitmapGlyph;
  } else {
    return BitmapGlyph();
  }
}

STPathGlyph loadPathGlyph(dchar ch) {
  uint flags;
  flags &= ~FT_LOAD.Render;
  flags |= FT_LOAD.NO_BITMAP;
  auto glyphIndex = FT_Get_Char_Index(cast(FT_Face)face, ch);
  auto error = FT_Load_Glyph(cast(FT_Face)face, glyphIndex, flags);

  if (!error)
  {
    auto pathGlyph = PathGlyph(face.glyph, glyphIndex);
    auto funcs = getCallbacks();

    Path path;
    if (FT_Outline_Decompose(&face.glyph.outline, &funcs, &pathGlyph._path) != 0) {
      assert(false, "Failed to render glyph as path");
      path.reset();
    } else
      path.close();

    auto immPathGlyph = cast(STPathGlyph)pathGlyph;
    pathGlyphCache[ch] = immPathGlyph;
    return immPathGlyph;
  } else {
    return PathGlyph();
  }
}

/*
 * Callback for transforming freetype outlines to paths.
 */
FT_Outline_Funcs getCallbacks() {
    FT_Outline_Funcs funcs;

    funcs.move_to = &moveTo;
    funcs.line_to = &lineTo;
    funcs.conic_to = &quadTo;
    funcs.cubic_to = &cubicTo;
    funcs.shift = 0;
    funcs.delta = 0;
    return funcs;
}

FPoint ConvFT_Vector(const FT_Vector* v) {
  auto fp = ScaleFT_Vector(*v);
  fp.y = -fp.y;
  return fp;
}
extern(C):

int moveTo(const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.close();
  path.moveTo(ConvFT_Vector(to));
  return 0;
}

int lineTo(const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.lineTo(ConvFT_Vector(to));
  return 0;
}

int quadTo(const FT_Vector* c1, const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.quadTo(ConvFT_Vector(c1), ConvFT_Vector(to));
  return 0;
}

int cubicTo(const FT_Vector* c1, const FT_Vector* c2,
             const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.cubicTo(ConvFT_Vector(c1), ConvFT_Vector(c2), ConvFT_Vector(to));
  return 0;
}
