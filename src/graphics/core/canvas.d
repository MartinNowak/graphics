module graphics.core.canvas;

private {
  import guip.bitmap;
  import graphics.core.pmcolor;
  import graphics.core.draw;
  import graphics.core.matrix;
  import graphics.core.paint;
  import graphics.core.path;
  import guip.point;
  import guip.rect;

  debug private import std.stdio : writeln, writef;
}
//debug=WHITEBOX;

enum EdgeType
{
  BW, /// Treat the edges as B&W (not antialiased) for the purposes
    /// of testing against the current clip.
  AA, /// Treat the edges as antialiased for the purposes of
    /// testing against the current clip.
}
enum PointMode
{
  kPoints,
  kLines,
  kPolygon,
}

/** \class SkCanvas

    A Canvas encapsulates all of the state about drawing into a device (bitmap).
    This includes a reference to the device itself, and a stack of matrix/clip
    values. For any given draw call (e.g. drawRect), the geometry of the object
    being drawn is transformed by the concatenation of all the matrices in the
    stack. The transformed geometry is clipped by the intersection of all of
    the clips in the stack.

    While the Canvas holds the state of the drawing device, the state (style)
    of the object being drawn is held by the Paint, which is provided as a
    parameter to each of the draw() methods. The Paint holds attributes such as
    color, typeface, textSize, strokeWidth, shader (e.g. gradients, patterns),
    etc.
*/
class Canvas {
  Bitmap _bitmap;
  MCRec[] mcRecs;
  bool deviceCMClean;

  enum SaveFlags {
    Matrix = (1<<0),
    Clip = (1<<1),
    HasAlphaLayer = (1<<2),
    FullColorLayer = (1<<3),
    ClipToLayer = (1<<4),
    MatrixClip = Matrix | Clip,
    ARGB_NoClipLayer = 0x0F,
    ARGB_ClipLayer = 0x1F,
  }

public:
  /** Construct a canvas with the specified device to draw into.
    * Params:
    *     bitmap   Specifies the bitmap for the canvas to draw into.
    */
  this(Bitmap bitmap) {
    this.mcRecs ~= MCRec();
    this.bitmap = bitmap;
    this.resetMatrix();
  }

  @property Matrix curMatrix() const {
    return this.curMCRec.matrix;
  }
  debug @property size_t saveCount() const {
    return this.mcRecs.length;
  }

  void bitmap(Bitmap bitmap) {
    this._bitmap = bitmap;
    auto bounds = bitmap.bounds;
    foreach(ref mcRec; this.mcRecs) {
      mcRec.clip.intersect(bounds);
    }
    this.curMCRec.clip = bounds;
  }

  private Bitmap bitmap() {
    return this._bitmap;
  }

  void setMatrix(in Matrix matrix) {
    this.curMCRec.matrix = matrix;
  }
  Matrix getMatrix() const {
    return this.curMCRec.matrix;
  }
  void resetMatrix() {
    this.setMatrix(Matrix());
  }

    /****************************************
     * Draw functions
     */
    void drawPaint(Paint paint)
    {
        auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
        draw.drawPaint(paint);
    }

    void drawColor(in Color c)
    {
        drawPaint(Paint(c));
    }

    void drawARGB(ubyte a, ubyte r, ubyte g, ubyte b)
    {
        drawColor(color(a, r, g, b));
    }

    void drawPath(in Path path, Paint paint)
    {
        // TODO: quickReject
        auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
        draw.drawPath(path, paint);
    }

  /**
     Blends the given bitmap at the current position to the canvas.
   */
  void drawBitmap(in Bitmap bitmap, Paint paint) {
    //! TODO: quickReject
    auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
    draw.drawBitmap(bitmap, paint);
  }

  void drawRect(in FRect rect, Paint paint) {
    auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
    draw.drawRect(rect, paint);
  }
  void drawRect(in IRect rect, Paint paint) {
    drawRect(fRect(rect), paint);
  }

  void drawRoundRect(in FRect rect, float rx, float ry, Paint paint) {
    if (rx > 0 && ry > 0) {
      Path path;
      path.addRoundRect(rect, rx, ry, Path.Direction.CW);
      this.drawPath(path, paint);
    } else {
      this.drawRect(rect, paint);
    }
  }
  final void drawRoundRect(in IRect rect, int rx, int ry, Paint paint) {
    return this.drawRoundRect(fRect(rect), rx, ry, paint);
  }

