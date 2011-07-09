module skia.core.shader_detail.bitmapshader;

import skia.core.pmcolor, skia.core.shader, skia.math.clamp;
import guip.bitmap, guip.point;

class BitmapShader : MappingShader {
  this(in Bitmap src) {
    this.src = src;
  }

  override @property bool opaque() const { return src.opaque; }

  override PMColor colorAt(in FPoint pt) {
    // round to nearest
    auto ipt = pt.round();
    if (!fitsIntoRange!("[)")(ipt.x, 0, src.width)
        || !fitsIntoRange!("[)")(ipt.y, 0, src.height))
      // transparent
      return PMColor(0);
    return PMColor((cast(Bitmap*)&src).getLine(ipt.y)[ipt.x]);
  }

  const Bitmap src;
}
