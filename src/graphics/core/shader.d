module graphics.core.shader;

import graphics.core.matrix, graphics.core.pmcolor, graphics.math.clamp;
import guip.point;
import std.array, std.algorithm, std.math, std.conv : to;
public import graphics.core.shader_detail._;

abstract class Shader {
  this() {
    this.mat.reset();
  }

  abstract void getRange(float x, float y, PMColor[] data);
  abstract @property bool opaque() const;
  @property bool needsMatrix() const { return false; }

  final @property void matrix(in Matrix mat) {
    this.mat = mat;
  }

  final FPoint mapPt(FPoint dst) {
    return this.matrix * dst;
  }

  protected final @property auto ref Matrix matrix() {
    return this.mat;
  }

private:
  // dynamically store matrix for non-mapping shaders ??
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

  override void getRange(float x, float y, PMColor[] data) {
    data[] = color;
  }

  override @property bool opaque() const {
    return color.opaque;
  }
}

abstract class MappingShader : Shader {
  final override @property bool needsMatrix() const { return true; }

  static void mapLine(alias colorAt, TShader)
    (TShader pthis, float x, float y, PMColor[] data) {
    if (data.length == 1) {
      // @@ BUG @@
      // data.front = colorAt(mapPt(FPoint(x, y)));
      data[0] = colorAt(pthis, pthis.mapPt(FPoint(x, y)));
      return;
    }

    if (!pthis.matrix.perspective) {
      auto p0 = pthis.mapPt(FPoint(x, y));
      auto p1 = pthis.mapPt(FPoint(x + data.length - 1, y));

      auto delta = p1 - p0;
      auto scale = 1. / (data.length - 1);
      foreach(i, ref d; data)
        d = colorAt(pthis, p0 + delta * (i * scale));
    } else {
      foreach(i, ref d; data)
        d = colorAt(pthis, pthis.mapPt(FPoint(x + i, y)));
    }
  }
}

class GradientShader : MappingShader {
  PMColor[] clrs;
  FPoint[] pts;
  float[] dist;

  this(Color[] clrs, FPoint[] pts) {
    assert(clrs.length == pts.length);
    //    this(array(map!(PMColor)(clrs)), pts); @@ BUG @@
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

  override @property bool opaque() const {
    foreach(cl; this.clrs)
      if (!cl.opaque)
        return false;
    return true;
  }

  override void getRange(float x, float y, PMColor[] data) {
    return mapLine!colorAt(this, x, y, data);
  }

  static PMColor colorAt(GradientShader pthis, in FPoint pt) {
    foreach(i, ptb; pthis.pts) {
      auto rd = rdistance(pt, ptb);
      if (rd > 1.0)
        return pthis.clrs[i];
      pthis.dist[i] = rd;
    }

    auto sumdist = reduce!("a + b")(0.0, pthis.dist);
    PMColor result;
    foreach(i; 0 .. pthis.dist.length) {
      auto weight = checkedTo!ubyte(255 * pthis.dist[i] / sumdist);
      result = result + alphaMul(pthis.clrs[i], alphaScale(weight));
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
      ret;
    }
  }
} else {
  float rdistance(FPoint pta, FPoint ptb) {
    return 1. / distance(pta, ptb);
  }
}

unittest
{
    import std.math : abs, sqrt;

    // ColorShader fills the span with its color
    auto cs = new ColorShader(Color.Red);
    assert(cs.opaque);
    assert(!cs.needsMatrix);
    PMColor[3] data;
    cs.getRange(0, 0, data[]);
    foreach (d; data)
        assert(d == Color.Red);

    // translucent color shaders are not opaque
    assert(!(new ColorShader(color(128, 0, 0, 0))).opaque);

    // mapPt uses the shader matrix
    Matrix m;
    m.setTranslate(5, 10);
    cs.matrix = m;
    auto p = cs.mapPt(FPoint(1, 1));
    assert(abs(p.x - 6) < 1e-4 && abs(p.y - 11) < 1e-4);

    // rdistance returns the reciprocal distance: rsqrtss on x86_64,
    // 1/distance elsewhere — a 3-4-5 triangle gives 1/5 either way.
    // One shared tolerance covers both: rsqrtss is only an estimate
    // (max rel. err. ~3.7e-4), 1/distance is exact.
    import std.conv : to;
    auto rd = rdistance(FPoint(0, 0), FPoint(3, 4));
    assert(abs(rd - 0.2f) < 1e-3f, "rdistance = " ~ rd.to!string);
}

unittest
{
    import std.math : abs;

    // gradient between two point sources
    auto gs = new GradientShader([Color.Red, Color.Blue],
                                 [FPoint(0, 0), FPoint(10, 0)]);
    assert(gs.opaque);
    assert(gs.needsMatrix);

    // right at a stop: pure stop color
    auto at = GradientShader.colorAt(gs, FPoint(0, 0));
    assert(at == PMColor(Color.Red));
    at = GradientShader.colorAt(gs, FPoint(10, 0));
    assert(at == PMColor(Color.Blue));

    // far from every stop: still a blend, weighted toward the nearest stop
    at = GradientShader.colorAt(gs, FPoint(100, 0));
    assert(at.r > 0 && at.b > 0);
    assert(at.b >= at.r); // nearer to the blue stop

    // in between: weighted blend of both stops
    at = GradientShader.colorAt(gs, FPoint(5, 0));
    assert(at.r > 0 && at.b > 0);
    assert(at.r > at.b - 8 && at.b > at.r - 8); // roughly balanced

    // getRange interpolates along the span (identity matrix, fast path)
    PMColor[3] data;
    gs.getRange(5, 0, data[]);
    assert(data.length == 3);
    foreach (d; data)
        assert(d.r > 0 && d.b > 0);

    // single-pixel spans take the documented buggy path
    PMColor[1] one;
    gs.getRange(0, 0, one[]);
    assert(one[0] == PMColor(Color.Red));
}
