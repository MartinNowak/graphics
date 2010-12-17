module skia.core.drawfilter;

private {
  import skia.core.canvas;
  import skia.core.paint;
}

interface DrawFilter {
  enum Type {
    Paint,
    Point,
    Line,
    Bitmap,
    Rect,
    Path,
    Text,
  }
  /** Return true to allow the draw to continue (with possible
      modified canvas/paint). If true is returned, then restore will
      be called.
   */
  bool filter(Canvas canvas, Paint paint, Type);
  /** If filter() returned true, then restore will be called to
      restore the canvas/paint to their previous state.
   */
  void restore(Canvas canvas, Paint paint, Type);
}

class BaseDrawFilter : DrawFilter {
  this() {
  }
  bool filter(Canvas canvas, Paint paint, Type) { return true; }
  void restore(Canvas canvas, Paint paint, Type) {}
}
