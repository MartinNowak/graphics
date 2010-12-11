module skia.core.matrix;

private {
  import std.bitmanip;
  import std.math;

  import skia.core.rect;
  import skia.core.point;
}

struct Matrix {
private:
  float[3][3] mat;
  Type _typeMask;

  enum Type : ubyte {
    Identity = 0x00,
    Translative = (1<<0),
    Scaling = (1<<1),
    Affine = (1<<2),
    Perspective = (1<<3),
    RectStaysRect = (1<<4),
    Unknown = (1<<5),
  }
  enum KAllTransMask = Type.Translative | Type.Scaling
    | Type.Affine | Type.Perspective;
  static assert(KAllTransMask == 0x0F);

  Type computeTypeMask() const {
    Type mask;
    if (mat[2] != [0.0f, 0.0f, 1.0f]) {
      mask |= Type.Perspective;
    }
    if (mat[0][2] != 0.0f || mat[1][2] != 0.0f) {
      mask |= Type.Translative;
    }
    if (mat[0][0] != 1.0f || mat[1][1] != 1.0f) {
      mask |= Type.Scaling;
    }
    if (mat[0][1] != 0.0f || mat[1][0] != 0.0f) {
      mask |= Type.Affine;
    }
    if (!mask & Type.Perspective) {
      //! Collect whether (p)rimary or (s)econdary diagonals are zero
      //! or one.
      auto dp0 = mat[0][0] == 0.0f && mat[1][1] == 0.0f;
      auto dp1 = mat[0][0] != 0.0f && mat[1][1] != 0.0f;
      auto ds0 = mat[0][1] == 0.0f && mat[1][0] == 0.0f;
      auto ds1 = mat[0][1] != 0.0f && mat[1][0] != 0.0f;
      //! No perspective transformation and multiple of 90 degree
      //! rotation.
      if ((dp0 && ds1) || (dp1 && ds0)) {
        mask |= Type.RectStaysRect;
      }
    }
    return mask;
  }

  @property Type typeMask() const {
    if (this._typeMask & Type.Unknown) {
      auto ncThis = cast(Matrix*)&this;
      ncThis._typeMask = this.computeTypeMask();
    }
    return this._typeMask;
  }
  @property byte typeMaskTrans() const {
    return this.typeMask & KAllTransMask;
  }

  void setDirty() {
    this._typeMask |= Type.Unknown;
  }

public:

  @property string toString() const {
    return "Matrix33: " ~ to!string(this.mat);
  }

  @property bool identity() const { return this.typeMask == Type.Identity; }
  @property bool translative() const
  { return (this.typeMask & Type.Translative) != 0; }
  @property bool scaling() const
  { return (this.typeMask & Type.Scaling) != 0; }
  @property bool affine() const
  { return (this.typeMask & Type.Affine) != 0; }
  @property bool perspective() const
  { return (this.typeMask & Type.Perspective) != 0; }
  @property bool rectStaysRect() const
  { return (this.typeMask & Type.RectStaysRect) != 0; }

  static Matrix identityMatrix() {
    Matrix ident;
    ident.mat
      = [[1.0f, 0.0f, 0.0f],
         [0.0f, 1.0f, 0.0f],
         [0.0f, 0.0f, 1.0f]];
    ident._typeMask = Matrix.Type.Identity;
    return ident;
  }

  /****************************************
   * Matrix manipulation functions.
   */
  void reset() {
    auto m = identityMatrix();
    this = m;
  }

  bool invert() {
    // TODO: matrix inversion code missing
    assert(0);
  }

  private real inverseDeterminant() const {
    real det = this.determinant();
    return abs(det) < 1e-5 ? 0.0 : 1.0 / det;
  }

  private real determinant() const {
    if (!this.perspective)
      return this[2][2] * (this[0][0] * this[1][1] - this[0][1] * this[1][0]);
    else
      return this[2][2] * (this[0][0] * this[1][1] - this[0][1] * this[1][0])
        + this[2][1] * (this[0][2] * this[1][0] - this[0][0] * this[1][2])
        + this[2][0] * (this[0][1] * this[1][2] - this[0][1] * this[1][0]);
  }

  void translate(float dx, float dy) {
    this.setDirty();
    this.mat[0][2] += dx;
    this.mat[1][2] += dy;
  }
  void scale(float xs, float ys) {
    this.setDirty();
    this.mat[0][0] *= xs;
    this.mat[1][1] *= ys;
  }

  void setRotate(float deg) {
    this.setDirty();
    auto rad = deg * 2 * PI / 360.0f;
    this.setSinCos(sin(rad), cos(rad));
  }

  void preRotate(float deg) {
    Matrix m;
    m.setRotate(deg);
    this.preConcat(m);
  }
  void postRotate(float deg) {
    Matrix m;
    m.setRotate(deg);
    this.postConcat(m);
  }

