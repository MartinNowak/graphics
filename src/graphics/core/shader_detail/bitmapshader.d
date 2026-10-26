module graphics.core.shader_detail.bitmapshader;

import graphics.core.pmcolor, graphics.core.shader, graphics.math.clamp;
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
    auto ipt = pt.rounded();
    if (!fitsIntoRange!("[)")(ipt.x, 0, pthis.src.width)
        || !fitsIntoRange!("[)")(ipt.y, 0, pthis.src.height))
      // transparent
      return PMColor(Color(0));
    return PMColor((cast(Bitmap*)&pthis.src).getLine!(PMColor)(ipt.y)[ipt.x]);
  }

  const Bitmap src;
}

unittest
{
    import graphics.core.matrix : Matrix;

    Bitmap src = Bitmap(Bitmap.Config.ARGB_8888, 2, 2);
    src.getRange!PMColor(0, 2, 0)[] = [PMColor(Color.Red), PMColor(Color.Green)];
    src.getRange!PMColor(0, 2, 1)[] = [PMColor(Color.Blue), PMColor(Color.Black)];
    src.opaque = true;

    auto bs = new BitmapShader(src);
    assert(bs.opaque);
    assert(bs.needsMatrix);

    // inside the source, with rounding to nearest
    assert(BitmapShader.colorAt(bs, FPoint(0.3f, 0.1f)) == PMColor(Color.Red));
    assert(BitmapShader.colorAt(bs, FPoint(1.3f, 0.3f)) == PMColor(Color.Green));
    assert(BitmapShader.colorAt(bs, FPoint(1.3f, 1.3f)) == PMColor(Color.Black));

    // outside the source: transparent
    assert(BitmapShader.colorAt(bs, FPoint(-1, 0)).argb == 0);
    assert(BitmapShader.colorAt(bs, FPoint(2, 0)).argb == 0);
    assert(BitmapShader.colorAt(bs, FPoint(0, 2)).argb == 0);

    // getRange maps the span through the shader matrix
    Matrix m;
    m.setTranslate(-1, 0);
    bs.matrix = m;
    PMColor[2] data;
    bs.getRange(1, 0, data[]);
    assert(data[0] == PMColor(Color.Red));   // (1,0) -> (0,0)
    assert(data[1] == PMColor(Color.Green)); // (2,0) -> (1,0)
}
