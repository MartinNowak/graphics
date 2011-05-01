module skia.core.shader;

import skia.core.matrix, skia.core.pmcolor, skia.math.clamp;
import guip.point;
import std.array, std.algorithm, std.math, std.conv : to;

class Shader {
  this() {
    this.mat.reset();
  }

  abstract void getRange(float x, float y, ref PMColor[] data);
  abstract @property bool opaque() const;

  final @property void matrix(in Matrix mat) {
    this.mat = mat;
  }

  final @property Matrix matrix() const {
    return this.mat;
  }

  final FPoint mapPoint(FPoint pt) const {
    return mat.mapPoint(pt);
  }

  Matrix mat;
}

class ColorShader : Shader {
  PMColor color;
  this(Color color) {
    this(PMColor(color));
  }
  this(PMColor color) {
    this.color = color;
  }

  override void getRange(float x, float y, ref PMColor[] data) {
    data[] = color;
  }

  @property bool opaque() const {
    return color.opaque;
  }
}

class GradientShader : Shader {
  PMColor[] clrs;
  FPoint[] pts;
  float[] dist;

  this(Color[] clrs, FPoint[] pts) {
    assert(clrs.length == pts.length);
    this.clrs = array(map!(PMColor)(clrs));
    this.pts = pts;
    this.dist.length = pts.length;
  }
  this(PMColor[] clrs, FPoint[] pts) {
    assert(clrs.length == pts.length);
    this.clrs = clrs;
    this.pts = pts;
    this.dist.length = pts.length;
  }

  override void getRange(float x, float y, ref PMColor[] data) {
    foreach(i, ref d; data) {
      d = colorAt(this.mapPoint(FPoint(x + i, y)));
    }
  }

  @property bool opaque() const {
    return this.clrs[0].opaque && this.clrs[1].opaque;
  }

  PMColor colorAt(in FPoint pt) {
    foreach(i, ptb; this.pts) {
      auto rd = rdistance(pt, ptb);
      if (rd > 1.0)
        return this.clrs[i];
      dist[i] = rd;
    }

    auto sumdist = reduce!("a + b")(0.0, dist);
    PMColor result;
    foreach(i; 0 .. dist.length) {
      auto weight = checkedTo!ubyte(255 * dist[i] / sumdist);
      result = result + alphaMul(this.clrs[i], alphaScale(weight));
    }
    return result;
  }
}

version (D_InlineAsm_X86_64) {
  float rdistance(FPoint pta, FPoint ptb) {
    auto d = ptb - pta;
    return rSqrt(d.x * d.x + d.y * d.y);
  }

  float rSqrt(float val) {
    asm {
      naked;
      rsqrtss XMM0, XMM0;
    }
  }
} else {
  float rdistance(FPoint pta, FPoint ptb) {
    return 1. / distance(pta, ptb);
  }
}
