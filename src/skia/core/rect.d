module skia.core.rect;

import std.algorithm;
import std.conv : to;
import std.traits : isIntegral, Unsigned;

alias Size!(int) ISize;
alias Rect!(int) IRect;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

struct Size(T)
{
  T width, height;
  this (T width, T height) {
    this.width = width;
    this.height = height;
  }

  @property bool empty() const {
    return this.width > 0 && this.height > 0;
  }
}


////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

/** Rectangle template
    IRect Integer variant.
*/
struct Rect(T)
{
  enum Corner
  {
    Left,
    Top,
    Right,
    Bottom,
  }
  alias Corner.Left Left;
  alias Corner.Top Top;
  alias Corner.Right Right;
  alias Corner.Bottom Bottom;
  T left, top, right, bottom;
  alias left x;
  alias top  y;

  this(T w, T h) {
    this(Size!T(w, h));
  }

  this(Size!T size) {
    this.size = size;
  }

  this(T left, T top, T right, T bottom) {
    this.set(left, top, right, bottom);
  }

  string toString() {
    return "Rect!"~to!string(typeid(T))
      ~" left: "~to!string(this.left)
      ~" top: "~to!string(this.top)
      ~" right: "~to!string(this.right)
      ~" bottom: "~to!string(this.bottom);
  }

  /** Returns the rectangle's width. This does not check for a valid rectangle (i.e. left <= right)
      so the result may be negative.
  */
  @property T width() const { return right - left; }
  @property void width(T width) {
    this.right = this.left + width;
  }
  
  /** Returns the rectangle's height. This does not check for a valid rectangle (i.e. top <= bottom)
      so the result may be negative.
  */
  @property T height() const { return bottom - top; }
  @property void height(T height) {
    this.bottom = this.top + height;
  }
  
  void set(T left, T top, T right, T bottom) {
    this.left   = left;
    this.top    = top;
    this.right  = right;
    this.bottom = bottom;
  }

  void setXYWH(T x, T y, T width, T height) {
    this.setPos(x, y);
    this.setSize(width, height);
  }

  void setPos(T left, T top) {
    this.right = left + this.width;
    this.left = left;
    this.bottom = top + this.height;
    this.top = top;
  }

  void setSize(T width, T height) {
    this.width = width;
    this.height = height;
  }

  @property Size!T size() const {
    return Size!T(this.width, this.height);
  }

  @property void size(Size!T size) {
    this.setSize(size.width, size.height);
  }

  /** Set the rectangle to (0,0,0,0)
   */
  void setEmpty() {
    this = Rect.init;
  }


  /** Return true if the rectangle's width or height are <= 0
   */
  @property bool empty() const {
    return this.left >= this.right || this.top >= this.bottom;
  }

  /** Offset set the rectangle by adding dx to its left and right,
      and adding dy to its top and bottom.
  */
  void offset(T dx, T dy) {
    this.left   += dx;
    this.top    += dy;
    this.right  += dx;
    this.bottom += dy;
  }

  /*
  void offset(const SkIPoint& delta) {
    this->offset(delta.fX, delta.fY);
  }
  */
  
  /** Inset the rectangle by (dx,dy). If dx is positive, then the sides are moved inwards,
      making the rectangle narrower. If dx is negative, then the sides are moved outwards,
      making the rectangle wider. The same hods true for dy and the top and bottom.
  */
  void inset(T dx, T dy) {
    this.left   += dx;
    this.top    += dy;
    this.right  -= dx;
    this.bottom -= dy;
  }

  /** Returns true if (x,y) is inside the rectangle and the rectangle is not
      empty. The left and top are considered to be inside, while the right
      and bottom are not. Thus for the rectangle (0, 0, 5, 10), the
      points (0,0) and (0,9) are inside, while (-1,0) and (5,9) are not.
  */
  bool contains(bool check=true)(T x, T y) const
    if (isIntegral!T)
  {  
    return (cast(Unsigned!T)(x - left)) <= (right - left) &&
      (cast(Unsigned!T)(y - top)) <= (bottom - top);
  }

  bool contains(bool check=true)(T x, T y) const
    if (!isIntegral!T)
  {  
    return this.left <= x && this.right >= x 
      && this.top <= y && this.bottom >= y;
  }

  /** Returns true if the 4 specified sides of a rectangle are inside or equal to this rectangle.
      If either rectangle is empty, contains() returns false.
  */
  bool contains(bool check=true)(T left, T top, T right, T bottom) const {
    return this.contains!check(Rect(left, top, right, bottom));
  }

  /** Returns true if the specified rectangle r is inside or equal to this rectangle.
   */
  bool contains(bool check=true)(in Rect b) const {
    static if(check == true) {
      if (b.empty || this.empty)
	return false;
    }
    else
      assert(b.empty || this.empty);

    return
      this.left <= b.left && this.top <= b.top &&
      this.right >= b.right && this.bottom >= b.bottom;
  }
    
  /** If r intersects this rectangle, return true and set this rectangle to that
      intersection, otherwise return false and do not change this rectangle.
      If either rectangle is empty, do nothing and return false.
  */
  bool intersect(bool check=true)(in Rect b) {
    if (this.intersects!check(b)) {
      this.left   = getSmaller!Left(this, b);
      this.top    = getSmaller!Top(this, b);
      this.right  = getSmaller!Right(this, b);
      this.bottom = getSmaller!Bottom(this, b);
      return true;
    }
    return false;
  }

