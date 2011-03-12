module skia.core.canvas;

private {
  import skia.core.bitmap;
  import skia.core.bounder;
  import skia.core.pmcolor;
  import skia.core.device;
  import skia.core.draw;
  import skia.core.drawfilter;
  import skia.core.drawlooper;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.path;
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
  DeviceFactory deviceFactory;
  Device device;
  DrawFilter drawFilter;
  Bounder bounder;
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
  /** Construct a canvas with the specified device to draw into.  The device
    * factory will be retrieved from the passed device.
    * Params:
    *     device   Specifies a device for the canvas to draw into.
  */
  this(Bitmap bitmap) {
    this(new Device(bitmap));
  }

  this(Device device) {
    this.mcRecs ~= MCRec();
    this.resetMatrix();
    this.setDevice(device);
  }

  debug @property Matrix curMatrix() const {
    return this.curMCRec.matrix;
  }
  debug @property size_t saveCount() const {
    return this.mcRecs.length;
  }

  void setDevice(Device device) {
    this.device = device;
    auto bounds = device ? device.bounds : IRect();
    foreach(ref mcRec; this.mcRecs) {
      mcRec.clip.intersect(bounds);
    }
    this.curMCRec.clip = bounds;
  }

  void setMatrix(in Matrix matrix) {
    this.curMCRec.matrix = matrix;
  }
  Matrix getMatrix() const {
    return this.curMCRec.matrix;
  }
  void resetMatrix() {
    this.setMatrix(Matrix.identityMatrix());
  }

  void setDrawFilter(DrawFilter filter) {
    this.drawFilter = filter;
  }

  /****************************************
   * Draw functions
   */
  void drawPaint(Paint paint) {
    assert(!paint.antiAlias, "Check you're paint");
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Paint);
    foreach(ref draw; cycle) {
      draw.drawPaint(paint);
    }
  }

  void drawColor(in Color c) {
    scope auto paint = new Paint(c);
    // TODO: TransferMode.SrcOver
    this.drawPaint(paint);
  }

  void drawARGB(ubyte a, ubyte r, ubyte g, ubyte b) {
    this.drawColor(Color(a, r, g, b));
  }

  void drawPath(in Path path, Paint paint) {
    // TODO: quickReject
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Path);
    foreach(ref draw; cycle) {
      draw.drawPath(path, paint);
    }
  }

  /**
     Blends the given bitmap at the current position to the canvas.
   */
  void drawBitmap(in Bitmap bitmap, Paint paint) {
    //! TODO: quickReject
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Bitmap);
    foreach(ref draw; cycle) {
      draw.drawBitmap(bitmap, paint);
    }
  }

  void drawRect(in IRect rect, Paint paint) {
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Path);
    foreach(ref draw; cycle) {
      draw.drawRect(rect, paint);
    }
  }

  void drawRoundRect(in IRect rect, int rx, int ry, Paint paint) {
    if (rx > 0 && ry > 0) {
      Path path;
      path.addRoundRect(fRect(rect), rx, ry, Path.Direction.CW);
      this.drawPath(path, paint);
    } else {
      this.drawRect(rect, paint);
    }
  }

  void drawOval(in IRect rect, Paint paint) {
    Path path;
    path.addOval(fRect(rect));
    this.drawPath(path, paint);
  }
  void drawCircle(IPoint c, float radius, Paint paint) {
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

  void drawText(string text, float x, float y, Paint paint) {
    return this.drawText(text, FPoint(x, y), paint);
  }
  void drawText(string text, FPoint pt, Paint paint) {
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Text);
    foreach(ref draw; cycle) {
      draw.drawText(text, pt, paint);
    }
  }
  void drawTextAsPaths(string text, FPoint pt, Paint paint) {
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Text);
    foreach(ref draw; cycle) {
      draw.drawTextAsPaths(text, pt, paint);
    }
  }
  void drawTextOnPath(string text, in Path path, Paint paint) {
    scope auto cycle = new DrawCycle(paint, DrawFilter.Type.Text);
    foreach(ref draw; cycle) {
      draw.drawTextOnPath(text, path, paint);
    }
  }


  /****************************************
   * Stub
   */
  bool quickReject(in IRect rect, EdgeType et) const {
    if (this.curMCRec.clip.empty)
      return true;

    if (!this.curMCRec.matrix.perspective)
      return !rect.intersects(this.curMCRec.clip);
    else {
      FRect mapped;
      this.curMCRec.matrix.mapRect(fRect(rect), mapped);
      auto ir = mapped.roundOut();
      return !ir.intersects(this.curMCRec.clip);
    }
  }

  bool quickReject(in Path path, EdgeType et) const {
    return path.empty || this.quickReject(path.bounds.roundOut(), et);
  }

  bool clipRect(in IRect rect) {
    return this.curMCRec.clip.intersect(rect);
  }

  void translate(FPoint pt) {
    this.translate(pt.x, pt.y);
  }
  void translate(float dx, float dy) {
    this.curMCRec.matrix.preTranslate(dx, dy);
  }
  void scale(float xs, float ys) {
    this.curMCRec.matrix.preScale(xs, ys);
  }
  void rotate(float deg) {
    this.curMCRec.matrix.preRotate(deg);
  }
  void rotate(float deg, float px, float py) {
    this.curMCRec.matrix.preRotate(deg, px, py);
  }
  void rotate(float deg, FPoint pt) {
    this.curMCRec.matrix.preRotate(deg, pt.x, pt.y);
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

  private class DrawCycle {
    Paint paint;
    DrawLooper drawLooper;
    DrawFilter.Type type;
    bool needFilterRestore;

    this(Paint paint, DrawFilter.Type type) {
      this.type = type;
      this.paint = paint;
      if (paint.drawLooper) {
        this.drawLooper = paint.drawLooper;
        this.drawLooper.init(this.outer, paint);
      }
    }

    ~this() {
      this.restoreFilter();
      if (this.drawLooper) {
        this.drawLooper.restore();
      }
    }

    alias int delegate(ref Draw) DrawIterDg;
    int opApply(DrawIterDg dg) {
      int res = 0;
      do {
        auto draw = Draw(this.outer.device.accessBitmap(),
          this.outer.curMCRec.matrix, this.outer.curMCRec.clip);
        // TODO: implement DrawIter here
        res = dg(draw);
      } while (res == 0 && this.drawAgain());
      return res;
    }

  private:

    bool drawAgain() {
      this.restoreFilter();

      return this.drawLooper !is null
        && this.drawLooper.drawAgain()
        && this.doFilter();
    }

    bool doFilter() {
      bool repeatDraw;
      if (this.outer.drawFilter) {
        repeatDraw = this.outer.drawFilter.filter(
          this.outer, this.paint, this.type);
        this.needFilterRestore = repeatDraw;
      }
      return repeatDraw;
    }
    void restoreFilter() {
      if (this.needFilterRestore) {
        assert(this.outer.drawFilter);
        this.outer.drawFilter.restore(
          this.outer, this.paint, this.type);
        this.needFilterRestore = false;
      }
    }
  }
};