  void preConcat(in Matrix mat) {
    this.setDirty();
    this = this * mat;
  }
  void postConcat(in Matrix mat) {
    this.setDirty();
    this = mat * this;
  }

  /****************************************
   * Matrix calculation functions.
   */
  bool mapRect(in FRect src, out FRect dst) const {
    if (this.rectStaysRect) {
      FPoint[] mapped = src.corners;
      this.mapPoints(mapped);
      dst = FRect(mapped[0], mapped[1]);
      dst.sort();
      return true;
    } else {
      FPoint[] quad = src.toQuad();
      this.mapPoints(quad);
      dst.calcBounds(quad);
      return false;
    }
  }

  void mapPoints(ref FPoint[] pts) const {
    auto mapF = this.mapPtsFunc();
    mapF(this, pts);
  }

private:

  void setSinCos(float sinVal, float cosVal) {
    this.mat =
      [[cosVal, -sinVal, 0.0f],
       [sinVal, cosVal , 0.0f],
       [0.0f  , 0.0f   , 1.0f]];
  }
  ref float[3] opIndex(int idx) {
    assert(0 <= idx && idx <= 2);
    return this.mat[idx];
  }
  ref const float[3] opIndex(int idx) const {
    assert(0 <= idx && idx <= 2);
    return this.mat[idx];
  }
  Matrix opBinary(string op)(in Matrix rhs) const
    if (op == "*") {

    if (rhs.identity)
      return this;
    else if (this.identity)
      return rhs;
    else {
      Matrix tmp;
      for(size_t row = 0; row < 3; ++row) {
        for (size_t col = 0; col < 3; ++col) {
          tmp[row][col] =
            this[row][0] * rhs[0][col]
            + this[row][1] * rhs[1][col]
            + this[row][2] * rhs[2][col];
        }
      }
      tmp.setDirty();
      return tmp;
    }
  }

  alias void function(in Matrix, ref FPoint[]) MapPtsFunc;
  MapPtsFunc mapPtsFunc() const {
    switch(this.typeMaskTrans) {
    case 0:
      return &IdentityPts;
    case 1:
      return &TransPts;
    case 2:
      return &ScalePts;
    case 3:
      return &ScaleTransPts;
    case 4, 6:
      return &RotPts;
    case 5, 7:
      return &RotTransPts;
    default:
      return &PerspPts;
    }
  }

  static void IdentityPts(in Matrix, ref FPoint[]) {
    return;
  }

  static void TransPts(in Matrix m, ref FPoint[] pts) {
    assert(m.typeMaskTrans == Type.Translative);

    auto tPt = FPoint(m.mat[0][2], m.mat[1][2]);
    foreach(ref pt; pts) {
      pt += tPt;
    }
  }

  static void ScalePts(in Matrix m, ref FPoint[] pts) {
    assert(m.typeMaskTrans == Type.Translative);

    auto sPt = FPoint(m.mat[0][0], m.mat[1][1]);
    foreach(ref pt; pts) {
      pt *= sPt;
    }
  }

  static void ScaleTransPts(in Matrix m, ref FPoint[] pts) {
    assert(m.typeMaskTrans == (Type.Translative | Type.Scaling));

    auto tPt = FPoint(m.mat[0][2], m.mat[1][2]);
    auto sPt = FPoint(m.mat[0][0], m.mat[1][1]);
    foreach(ref pt; pts) {
      pt *= sPt;
      pt += tPt;
    }
  }

  static void RotPts(in Matrix m, ref FPoint[] pts) {
    assert((m.typeMaskTrans & (Type.Perspective | Type.Translative)) == 0);

    auto sPt = FPoint(m.mat[0][0], m.mat[1][1]);
    //! Skew pt is inverted, so the mul op can be used
    auto kPt = FPoint(m.mat[1][0], m.mat[0][1]);
    foreach(ref pt; pts) {
      pt = pt * sPt + pt * kPt;
    }
  }

  static void RotTransPts(in Matrix m, ref FPoint[] pts) {
    assert((m.typeMaskTrans & Type.Perspective) == 0);

    auto sPt = FPoint(m.mat[0][0], m.mat[1][1]);
    auto tPt = FPoint(m.mat[0][2], m.mat[1][2]);

    foreach(ref pt; pts) {
      auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
      pt = pt * sPt + skewPt + tPt;
    }
  }

  static void PerspPts(in Matrix m, ref FPoint[] pts) {
    assert(m.typeMaskTrans & Type.Perspective);

    auto sPt = FPoint(m[0][0], m[1][1]);
    auto tPt = FPoint(m[0][2], m[1][2]);

    auto p0 = m[2][0];
    auto p1 = m[2][1];
    auto p2 = m[2][2];

    foreach(ref pt; pts) {
      auto z = pt.x * p0 + pt.y * p1 + p2;
      auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
      pt = pt * sPt + skewPt + tPt;
      if (z)
        pt /= z;
    }
  }
}