  /** If the rectangle specified by left,top,right,bottom intersects this rectangle,
      return true and set this rectangle to that intersection,
      otherwise return false and do not change this rectangle.
      If either rectangle is empty, do nothing and return false.
  */
  bool intersect(bool check=true)(T left, T top, T right, T bottom) {
    auto b = Rect(left, top, right, bottom);
    return this.intersect!check(b);
  }

  /** If rectangles a and b intersect, return true and set this rectangle to
      that intersection, otherwise return false and do not change this
      rectangle. If either rectangle is empty, do nothing and return false.
  */
  bool intersect(bool check=true)(in Rect a, in Rect b) {
    Rect copy = a;
    if (copy.intersect!check(b)) {
      this = copy;
      return true;
    }
    return false;
  }
 
  /** Returns true if a and b are not empty, and they intersect
   */
  bool intersects(bool check=true)(in Rect b) const {
    static if(check == true) {
      if (b.empty || this.empty)
	return false;
    }
    else
      assert(b.empty || this.empty);

    return
      this.left < b.right && b.left < this.right &&
      this.top < b.bottom && b.top < this.bottom;
  }

  /** Returns true if a and b are not empty, and they intersect
   */
  static bool intersects(bool check=true)(in Rect a, in Rect b) {
    return a.intersects!check(b);
  }
  
  /** Update this rectangle to enclose itself and the specified rectangle.
      If this rectangle is empty, just set it to the specified rectangle. If the specified
      rectangle is empty, do nothing.
  */
  void join(T left, T top, T right, T bottom) {
    this.join(Rect(left, top, right, bottom));
  }

  /** Update this rectangle to enclose itself and the specified rectangle.
      If this rectangle is empty, just set it to the specified rectangle. If the specified
      rectangle is empty, do nothing.
  */
  void join(in Rect b) {
    if (b.empty)
      return;
    
    if (this.empty)
      this = b;
    else
    {
      this.left   = getBigger!Left(this, b);
      this.top    = getBigger!Top(this, b);
      this.right  = getBigger!Right(this, b);
      this.bottom = getBigger!Bottom(this, b);
    }
  }
  
  /** Swap top/bottom or left/right if there are flipped.
      This can be called if the edges are computed separately,
      and may have crossed over each other.
      When this returns, left <= right && top <= bottom
  */
  void sort()
  {
    if (left > right)
        swap(left, right);
    if (top > bottom)
        swap(left, right);
  }

  private static T getBigger(Corner c)(in Rect a, in Rect b) {
    static if (c == Left)
      return min(a.left, b.left);
    else if (c == Right)
      return max(a.right, b.right);
    else if (c == Top)
      return min(a.top, b.top);
    else if (c == Bottom)
      return max(a.bottom, b.bottom);
  }
  
  private static T getSmaller(Corner c)(in Rect a, in Rect b) {
    static if (c == Left)
      return max(a.left, b.left);
    else if (c == Right)
      return min(a.right, b.right);
    else if (c == Top)
      return max(a.top, b.top);
    else if (c == Bottom)
      return min(a.bottom, b.bottom);
  }
  
version(NULL)
{
    /* Set the dst integer rectangle by rounding this rectangle's coordinates
        to their nearest integer values.
    */
    void round(Rect* dst) const {
      assert(dst);
      dst.set(SkScalarRound(left), SkScalarRound(top), SkScalarRound(right), SkScalarRound(bottom));
    }

    /** Set the dst integer rectangle by rounding "out" this rectangle, choosing the floor of top and left,
        and the ceiling of right and bototm.
    */
    void roundOut(Rect* dst) const {
        assert(dst);
        dst.set(SkScalarFloor(left), SkScalarFloor(top), SkScalarCeil(right), SkScalarCeil(bottom));
    }
}
};

version(unittest) import std.stdio : writeln;
unittest
{
  IRect r1 = IRect(0,1,2,3);
  assert(r1.width == 2);
  assert(r1.height == 2);

  r1.setSize(20, 20);
  assert(r1.width == 20);
  assert(r1.height == 20);
  assert(r1.left == 0);
  assert(r1.top == 1);
  assert(r1.right == 20);
  assert(r1.bottom == 21);
  r1.setPos(0, 0);
  assert(r1.width == 20);
  assert(r1.height == 20);

  IRect r2 = IRect(20, 20);
  assert(r1 == r2);
  assert(r1.intersects(r2));
  assert(r1.intersect(r2));
  assert(r1 == r2);

  r2.setPos(10, 0);
  r2.setSize(10, 20);
  assert(r1.intersects(r2));
  assert(r1.intersect(r2));
  assert(r1 == r2);
  assert(r1 == IRect(10, 0, 20, 20));

  r2.setSize(20, 40);
  r2.setPos(-10, 10);
  r1.join(r2);
  assert(r1 == IRect(-10, 0, 20, 50));
  assert(r1.contains(-10, 50));
  assert(r1.contains(0, 0));
}
