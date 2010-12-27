module skia.core.point;

private {
  import std.math;
  import std.conv : to;
  import std.traits : isSigned, isAssignable, isFloatingPoint;
  debug import std.stdio : writeln, writefln;

  import skia.core.size;
}

alias Point!(int) IPoint;
alias Point!(float) FPoint;

/**
 * Template deducing function.
 */
Point!T point(T)(T x, T y) {
  return Point!T(x, y);
}

/**
 * Convenience function to obtain a null initialized FPoint.  FPoint()
 * is initialized with nan.
 */
FPoint fPoint()() {
  return FPoint(0, 0);
}
FPoint fPoint(T)(Point!T pt) {
  return FPoint(pt.x, pt.y);
}

struct Point (T)
{
  @property T x;
  @property T y;

  this (T x, T y) {
    static if (isFloatingPoint!T) {
      //assert(isNormal(x)&& isNormal(y));
    }
    this.x = x;
    this.y = y;
  }

  @property string toString() const {
    return "Point!"~to!string(typeid(T))
      ~" x: "~to!string(this.x)
      ~" y: "~to!string(this.y);
  }
  /** Set the point's X and Y coordinates */
  void set(T x, T y) { this.x = x; this.y = y; }

  /** Set the point's X and Y coordinates by automatically promoting (x,y) to
   *  SkScalar values.
   */
  void iset(uint x, uint y) {
    this.x = to!T(x);
    this.y = to!T(y);
  }

  /** Return the euclidian distance from (0,0) to the point
   */
  @property real length()
  {
    return std.math.sqrt(x * x + y * y);
  }

  /** Set the point (vector) to be unit-length in the same direction as it
   *  currently is, and return its old length. If the old length is
   *  degenerately small (nearly zero), do nothing and return false, otherwise
   *  return true.
   */
  void normalize() {
    return this.setLength(1);
  }

  /** Set the point (vector) to be unit-length in the same direction as the
   *  x,y params. If the vector (x,y) has a degenerate length (i.e. nearly 0)
   *  then return false and do nothing, otherwise return true.
   */
  void setNormalize(Point!T pt) {
    return setNormalize(pt.x, pt.y);
  }
  void setNormalize(T x, T y) {
    this.set(x, y);
    return this.normalize();
  }

  /** Scale the point (vector) to have the specified length, and return that
   *  length. If the original length is degenerately small (nearly zero),
   *   do nothing and return false, otherwise return true.
   */
  void setLength(T length) {
    assert(this.length > 10 * float.epsilon, to!string(this));
    auto scale = length / this.length;
    this.x = to!T(scale * this.x);
    this.y = to!T(scale * this.y);
  }

  /** Set the point (vector) to have the specified length in the same
   *  direction as (x,y). If the vector (x,y) has a degenerate length
   *  (i.e. nearly 0) then return false and do nothing, otherwise return true.
   */
  void setLength(T x, T y, T length) {
    this.set(x, y);
    return this.setLength(length);
  }

  /** Scale the point's coordinates by scale, writing the answer into dst.
   *  It is legal for dst == this.
   */
  void scale(T2)(T2 scale, ref Point!T dst) const
  {
    dst = this;
    dst.scale(scale);
  }

  /** Scale the point's coordinates by scale, writing the answer back into
      the point.
  */
  void scale(T2)(T2 scale) {
    this.set(to!T(this.x * scale), to!T(this.y * scale));
  }


  /** static if (isSigned!T) */
  static if (isSigned!T)
  {

  /** Rotate the point clockwise by 90 degrees, writing the answer into dst.
   *  It is legal for dst == this.
   */
  void rotateCW(out Point dst) const {
    dst = this;
    dst.rotateCW();
  }

  /** Rotate the point clockwise by 90 degrees, writing the answer back into
   *  the point.
   */
  void rotateCW() {
    this.set(-this.y, this.x);
  }

  /** Rotate the point counter-clockwise by 90 degrees, writing the answer
   *  into dst. It is legal for dst == this.
   */
  void rotateCCW(out Point dst) const {
    dst = this;
    dst.rotateCCW();
  }

  /** Rotate the point counter-clockwise by 90 degrees, writing the answer
   *  back into the point.
   */
  void rotateCCW() {
    this.set(this.y, -this.x);
  }

  /** Negate the point's coordinates
   */
  void negate() {
    this = -this;
  }

  Point opUnary(string op)() if (op == "-") {
    return Point(-x, -y);
  }

  } /** static if (isSigned!T) */


  /** Returns a new point whose coordinates are the difference/sum
   * between a's and b's (a -/+ b).
   */
  Point opBinary(string op)(Point rhs) const
    if (op == "-" || op == "+" || op == "*" || op == "/")
  {
    T resx = mixin("this.x" ~ op ~ "rhs.x");
    T resy = mixin("this.y" ~ op ~ "rhs.y");
    return Point(resx, resy);
  }

