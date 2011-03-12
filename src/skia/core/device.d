module skia.core.device;

private import guip.bitmap;
// import skia.core.canvas; // circular dependency
import skia.core.pmcolor;
import skia.core.draw;
import guip.rect;


/****************************************
 * DeviceFactory

 * Devices that extend SkDevice should also implemet a SkDeviceFactory
 * to pass into Canvas.  Doing so will eliminate the need to extend
 * Canvas as well.
 */
interface DeviceFactory {
public:
  abstract Device newDevice(Bitmap.Config config, int width, int height,
			    bool isOpaque, bool isForLayer);
};

class RasterDeviceFactory : DeviceFactory
{
public:
  Device newDevice(Bitmap.Config config, int width, int height,
		   bool isOpaque, bool isForLayer) const
  {
    auto bitmap = Bitmap();
    bitmap.opaque = isOpaque;
    bitmap.setConfig(config, width, height);

    // buffer is already initialized
    /*
    if (!bitmap.opaque)
      bitmap.eraseARGB(0, 0, 0, 0);
    */
    return new Device(bitmap);
  }

};

class Device
{
  Bitmap bitmap;
public:

  /****************************************
   * Construct a new device, extracting the
   * width/height/config/isOpaque values from the bitmap.
   * Params:
   *      bitmap = A copy of this bitmap is made and stored in the device
   */
  this(Bitmap bitmap) {
    this.bitmap = bitmap;
  }

  DeviceFactory getDeviceFactory() {
    return new RasterDeviceFactory;
  }

  enum Capabilities {
    kGL_Capability     = 0x1,  /// mask indicating GL support
    kVector_Capability = 0x2,  /// mask indicating a vector representation
    kAll_Capabilities  = 0x3
  };

  uint getDeviceCapabilities() { return 0; }

  /** Return the width of the device (in pixels).
   */
  @property uint width() const { return this.bitmap.width; }
  /** Return the height of the device (in pixels).
   */
  @property uint height() const { return this.bitmap.height; }
  /** Return the bitmap config of the device's pixels
   */
  @property Bitmap.Config config() const { return bitmap.config; }
  /** Returns true if the device's bitmap's config treats every pixels as
      implicitly opaque.
  */
  @property bool opaque() const { return this.bitmap.opaque; }

  /** Return the bounds of the device
   */
  @property IRect bounds() const {
    return this.bitmap.bounds;
  }

  /** Return true if the specified rectangle intersects the bounds of the
      device. If sect is not NULL and there is an intersection, sect returns
      the intersection.
  */
  bool intersects(in IRect r) const {
    return this.bounds.intersects(r);
  }

  /** Return the bitmap associated with this device. Call this each time you need
    * to access the bitmap, as it notifies the subclass to perform any flushing
    * etc. before you examine the pixels.
    * Params:
    *      changePixels = set to true if the caller plans to change the pixels
    * Returns:
    *      the device's bitmap
    */
  Bitmap accessBitmap() {
    return this.bitmap;
  }

  /** Helper to erase the entire device to the specified color (including
      alpha).
  */
  void eraseColor(Color eraseColor) {
    this.bitmap.eraseColor(PMColor(eraseColor));
  }

  /** Called when this device is installed into a Canvas. Balanaced by a call
      to unlockPixels() when the device is removed from a Canvas.
  */
  void lockPixels() {}
  void unlockPixels() {}

  /** Called with the correct matrix and clip before this device is drawn
      to using those settings. If your subclass overrides this, be sure to
      call through to the base class as well.
  */
  //  void setMatrixClip(in Matrix, int Region) {}

  /** Called when this device gains focus (i.e becomes the current device
      for drawing).
  */
  //  void gainFocus(in Canvas) {}
}
  /++
  /** These are called inside the per-device-layer loop for each draw call.
    * When these are called, we have already applied any saveLayer operations,
    * and are handling any looping from the paint, and any effects from the
    * DrawFilter.
    */
  void drawPaint(in Draw, in Paint paint);
  void drawPoints(in Draw, SkCanvas::PointMode mode, size_t count,
			  const SkPoint[], in Paint paint);
  void drawRect(in Draw, const SkRect& r,
			in Paint paint);
  void drawPath(in Draw, const SkPath& path,
			in Paint paint);
  void drawBitmap(in Draw, const SkBitmap& bitmap,
			  const SkMatrix& matrix, in Paint paint);
  void drawSprite(in Draw, const SkBitmap& bitmap,
			  int x, int y, in Paint paint);
  void drawText(in Draw, const void* text, size_t len,
                          SkScalar x, SkScalar y, in Paint paint);
  void drawPosText(in Draw, const void* text, size_t len,
			   const SkScalar pos[], SkScalar constY,
			   int scalarsPerPos, in Paint paint);
  void drawTextOnPath(in Draw, const void* text, size_t len,
			      const SkPath& path, const SkMatrix* matrix,
			      in Paint paint);
  void drawVertices(in Draw, SkCanvas::VertexMode, int vertexCount,
			    const SkPoint verts[], const SkPoint texs[],
			    const SkColor colors[], SkXfermode* xmode,
			    const uint16_t indices[], int indexCount,
			    in Paint paint);
  void drawDevice(in Draw draw, in Device, int x, int y,
		  in Paint paint) {
    draw.drawSprite(device.accessBitmap(), x, y, paint);
  }
}


