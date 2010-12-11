module skia.core.drawlooper;

private {
  import skia.core.canvas;
  import skia.core.paint;
}

/**
 *  Implementations of DrawLooper can be attached to a Paint. Where
 *  they are, and something is drawn to a canvas with that paint, the
 *  looper will be called, allowing it to modify the canvas and/or
 *  paint for that draw call.  More than that, via the next() method,
 *  the looper can modify the draw to be invoked multiple times
 *  (hence the name loop-er), allow it to perform effects like
 *  shadows or frame/fills, that require more than one pass.
 */
interface DrawLooper {
  void init(Canvas canvas, Paint paint);
  /**
   * Drawing is repeated while true is returned.  Each time
   * canvas/paint might be modified.  The loop is bracketed by a call
   * to init/restore.
   */
  bool drawAgain();
  void restore();
}
