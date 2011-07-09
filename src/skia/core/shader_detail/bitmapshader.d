module skia.core.shader_detail.bitmapshader;

import skia.core.pmcolor, skia.core.shader, skia.math.clamp;
import guip.bitmap, guip.point;

class BitmapShader : MappingShader {
  this(in Bitmap src) {
    this.src = src;
  }

  override @property bool opaque() const { return src.opaque; }

  override void getRange(float x, float y, PMColor[] data) {
    return mapLine!(colorAt)(this, x, y, data);
  }

  static PMColor colorAt(BitmapShader pthis, in FPoint pt) {
    // round to nearest
    auto ipt = pt.round();
    if (!fitsIntoRange!("[)")(ipt.x, 0, pthis.src.width)
        || !fitsIntoRange!("[)")(ipt.y, 0, pthis.src.height))
      // transparent
      return PMColor(0);
    return PMColor((cast(Bitmap*)&pthis.src).getLine(ipt.y)[ipt.x]);
  }

  const Bitmap src;
}
