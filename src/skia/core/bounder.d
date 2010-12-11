module skia.core.bounder;

private {
  import skia.core.point;
  import skia.core.rect;
}

interface Bounder {
public:
  // TODO: Revise necessity for Bounder
  final bool doIRect(in IRect rect) {
    return false;
  }
  /*
  final bool doIRectGlyph(in IRect rect, int x, int y, in Glyph) {
    return false;
  }
  */
protected:
  void commit();
  bool onIRect(in IRect);
  bool onIRectGlyph(in IRect, in GlyphRec);
}

struct GlyphRec {
  IPoint lsb;
  IPoint rsb;
  ushort glyphId;
  ushort flags;
}