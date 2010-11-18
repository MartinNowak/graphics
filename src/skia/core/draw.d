module skia.core.draw;
import skia.core.bitmap;
import skia.core.paint;

// debug=PRINTF;
debug(PRINTF) private import std.stdio : printf;

struct Draw {
public:
  Bitmap bitmap;

  this(Bitmap bitmap) {
    this.bitmap = bitmap;
  }

  void drawPaint(ref const Paint p) {
    foreach (ref pix; this.bitmap.buffer) {
      pix = p.color;
    }
  }

  /++

  void    drawPoints(SkCanvas::PointMode, size_t count, const SkPoint[],
		     const SkPaint&) const;
  void    drawRect(const SkRect&, const SkPaint&) const;
  /*  To save on mallocs, we allow a flag that tells us that srcPath is
      mutable, so that we don't have to make copies of it as we transform it.
  */
  void    drawPath(const SkPath& srcPath, const SkPaint&,
		   const SkMatrix* prePathMatrix, bool pathIsMutable) const;
  void    drawBitmap(const SkBitmap&, const SkMatrix&, const SkPaint&) const;
  void    drawSprite(const SkBitmap&, int x, int y, const SkPaint&) const;
  void    drawText(const char text[], size_t byteLength, SkScalar x,
		   SkScalar y, const SkPaint& paint) const;
  void    drawPosText(const char text[], size_t byteLength,
		      const SkScalar pos[], SkScalar constY,
		      int scalarsPerPosition, const SkPaint& paint) const;
  void    drawTextOnPath(const char text[], size_t byteLength,
			 const SkPath&, const SkMatrix*, const SkPaint&) const;
  void    drawVertices(SkCanvas::VertexMode mode, int count,
		       const SkPoint vertices[], const SkPoint textures[],
		       const SkColor colors[], SkXfermode* xmode,
		       const uint16_t indices[], int ptCount,
		       const SkPaint& paint) const;
  
  void drawPath(const SkPath& src, const SkPaint& paint) const {
    this->drawPath(src, paint, NULL, false);
  }
  
  /** Helper function that creates a mask from a path and an optional maskfilter.
      Note however, that the resulting mask will not have been actually filtered,
      that must be done afterwards (by calling filterMask). The maskfilter is provided
      solely to assist in computing the mask's bounds (if the mode requests that).
  */
  static bool DrawToMask(const SkPath& devPath, const SkIRect* clipBounds,
			 SkMaskFilter* filter, const SkMatrix* filterMatrix,
			 SkMask* mask, SkMask::CreateMode mode);
  
private:
  void    drawText_asPaths(const char text[], size_t byteLength,
			   SkScalar x, SkScalar y, const SkPaint&) const;
  void    drawDevMask(const SkMask& mask, const SkPaint&) const;
  void    drawBitmapAsMask(const SkBitmap&, const SkPaint&) const;
  
public:
  const Bitmap mBitmap;        // required
  const Matrix mMatrix;        // required
  const Region mClip;          // required
  Device       mDevice;        // optional
  Bounder      mBounder;       // optional
  DrawProcs    mProcs;         // optional
  
#ifdef SK_DEBUG
    void    validate(int width, int height) const;
#endif
+/
};
