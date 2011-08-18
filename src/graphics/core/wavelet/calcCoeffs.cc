struct FPoint {
  float x, y;
};

struct IPoint {
  int x, y;
};

enum Quad {
  Quad00, // top-left
  Quad01, // top-right
  Quad10, // bottom-left
  Quad11, // bottom-right
};


//==============================================================================

//------------------------------------------------------------------------------

namespace {


//------------------------------------------------------------------------------

struct Interim {
  double Kx, Ky, Lx, Ly;
};


//------------------------------------------------------------------------------

template<unsigned K>
Interim calcInterim(double rscale, const FPoint pts[K]);


//------------------------------------------------------------------------------

template<unsigned K>
void addInterim(const Interim& tmp, float coeffs[3]);


//------------------------------------------------------------------------------

template<unsigned K, Quad Q>
void updateCoeffs(unsigned scale, FPoint pts[K], float coeffs[3]) {
  const Interim& tmp = calcInterim<K>(1.0 / scale, pts);
  addInterim<Q>(tmp, coeffs);
}


//------------------------------------------------------------------------------

double determinant(const FPoint& pt1, const FPoint& pt2) {
  return pt1.x * pt2.y - pt1.y * pt2.x;
}


//------------------------------------------------------------------------------

template<>
Interim calcInterim<2>(double rscale, const FPoint pts[2]) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[1].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[1].x) * rscale;

  tmp.Lx = (1.f / 2.f) * tmp.Kx * (pts[0].x + pts[1].x) * rscale;
  tmp.Ly = (1.f / 2.f) * tmp.Ky * (pts[0].y + pts[1].y) * rscale;

  return tmp;
}

template<>
Interim calcInterim<3>(double rscale, const FPoint pts[3]) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[2].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[2].x) * rscale;

  const double Lcommon = (1.f / 24.f) * (
      2 * (determinant(pts[0], pts[1]) + determinant(pts[1], pts[2]))
      + determinant(pts[0], pts[2])
  ) * rscale * rscale;
  const double Ldiff = (3.f / 24.f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}

template<>
Interim calcInterim<4>(double rscale, const FPoint pts[4]) {
  Interim tmp;
  tmp.Kx = (1.f / 4.f) * (pts[3].y - pts[0].y) * rscale;
  tmp.Ky = (1.f / 4.f) * (pts[0].x - pts[3].x) * rscale;

  const double Lcommon = (1.f / 80.f) * (
      3 * (
          2 * (determinant(pts[2], pts[3]) + determinant(pts[0], pts[1]))
          + determinant(pts[1], pts[2])
          + determinant(pts[1], pts[3])
          + determinant(pts[0], pts[2])
      )
      + determinant(pts[0], pts[3])
  ) * rscale * rscale;
  const double Ldiff = (10.f / 80.f) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y)  * rscale * rscale;
  tmp.Lx = Lcommon + Ldiff;
  tmp.Ly = Lcommon - Ldiff;

  return tmp;
}


//------------------------------------------------------------------------------

template<>
void addInterim<Quad00>(const Interim& tmp, float coeffs[3]) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Lx;
}

template<>
void addInterim<Quad01>(const Interim& tmp, float coeffs[3]) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ly;
  coeffs[2] += tmp.Kx - tmp.Lx;
}

template<>
void addInterim<Quad10>(const Interim& tmp, float coeffs[3]) {
  coeffs[0] += tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Lx;
}

template<>
void addInterim<Quad11>(const Interim& tmp, float coeffs[3]) {
  coeffs[0] += tmp.Kx - tmp.Lx;
  coeffs[1] += tmp.Ky - tmp.Ly;
  coeffs[2] += -tmp.Kx + tmp.Lx;
}


//------------------------------------------------------------------------------

template<unsigned K>
void calcCoeffs(unsigned half, unsigned qidx, IPoint* pos, FPoint pts[K], float coeffs[3]) {
  switch (qidx) {
  case 0b00:
    // (0, 0)
    updateCoeffs<K, Quad00>(half, pts, coeffs);
    break;

  case 0b01:
    pos->x -= half;
    for (unsigned i = 0; i < K; ++i)
      pts[i].x -= half;
    updateCoeffs<K, Quad01>(half, pts, coeffs);
    break;

  case 0b10:
    pos->y -= half;
    for (unsigned i = 0; i < K; ++i)
      pts[i].y -= half;
    updateCoeffs<K, Quad10>(half, pts, coeffs);
    break;

  case 0b11:
    pos->x -= half;
    pos->y -= half;
    for (unsigned i = 0; i < K; ++i) {
      pts[i].x -= half;
      pts[i].y -= half;
    }
    updateCoeffs<K, Quad11>(half, pts, coeffs);
    break;
  }
}

} // namespace


//------------------------------------------------------------------------------

#define DECL(K) \
  void calcCoeffs_##K(unsigned half, unsigned qidx, IPoint* pos, FPoint pts[K], float coeffs[K]) { \
    calcCoeffs<K>(half, qidx, pos, pts, coeffs);                         \
  }

extern "C" {
  DECL(2);
  DECL(3);
  DECL(4);
}
