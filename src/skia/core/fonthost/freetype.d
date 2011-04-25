module skia.core.fonthost.freetype;

import core.atomic, core.sync.mutex, core.sync.rwmutex, std.exception, std.c.string : memcpy;
import freetype.freetype, freetype.outline, guip.bitmap, guip.point;
import skia.core.glyph, skia.core.fonthost.fontconfig, skia.core.paint, skia.core.path;

alias BitmapGlyph STBitmapGlyph;
alias PathGlyph STPathGlyph;

__gshared STBitmapGlyph[dchar] bitmapGlyphCache;
__gshared STPathGlyph[dchar] pathGlyphCache;
shared FT_Face _face;
shared FreeType _freeType;

@property shared(FreeType) freeType() {
  if (_freeType is null) {
    auto ft = new FreeType();
    if (cas(&_freeType, cast(FreeType)null, ft))
      _freeType.init();
  }
  return _freeType;
}

private synchronized class FreeType {
  ~this() {
    foreach(k, v; faces)
      FT_Done_Face(cast(FT_Face)v);
    FT_Done_FreeType(cast(FT_Library)library);
    _freeType = null;
  }

  void init() {
    enforce(!FT_Init_FreeType(cast(FT_Library*)&library),
      new Exception("Error during initialization of FreeType"));
  }

  shared(FT_Face) getFace(string path) {
    return faces.get(path, loadFace(path));
  }

  shared(FT_Face) loadFace(string path) {
    shared(FT_Face) face;
    enforce(!FT_New_Face(cast(FT_Library)library, toStringz(path), 0, cast(FT_Face*)&face));
    faces[path] = face;
    return face;
  }

  FT_Library library;
  FT_Face[string] faces;
}

static this() {
  auto typeface = TypeFace.defaultFace();
  _face = freeType.getFace(typeface.filename);
  enforce(!FT_Set_Char_Size(cast(FT_Face)_face, 0, 10*64, 96, 96));
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

shared(GlyphStore) _glyphStore;

@property shared(GlyphStore) glyphStore() {
  if (_glyphStore is null) {
    auto gs = new GlyphStore();
    cas(&_glyphStore, cast(GlyphStore)null, gs);
  }
  return _glyphStore;
}

synchronized class GlyphStore {
  // TODO: hash more TextPaint members
  shared(Data) getData(TypeFace face) {
    return data.get(face, newData(face));
  }

  shared(Data) newData(TypeFace face) {
    shared(Data) d;
    d.face = freeType.getFace(face.filename);
    d.mtx = new shared(ReadWriteMutex)();
    data[face] = d;
    return d;
  }

  struct Data {
    Glyph[dchar] glyphs;
    FT_Face face;
    ReadWriteMutex mtx;
  }

  Data[TypeFace] data;
}

GlyphCache getGlyphCache(TextPaint paint) {
  auto typeFace = paint.typeFace.valid()
    ? paint.typeFace
    : TypeFace.defaultFace();
  assert(typeFace.valid());
  return GlyphCache(paint, glyphStore.getData(typeFace));
}

struct GlyphCache {
  TextPaint paint;
  shared(GlyphStore.Data) data;

  enum LoadFlag { Advance, Metrics, Bitmap, Path }
  GlyphRange glyphRange(string text, LoadFlag loadFlag) {
    return GlyphRange(text, loadFlag, &this);
  }
}

struct GlyphRange {
  alias int delegate(const ref Glyph) GlyphDg;

  int opApply(GlyphDg dg) {
    if (text.length == 0)
      return 0;
    auto reader = (cast(ReadWriteMutex)cache.data.mtx).reader;
    reader.lock();
    auto glyphs = cast(Glyph[dchar])cache.data.glyphs;

    foreach(dchar c; text) {
      auto gl = glyphs.get(c, loadGlyph(c, reader));
      auto res = dg(gl); if (res) return res;
    }
    return 0;
  }

  Glyph loadGlyph(dchar c, ref ReadWriteMutex.Reader reader) {
    reader.unlock();
    auto writer = (cast(ReadWriteMutex)cache.data.mtx).writer;
    writer.lock();
    scope(exit) { writer.unlock(); reader.lock(); }

    // TODO: loadFlag
    BitmapGlyph bmpGlyph;
    synchronized(freeType) {
      bmpGlyph = getBitmapGlyph(c);
      //        auto glyph = freeType.loadGlyph(cache.data.face, c);
    }
    Glyph glyph;
    glyph.topLeft = bmpGlyph.topLeftOffset;
    glyph.advance = bmpGlyph.advance;
    glyph.bmp = bmpGlyph._bitmap;
    //      glyph.size =
    //      glyph.rsbDelta =

    cache.data.glyphs[c] = cast(shared)glyph;
    return glyph;
  }

  string text;
  GlyphCache.LoadFlag loadFlag;
  private GlyphCache* cache;
}

private:

STBitmapGlyph loadBitmapGlyph(dchar ch) {
  auto glyphIndex = FT_Get_Char_Index(cast(FT_Face)_face, ch);
  auto error = FT_Load_Glyph(cast(FT_Face)_face, glyphIndex, FT_LOAD.Render);
  if (!error) {
    auto bitmapGlyph = cast(STBitmapGlyph)BitmapGlyph((cast(FT_Face)_face).glyph, glyphIndex);
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
  auto glyphIndex = FT_Get_Char_Index(cast(FT_Face)_face, ch);
  auto error = FT_Load_Glyph(cast(FT_Face)_face, glyphIndex, flags);

  if (!error)
  {
    auto pathGlyph = PathGlyph((cast(FT_Face)_face).glyph, glyphIndex);
    auto funcs = getCallbacks();

    Path path;
    if (FT_Outline_Decompose(&(cast(FT_Face)_face).glyph.outline, &funcs, &pathGlyph._path) != 0) {
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
