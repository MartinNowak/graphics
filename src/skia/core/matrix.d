module skia.core.matrix;

private {
  import std.bitmanip;
  import std.conv : to;
  import std.math;

  import guip.rect;
  import guip.point;
  debug import std.stdio : writefln;
  import Detail = skia.core.matrix_detail._;
}

// TODO: move matrix implementation into matrix_detail and leave an
// interface here.
struct Matrix {
private:
  Detail.MatrixStorage data;
  ubyte _typeMask;

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

  ubyte computeTypeMask() const {
    ubyte mask;
    if (this[2][0..3] != [0.0f, 0.0f, 1.0f]) {
      mask |= Type.Perspective;
    }
    if (this[0][2] != 0.0f || this[1][2] != 0.0f) {
      mask |= Type.Translative;
    }
    if (this[0][0] != 1.0f || this[1][1] != 1.0f) {
      mask |= Type.Scaling;
    }
    if (this[0][1] != 0.0f || this[1][0] != 0.0f) {
      mask |= Type.Affine;
    }
    if (!(mask & Type.Perspective)) {
      //! Collect whether (p)rimary or (s)econdary diagonals are zero
      //! or one.
      auto dp0 = this[0][0] == 0.0f && this[1][1] == 0.0f;
      auto dp1 = this[0][0] != 0.0f && this[1][1] != 0.0f;
      auto ds0 = this[0][1] == 0.0f && this[1][0] == 0.0f;
      auto ds1 = this[0][1] != 0.0f && this[1][0] != 0.0f;
      //! No perspective transformation and multiple of 90 degree
      //! rotation.
      if ((dp0 && ds1) || (dp1 && ds0)) {
        mask |= Type.RectStaysRect;
      }
    }
    return mask;
  }

  @property ubyte typeMask() const {
    if (this._typeMask & Type.Unknown) {
      auto ncThis = cast(Matrix*)&this;
      ncThis._typeMask = this.computeTypeMask();
    }
    return this._typeMask;
  }
  // TODO: this should only have package visibility, but the matrix
  // impl needed to be moved.
  public @property ubyte typeMaskTrans() const {
    return this.typeMask & KAllTransMask;
  }

  void setDirty() {
    this._typeMask |= Type.Unknown;
  }

public:

  this(in Detail.MatrixStorage data) {
    this.data = data;
    this.setDirty();
  }
  @property string toString() const {
    return "Matrix33: " ~ to!string(this.data);
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

  public ref typeof(this.data[0]) opIndex(size_t idx) {
    assert(0 <= idx && idx <= 2);
    return this.data[idx];
  }
  public ref typeof(this.data[0]) opIndex(size_t idx) const {
    assert(0 <= idx && idx <= 2);
    return this.data[idx];
  }

  static Matrix identityMatrix() {
    Matrix id;
    id.data[0][0] = 1.0f; id.data[0][1] = 0.0f; id.data[0][2] = 0.0f;
    id.data[1][0] = 0.0f; id.data[1][1] = 1.0f; id.data[1][2] = 0.0f;
    id.data[2][0] = 0.0f; id.data[2][1] = 0.0f; id.data[2][2] = 1.0f;
    id._typeMask = Matrix.Type.Identity;
    return id;
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

  void setTranslate(float dx, float dy) {
    this.reset();
    this.setDirty();
    this[0][2] = dx;
    this[1][2] = dy;
  }
  void setRotate(float deg) {
    this.reset();
    this.setDirty();
    auto rad = deg * 2 * PI / 360.0f;
    this.setSinCos(sin(rad), cos(rad));
  }
  void setRotate(float deg, float px, float py) {
    this.reset();
    this.setDirty();
    auto rad = deg * 2 * PI / 360.0f;
    this.setSinCos(sin(rad), cos(rad), px, py);
  }
  void setScale(float xs, float ys) {
    this.reset();
    this.setDirty();
    this[0][0] = xs;
    this[1][1] = ys;
  }
  mixin PrePost!("Translate");
  mixin PrePost!("Rotate");
  mixin PrePost!("Scale");

  private mixin template PrePost(string s)
  {
    mixin(
      "void pre"~s~"(Args...)(Args args) {
         Matrix m;
         m.set"~s~"(args);
         this = m * this;
       }");
    mixin(
      "void post"~s~"(Args...)(Args args) {
         Matrix m;
         m.set"~s~"(args);
         this = this * m;
       }");
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
      dst = FRect.calcBounds(quad);
      return false;
    }
  }

  void mapPoints(FPoint[] pts) const {
    auto mapF = Detail.mapPtsFunc(this.typeMaskTrans);
    mapF(this, pts);
  }

  FPoint mapPoint(FPoint pt) const {
    auto pts = [pt];
    this.mapPoints(pts);
    return pts[0];
  }

private:

  /**
   * Needs to be reset first.
   * [[cosV, -sinV, 0.0f],
   * [sinV, cosV , 0.0f],
   * [0.0f  , 0.0f  , 1.0f]];
   */
  void setSinCos(float sinV, float cosV) {
    this[0][0] = cosV;
    this[0][1] = -sinV;
    this[1][0] = sinV;
    this[1][1] = cosV;
  }
  void setSinCos(float sinV, float cosV, float px, float py) {
    this.setSinCos(sinV, cosV);
    this[0][2] = sinV*py - cosV*px + px;
    this[1][2] = -sinV*px - cosV*py + py;
  }

  Matrix opBinary(string op)(in Matrix rhs) const
    if (op == "*") {

    if (rhs.identity)
      return this;
    else if (this.identity)
      return rhs;
    else {
      auto tmp = Detail.multiplyMatrices(this, rhs);
      tmp.setDirty();
      return tmp;
    }
  }
}
