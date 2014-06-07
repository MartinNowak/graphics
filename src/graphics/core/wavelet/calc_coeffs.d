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

void updateCoeffs(size_t K)(Quad q, uint scale, const ref FPoint[K] pts, ref float[3] coeffs) {
  auto tmp = calcInterim!K(1.0f / scale, pts);
  addInterim(q, tmp, coeffs);
}


//------------------------------------------------------------------------------

Interim calcInterim(size_t K : 2)(float rscale, const ref FPoint[2] pts) {
  Interim tmp = void;
  with (tmp)
  {
      Kx = (1.0f / 4.0f) * (pts[1].y - pts[0].y) * rscale;
      Ky = (1.0f / 4.0f) * (pts[0].x - pts[1].x) * rscale;

      Lx = (1.0f / 2.0f) * Kx * (pts[0].x + pts[1].x) * rscale;
      Ly = (1.0f / 2.0f) * Ky * (pts[0].y + pts[1].y) * rscale;
  }
  return tmp;
}

Interim calcInterim(size_t K : 3)(float rscale, const ref FPoint[3] pts) {
  Interim tmp = void;
  with (tmp)
  {
      Kx = (1.0f / 4.0f) * (pts[2].y - pts[0].y) * rscale;
      Ky = (1.0f / 4.0f) * (pts[0].x - pts[2].x) * rscale;

      immutable Lcommon = (1.0f / 24.0f) * (
          2 * (determinant(pts[0], pts[1]) + determinant(pts[1], pts[2]))
          + determinant(pts[0], pts[2])
      ) * rscale * rscale;
      immutable Ldiff = (3.0f / 24.0f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y)  * rscale * rscale;
      Lx = Lcommon + Ldiff;
      Ly = Lcommon - Ldiff;
  }
  return tmp;
}

Interim calcInterim(size_t K : 4)(float rscale, const ref FPoint[4] pts) {
  Interim tmp = void;
  with (tmp)
  {
      Kx = (1.0f / 4.0f) * (pts[3].y - pts[0].y) * rscale;
      Ky = (1.0f / 4.0f) * (pts[0].x - pts[3].x) * rscale;

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
      Lx = Lcommon + Ldiff;
      Ly = Lcommon - Ldiff;
  }
  return tmp;
}


//------------------------------------------------------------------------------

void addInterim(Quad q, in ref Interim tmp, ref float[3] coeffs) {
    with (tmp) final switch (q)
    {
    case Quad._00:
        coeffs[0] += Lx;
        coeffs[1] += Ly;
        coeffs[2] += Lx;
        break;

    case Quad._01:
        coeffs[0] += Kx - Lx;
        coeffs[1] += Ly;
        coeffs[2] += Kx - Lx;
        break;

    case Quad._10:
        coeffs[0] += Lx;
        coeffs[1] += Ky - Ly;
        coeffs[2] += -Lx;
        break;

    case Quad._11:
        coeffs[0] += Kx - Lx;
        coeffs[1] += Ky - Ly;
        coeffs[2] += -Kx + Lx;
        break;
    }
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

    return updateCoeffs!(K)(q, half, pts, coeffs);
}