  final void drawOval(in IRect rect, Paint paint) {
    drawOval(fRect(rect), paint);
  }
  void drawOval(in FRect rect, Paint paint) {
    Path path;
    path.addOval(rect);
    this.drawPath(path, paint);
  }

  final void drawCircle(IPoint c, float radius, Paint paint) {
    return this.drawCircle(fPoint(c), radius, paint);
  }
  void drawCircle(FPoint c, float radius, Paint paint) {
    auto topL = FPoint(c.x - radius, c.y - radius);
    auto botR = topL + FPoint(2*radius, 2*radius);
    auto rect = FRect(topL, botR);

    Path path;
    path.addOval(rect);
    this.drawPath(path, paint);
  }

  final void drawText(string text, float x, float y, TextPaint paint) {
    return this.drawText(text, FPoint(x, y), paint);
  }
  void drawText(string text, FPoint pt, TextPaint paint) {
    auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
    draw.drawText(text, pt, paint);
  }
  final void drawText(string text, IPoint pt, TextPaint paint) {
    return this.drawText(text, fPoint(pt), paint);
  }

  deprecated alias drawText drawTextAsPaths;

  void drawTextOnPath(string text, in Path path, TextPaint paint) {
    auto draw = Draw(this.bitmap, this.curMCRec.matrix, this.curMCRec.clip);
    draw.drawTextOnPath(text, path, paint);
  }

  bool quickReject(in IRect rect, EdgeType et) const {
    if (this.curMCRec.clip.empty)
      return true;

    FRect mapped = this.curMCRec.matrix.mapRect(fRect(rect));
    auto ir = mapped.roundOut();
    return !ir.intersects(this.curMCRec.clip);
  }

  bool quickReject(in Path path, EdgeType et) const {
    return path.empty || this.quickReject(path.bounds.roundOut(), et);
  }

  /*
   * Sets the current clipping to an Intersection with rect. Returns
   * true if resulting clipping is non-empty.
   */
  bool clipRect(in IRect rect) {
    FRect mapped = this.curMCRec.matrix.mapRect(fRect(rect));
    auto ir = mapped.round();
    if (this.curMCRec.clip.intersect(ir))
      return true;
    this.curMCRec.clip = IRect();
    return false;
  }

  void translate(IPoint pt) {
    this.translate(pt.x, pt.y);
  }
  void translate(FPoint pt) {
    this.translate(pt.x, pt.y);
  }
  void translate(float dx, float dy) {
    this.curMCRec.matrix = this.curMCRec.matrix.preTranslate(dx, dy);
  }
  void scale(FVector v) {
    this.scale(v.x, v.y);
  }
  void scale(float xs, float ys) {
    this.curMCRec.matrix = this.curMCRec.matrix.preScale(xs, ys);
  }
  void rotate(float deg) {
    this.curMCRec.matrix = this.curMCRec.matrix.preRotate(deg);
  }
  void rotate(float deg, float px, float py) {
    this.curMCRec.matrix = this.curMCRec.matrix.preRotate(deg, px, py);
  }
  void rotate(float deg, FPoint pt) {
    this.rotate(deg, pt.x, pt.y);
  }

  /****************************************
   * Stub
   */
  size_t save(SaveFlags flags = SaveFlags.MatrixClip) {
    return this.internalSave(flags);
  }
  private final size_t internalSave(SaveFlags flags) {
    this.mcRecs ~= this.curMCRec;
    return this.mcRecs.length - 1;
  }
  @property private ref MCRec curMCRec() {
    assert(this.mcRecs.length > 0);
    return this.mcRecs[$ - 1];
  }
  @property private ref const(MCRec) curMCRec() const {
    assert(this.mcRecs.length > 0);
    return this.mcRecs[$ - 1];
  }

  void restore() {
    assert(this.mcRecs.length > 0);
    this.mcRecs = this.mcRecs[0 .. $-1];
  }
  void restoreCount(size_t sc) {
    assert(sc <= this.mcRecs.length);
    this.mcRecs = this.mcRecs[0 .. sc];
  }

  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented method "~m);
  }
}

struct MCRec {
  this(in Matrix matrix, in IRect clip) {
    this.matrix = matrix;
    this.clip = clip;
  }
  Matrix matrix;
  IRect clip;
}
