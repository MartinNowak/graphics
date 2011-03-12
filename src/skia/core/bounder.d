module skia.core.bounder;

private {
  import skia.core.paint;
  import skia.core.path;
  import guip.point;
  import skia.core.rect;
}

interface Bounder {
public:
  // TODO: Revise necessity for Bounder
  final bool doIRect(in IRect rect, in Paint paint) {
    return this.onIRect(rect, paint);
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
  bool onIRect(in IRect, in Paint);
  bool onPath(in Path, in Paint, bool doFill);
  bool onIRectGlyph(in IRect, in Paint, in GlyphRec);
}

struct GlyphRec {
  IPoint lsb;
  IPoint rsb;
  ushort glyphId;
  ushort flags;
}