module skia.core.bounder;

private {
  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
}

interface Bounder {
public:
  // TODO: Revise necessity for Bounder
  final bool doIRect(in IRect rect) {
    return this.onIRect(rect);
  }
  final bool doPath(in Path path, in Paint paint, bool doFill) {
    return this.onPath(path, paint, doFill);
  }
  /*
  final bool doIRectGlyph(in IRect rect, int x, int y, in Glyph) {
    return false;
  }
  */
protected:
  void commit();
  bool onIRect(in IRect);
  bool onPath(in Path path, in Paint paint, bool doFill);
  bool onIRectGlyph(in IRect, in GlyphRec);
}

struct GlyphRec {
  IPoint lsb;
  IPoint rsb;
  ushort glyphId;
  ushort flags;
}