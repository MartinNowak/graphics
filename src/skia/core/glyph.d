module skia.core.glyph;

private {
  import std.conv;

  import skia.core.bitmap;
  import skia.core.path;
  import skia.core.point;

  import skia.core.fonthost.freetype;
  import freetype.freetype;

  debug import std.stdio;
}

////////////////////////////////////////////////////////////////////////////////

static float measureText(GlyphStream)(string text) {
  auto start = FPoint(0, 0);
  FPoint end;
  foreach(pos, _; GlyphStream(text, start)) {
    end = pos;
  }
  return end.x;
}


struct BitmapGlyphStream {
  string text;
  FPoint loc;

  this(string text, FPoint loc) {
    this.text = text;
    this.loc = loc;
  }

  alias int delegate(ref FPoint loc, ref STBitmapGlyph glyph) GlyphStreamDg;
  int opApply(GlyphStreamDg dg) {

    if ((face.face_flags & FT_Face_Flag.KERNING) == 0) {
      foreach(dchar ch; text) {
        auto bitmapGlyph = getBitmapGlyph(ch);

        if (bitmapGlyph.width > 0) {
          auto pos = this.loc + bitmapGlyph.topLeftOffset;
          auto res = dg(pos, bitmapGlyph);
          if (res) return res;
          this.loc += bitmapGlyph.advance;
        } else {
          assert(bitmapGlyph.advance == FPoint(0, 0));
        }
      }
    } else {
      FT_UInt prev;
      foreach(dchar ch; text) {
        auto bitmapGlyph = getBitmapGlyph(ch);

        if (prev && bitmapGlyph.faceIndex) {
          FT_Vector delta;
          FT_Get_Kerning(cast(FT_Face)face, prev,
                         bitmapGlyph.faceIndex, FT_Kerning_Mode.Default, &delta);
          this.loc += ScaleFT_Vector(delta);
        }
        prev = bitmapGlyph.faceIndex;

        if (bitmapGlyph.width > 0) {
          auto pos = this.loc + bitmapGlyph.topLeftOffset;
          auto res = dg(pos, bitmapGlyph);
          if (res) return res;
          this.loc += bitmapGlyph.advance;
        } else {
          assert(bitmapGlyph.advance == FPoint(0, 0));
        }
      }
    }

    return 0;
  }
}


struct PathGlyphStream {
  string text;
  FPoint loc;

  this(string text, FPoint loc) {
    this.text = text;
    this.loc = loc;
  }

  alias int delegate(ref FPoint pos, ref const Path path) GlyphPathStreamDg;
  int opApply(GlyphPathStreamDg dg) {

    if ((face.face_flags & FT_Face_Flag.KERNING) == 0) {
      foreach(dchar ch; text) {
        auto pathGlyph = getPathGlyph(ch);
        auto res = dg(this.loc, pathGlyph._path);
        if (res) return res;
        this.loc += pathGlyph.advance;
      }
    } else {
      FT_UInt prev;
      foreach(dchar ch; text) {
        auto pathGlyph = getPathGlyph(ch);

        if (prev && pathGlyph.faceIndex) {
          FT_Vector delta;
          FT_Get_Kerning(cast(FT_Face)face, prev,
                         pathGlyph.faceIndex, FT_Kerning_Mode.Default, &delta);
          this.loc += ScaleFT_Vector(delta);
        }
        prev = pathGlyph.faceIndex;

        auto res = dg(this.loc, pathGlyph._path);
        if (res) return res;
        this.loc += pathGlyph.advance;
      }
    }

    return 0;
  }
}