struct MCRec {
  this(in Matrix matrix, in IRect clip, DrawFilter filter = null) {
    this.matrix = matrix;
    this.clip = clip;
    this.filter = filter;
  }
  Matrix matrix;
  IRect clip;
  DrawFilter filter;
}

struct AutoDrawLooper {
  DrawFilter filter;
  DrawLooper drawLooper;
  Canvas     canvas;
  Paint      paint;
  DrawFilter.Type type;
  bool        once;
  bool        needFilterRestore;

public:
  this(Canvas canvas, Paint paint, DrawFilter.Type type) {
    this.canvas = canvas;
    this.paint = paint;
    this.type = type;
    this.drawLooper = paint.drawLooper;
    if (this.drawLooper)
      paint.drawLooper.init(canvas, paint);
    else
      this.once = true;
    this.filter = canvas.drawFilter;
    this.needFilterRestore = false;
  }

  ~this() {
    this.restoreFilter();
    if (this.drawLooper) {
      this.drawLooper.restore();
    }
  }

  bool drawAgain() {
    // if we drew earlier with a filter, then we need to restore first
    this.restoreFilter();

    bool result;

    if (this.drawLooper) {
      result = this.drawLooper.drawAgain();
    } else {
      result = this.once;
      this.once = false;
    }

    // if we're gonna draw, give the filter a chance to do its work
    if (result && this.filter) {
      auto continueDrawing = this.filter.filter(
        this.canvas, this.paint, this.type);
      this.needFilterRestore = result = continueDrawing;
    }
    return result;
  }

private:

  void restoreFilter() {
    if (this.needFilterRestore) {
      assert(this.filter);
      this.filter.restore(this.canvas, this.paint, this.type);
      this.needFilterRestore = false;
    }
  }
};
