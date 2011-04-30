module skia.core.shader;

import skia.core.pmcolor, skia.math.clamp;
import guip.point;
import std.array, std.algorithm, std.math, std.conv : to;

interface Shader {
  void getRange(int x, int y, ref PMColor[] data);
  @property bool opaque() const;
}

class ColorShader : Shader {
  PMColor color;
  this(Color color) {
    this(PMColor(color));
  }
  this(PMColor color) {
    this.color = color;
  }

  void getRange(int x, int y, ref PMColor[] data) {
    data[] = color;
  }

  @property bool opaque() const {
    return color.opaque;
  }
}

class GradientShader : Shader {
  PMColor[] clrs;
  IPoint[] pts;

  this(Color[] clrs, IPoint[] pts) {
    assert(clrs.length == pts.length);
    this.clrs = array(map!(PMColor)(clrs));
    this.pts = pts;
  }
  this(PMColor[] clrs, IPoint[] pts) {
    assert(clrs.length == pts.length);
    this.clrs = clrs;
    this.pts = pts;
  }

  void getRange(int x, int y, ref PMColor[] data) {
    foreach(int i, ref d; data)
      d = colorAt(IPoint(x + i, y));
  }

  @property bool opaque() const {
    return this.clrs[0].opaque && this.clrs[1].opaque;
  }

  PMColor colorAt(in IPoint pt) const {
    foreach(i, cpt; this.pts)
      if (pt == cpt) return this.clrs[i];

    float calcDist(IPoint ptb) { return rdistance(ptb, pt); }
    auto dist = map!(calcDist)(this.pts);
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
  float rdistance(IPoint pta, IPoint ptb) {
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
  float rdistance(IPoint pta, IPoint ptb) {
    return 1. / distance(pta, ptb);
  }
}