  /** Returns a new point whose coordinates is multiplied/divided by
   *  the scalar.
   */
  Point opBinary(string op)(T val)
    if (op == "*" || op == "/")
  {
    T resx = mixin("this.x" ~ op ~ "val");
    T resy = mixin("this.y" ~ op ~ "val");
    return Point(resx, resy);
  }


  Point!T opBinary(string op)(Size!T size) const
    if (op == "-" || op == "+")
  {
    T resx = mixin("this.x" ~ op ~ "size.width");
    T resy = mixin("this.y" ~ op ~ "size.height");
    return point(resx, resy);
  }



  /** Add/Subtract v's coordinates to the point's
   */
  ref Point opOpAssign(string op)(Point rhs)
  //if (op == "-" || op == "+")
 {
    mixin("this.x" ~ op ~ "=rhs.x;");
    mixin("this.y" ~ op ~ "=rhs.y;");
    return this;
  }

  ref Point opOpAssign(string op)(T val)
  //if (op == "*" || op == "/")
 {
    mixin("this.x" ~ op ~ "=val;");
    mixin("this.y" ~ op ~ "=val;");
    return this;
  }

  /** Returns true if the point's coordinates equal (x,y)
   */
  bool equals(T x, T y) const
  { return this.x == x && this.y == y; }

  bool opEquals(ref const Point rhs) const {
    return this.x == rhs.x && this.y == rhs.y;
  }

};

/** Returns the euclidian distance between a and b
 */
T distance(T)(Point!T a, Point!T b) {
  Point!T tmp = a - b;
  return tmp.length();
}

/** Returns the dot product of a and b, treating them as 2D vectors
 */
T dotProduct(T)(Point!T a, Point!T b) {
  return a.x * b.x + a.y * b.y;
}

/** Returns the cross product of a and b, treating them as 2D vectors
 */
T crossProduct(T)(Point!T a, Point!T b) {
  return a.x * b.y - a.y * b.x;
}


unittest
{
  testPointCoordinates!uint();
  testVectorLength!uint();

  testPointCoordinates!int();
  testVectorLength!int();
  testVectorDirection!int();
  testVectorOps!int();
}

void testPointCoordinates(T)() {
  auto p1 = Point!T(10, 20);
  assert(p1.x == 10);
  assert(p1.y == 20);
  p1 = Point!T(5, 5);
  assert(p1.x == 5);
  assert(p1.y == 5);
  p1.set(4, 3);
  assert(p1.x == 4);
  assert(p1.y == 3);
  p1.set(3, 4);
  assert(p1.x == 3);
  assert(p1.y == 4);
  p1.iset(2, 7);
  assert(p1.x == 2);
  assert(p1.y == 7);

  auto p2 = Point!T(5, 5);
  p1 = p2;
  assert(p1.x == 5);
  assert(p1.y == 5);

  auto p3 = p1 + p2;
  assert(p3.x == 10);
  assert(p3.y == 10);
  p3 += p1;
  assert(p3.x == 15);
  assert(p3.y == 15);
}

void testVectorLength(T)() {
  auto p1 = Point!T(3, 4);
  auto p2 = p1;
  assert(p1.length() == 5);
  assert(p1.length() == p2.length());

  p1.set(5, 5);
  p1.normalize();
  assert(p1.x == to!T(std.math.sqrt(0.5)));
  assert(p1.y == to!T(std.math.sqrt(0.5)));

  p2.setNormalize(5, 5);
  assert(p2.x == to!T(std.math.sqrt(0.5)));
  assert(p2.y == to!T(std.math.sqrt(0.5)));

  p1.set(1, 1);
  p1.setLength(4);
  assert(p1.x == 2);
  assert(p1.y == 2);

  p1.scale(2, p2);
  assert(p2.x == 4);
  assert(p2.y == 4);

  p2.scale(0.5, p2);
  assert(p2.x == 2);
  assert(p2.y == 2);
}

void testVectorDirection(T)() {
  // Rotation works on an y-axis inverted space
  auto p1 = Point!T(2, 1);
  auto p2 = p1;
  p2.rotateCW();
  assert(p2.x == -1);
  assert(p2.y == 2);

  p2 = p1;
  p2.rotateCCW();
  assert(p2.x == 1);
  assert(p2.y == -2);

  // Maybe random test p.rotateCCW().rotateCW() == p

  assert(-p1.x == -2);
  assert(-p1.y == -1);
  assert(p1.x == 2);
  assert(p1.y == 1);
  p1.negate();
  assert(p1.x == -2);
  assert(p1.y == -1);
}

void testVectorOps(T)()
{
  auto p1 = Point!T(2, 1);
  auto p2 = -p1;
  assert(dotProduct(p1, p2) == -5);

  assert(crossProduct(p1, p2) == 0);
  auto pCW = p1;
  pCW.rotateCW();
  auto pCCW = p1;
  pCCW.rotateCCW();
  assert(crossProduct(p1, pCW) == -(crossProduct(p1, pCCW)));
  assert(dotProduct(p1, pCW) == 0);
}
