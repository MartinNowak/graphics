module graphics.core.wavelet.calc_coeffs;

import guip.point;
import graphics.math.poly;

enum Quad {
  _00, // top-left
  _01, // top-right
  _10, // bottom-left
  _11, // bottom-right
};


//==============================================================================

//------------------------------------------------------------------------------

struct Interim {
  float Kx, Ky, Lx, Ly;
};


//------------------------------------------------------------------------------

void updateCoeffs(size_t K, Quad Q)(uint scale, const ref FPoint[K] pts, ref float[3] coeffs) {
  auto tmp = calcInterim!K(1.0f / scale, pts);
  addInterim!Q(tmp, coeffs);
}


//------------------------------------------------------------------------------

Interim calcInterim(size_t K : 2)(float rscale, const ref FPoint[2] pts) {
  Interim tmp = void;
  tmp.Kx = (1.0f / 4.0f) * (pts[1].y - pts[0].y) * rscale;
  tmp.Ky = (1.0f / 4.0f) * (pts[0].x - pts[1].x) * rscale;

  tmp.Lx = (1.0f / 2.0f) * tmp.Kx * (pts[0].x + pts[1].x) * rscale;
  tmp.Ly = (1.0f / 2.0f) * tmp.Ky * (pts[0].y + pts[1].y) * rscale;

  return tmp;
}

Interim calcInterim(size_t K : 3)(float rscale, const ref FPoint[3] pts) {
  Interim tmp = void;
  tmp.Kx = (1.0f / 4.0f) * (pts[2].y - pts[0].y) * rscale;
  tmp.Ky = (1.0f / 4.0f) * (pts[0].x - pts[2].x) * rscale;

  immutable Lcommon = (1.0f / 24.0f) * (
      2 * (determinant(pts[0], pts[1]) + determinant(pts[1], pts[2]))
      + determinant(pts[0], pts[2])
  ) * rscale * rscale;
  immutable Ldiff = (3.0f / 24.0f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}

Interim calcInterim(size_t K : 4)(float rscale, const ref FPoint[4] pts) {
  Interim tmp = void;
  tmp.Kx = (1.0f / 4.0f) * (pts[3].y - pts[0].y) * rscale;
  tmp.Ky = (1.0f / 4.0f) * (pts[0].x - pts[3].x) * rscale;

  immutable Lcommon = (1.0f / 80.0f) * (
      3 * (
          2 * (determinant(pts[2], pts[3]) + determinant(pts[0], pts[1]))
          + determinant(pts[1], pts[2])
          + determinant(pts[1], pts[3])
          + determinant(pts[0], pts[2])
      )
      + determinant(pts[0], pts[3])
  ) * rscale * rscale;
  immutable Ldiff = (10.0f / 80.0f) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}


//------------------------------------------------------------------------------

void addInterim(Quad Q : Quad._00)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Lx;
}

void addInterim(Quad Q : Quad._01)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Kx - tmp.Lx;
}

void addInterim(Quad Q : Quad._10)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Lx;
}

void addInterim(Quad Q : Quad._11)(in Interim tmp, ref float[3] coeffs) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Kx + tmp.Lx;
}


//------------------------------------------------------------------------------

void calcCoeffs(size_t K)(IPoint pos, uint half, Quad q, ref FPoint[K] pts, ref float[3] coeffs)
{
    pos.x &= ~(half - 1);
    pos.y &= ~(half - 1);
    immutable float xo = pos.x;
    immutable float yo = pos.y;
    foreach(i; SIota!(0, K))
    {
        pts[i].x -= xo;
        pts[i].y -= yo;
    }

    final switch (q)
    {
    case Quad._00:
        return updateCoeffs!(K, Quad._00)(half, pts, coeffs);
    case Quad._01:
        return updateCoeffs!(K, Quad._01)(half, pts, coeffs);
    case Quad._10:
        return updateCoeffs!(K, Quad._10)(half, pts, coeffs);
    case Quad._11:
        return updateCoeffs!(K, Quad._11)(half, pts, coeffs);
    }
}