protected:
    /** Update as needed the pixel value in the bitmap, so that the caller can access
        the pixels directly. Note: only the pixels field should be altered. The config/width/height/rowbytes
        must remain unchanged.
    */
    virtual void onAccessBitmap(SkBitmap*);

private:
    SkBitmap fBitmap;
};

#endif

SkDeviceFactory::~SkDeviceFactory() {}

SkDevice::SkDevice() {}

SkDevice::SkDevice(const SkBitmap& bitmap) : fBitmap(bitmap) {}

void SkDevice::lockPixels() {
    fBitmap.lockPixels();
}

void SkDevice::unlockPixels() {
    fBitmap.unlockPixels();
}

const SkBitmap& SkDevice::accessBitmap(bool changePixels) {
    this->onAccessBitmap(&fBitmap);
    if (changePixels) {
        fBitmap.notifyPixelsChanged();
    }
    return fBitmap;
}

IRect SkDevice::getBounds() const {
    if (bounds) {
        bounds->set(0, 0, fBitmap.width(), fBitmap.height());
    }
}

void SkDevice::eraseColor(SkColor eraseColor) {
    fBitmap.eraseColor(eraseColor);
}

void SkDevice::onAccessBitmap(SkBitmap* bitmap) {}

void SkDevice::setMatrixClip(const SkMatrix&, const SkRegion&) {}

///////////////////////////////////////////////////////////////////////////////

void SkDevice::drawPaint(in Draw draw, in Paint paint) {
    draw.drawPaint(paint);
}

void SkDevice::drawPoints(in Draw draw, SkCanvas::PointMode mode, size_t count,
                              const SkPoint pts[], in Paint paint) {
    draw.drawPoints(mode, count, pts, paint);
}

void SkDevice::drawRect(in Draw draw, const SkRect& r,
                            in Paint paint) {
    draw.drawRect(r, paint);
}

void SkDevice::drawPath(in Draw draw, const SkPath& path,
                            in Paint paint) {
    draw.drawPath(path, paint);
}

void SkDevice::drawBitmap(in Draw draw, const SkBitmap& bitmap,
                              const SkMatrix& matrix, in Paint paint) {
    draw.drawBitmap(bitmap, matrix, paint);
}

void SkDevice::drawSprite(in Draw draw, const SkBitmap& bitmap,
                              int x, int y, in Paint paint) {
    draw.drawSprite(bitmap, x, y, paint);
}

void SkDevice::drawText(in Draw draw, const void* text, size_t len,
                            SkScalar x, SkScalar y, in Paint paint) {
    draw.drawText((const char*)text, len, x, y, paint);
}

void SkDevice::drawPosText(in Draw draw, const void* text, size_t len,
                               const SkScalar xpos[], SkScalar y,
                               int scalarsPerPos, in Paint paint) {
    draw.drawPosText((const char*)text, len, xpos, y, scalarsPerPos, paint);
}

void SkDevice::drawTextOnPath(in Draw draw, const void* text,
                                  size_t len, const SkPath& path,
                                  const SkMatrix* matrix,
                                  in Paint paint) {
    draw.drawTextOnPath((const char*)text, len, path, matrix, paint);
}

void SkDevice::drawVertices(in Draw draw, SkCanvas::VertexMode vmode,
                                int vertexCount,
                                const SkPoint verts[], const SkPoint textures[],
                                const SkColor colors[], SkXfermode* xmode,
                                const uint16_t indices[], int indexCount,
                                in Paint paint) {
    draw.drawVertices(vmode, vertexCount, verts, textures, colors, xmode,
                      indices, indexCount, paint);
}
+/