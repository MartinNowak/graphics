module skia.core.rect;

import std.algorithm;

alias Size!(uint) ISize;
alias Rect!(uint) IRect;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

struct Size(T)
{
  T mWidth, mHeight;
  this (T width, T height) {
    mWidth = width;
    mHeight = height;
  }
}


////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

struct Rect(T)
{
  T mLeft, mTop, mRight, mBottom;
  
  this(T w, T h) {
    this.set(0, 0, w, h);
  }

  this(T left, T top, T right, T bottom) {
    this.set(left, top, right, bottom);
  }

  /** Returns the rectangle's width. This does not check for a valid rectangle (i.e. left <= right)
      so the result may be negative.
  */
  int width() const { return mRight - mLeft; }
  
  /** Returns the rectangle's height. This does not check for a valid rectangle (i.e. top <= bottom)
      so the result may be negative.
  */
  int height() const { return mBottom - mTop; }
  
  void set(T left, T top, T right, T bottom) {
    mLeft   = left;
    mTop    = top;
    mRight  = right;
    mBottom = bottom;
  }

  void setXYWH(T x, T y, T w, T h) {
    set(x, y, x + w, y + h);
  }

  /** Set the rectangle to (0,0,0,0)
   */
  void setEmpty() { this = Rect.init; }


  /** Return true if the rectangle's width or height are <= 0
   */
  bool isEmpty() const {
    return mLeft >= mRight || mTop >= mBottom;
  }

  /** Offset set the rectangle by adding dx to its left and right,
      and adding dy to its top and bottom.
  */
  void offset(T dx, T dy) {
    mLeft   += dx;
    mTop    += dy;
    mRight  += dx;
    mBottom += dy;
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
    mLeft   += dx;
    mTop    += dy;
    mRight  -= dx;
    mBottom -= dy;
  }

  /** Returns true if (x,y) is inside the rectangle and the rectangle is not
      empty. The left and top are considered to be inside, while the right
      and bottom are not. Thus for the rectangle (0, 0, 5, 10), the
      points (0,0) and (0,9) are inside, while (-1,0) and (5,9) are not.
  */
  bool contains(T x, T y) const {
    return (x - mLeft) < (mRight - mLeft) &&
      (y - mTop) < (mBottom - mTop);
  }

  /** Returns true if the 4 specified sides of a rectangle are inside or equal to this rectangle.
      If either rectangle is empty, contains() returns false.
  */
  bool contains(T left, T top, T right, T bottom) const {
    return  left < right && top < bottom && !this.isEmpty() && // check for empties
      mLeft <= left && mTop <= top &&
      mRight >= right && mBottom >= bottom;
  }

  /** Returns true if the specified rectangle r is inside or equal to this rectangle.
   */
  bool contains(const ref Rect r) const {
    return  !r.isEmpty() && !this.isEmpty() &&     // check for empties
      mLeft <= r.mLeft && mTop <= r.mTop &&
      mRight >= r.mRight && mBottom >= r.mBottom;
  }

  /** Return true if this rectangle contains the specified rectangle.
      For speed, this method does not check if either this or the specified
      rectangles are empty, and if either is, its return value is undefined.
      In the debugging build however, we assert that both this and the
      specified rectangles are non-empty.
    */
  bool containsNoEmptyCheck(T left, T top,
			    T right, T bottom) const {
    assert(mLeft < mRight && mTop < mBottom);
    assert(left < right && top < bottom);
    
    return mLeft <= left && mTop <= top &&
      mRight >= right && mBottom >= bottom;
  }
    
  /** If r intersects this rectangle, return true and set this rectangle to that
      intersection, otherwise return false and do not change this rectangle.
      If either rectangle is empty, do nothing and return false.
  */
  bool intersect(const ref Rect r) {
    assert(&r);
    return this.intersect(r.mLeft, r.mTop, r.mRight, r.mBottom);
  }

    /** If rectangles a and b intersect, return true and set this rectangle to
        that intersection, otherwise return false and do not change this
        rectangle. If either rectangle is empty, do nothing and return false.
    */
  bool intersect(const ref Rect a, const ref Rect b) {
    assert(&a && &b);
    
    if (!a.isEmpty() && !b.isEmpty() &&
	a.mLeft < b.mRight && b.mLeft < a.mRight &&
	a.mTop < b.mBottom && b.mTop < a.mBottom) {
      mLeft   = max(a.mLeft,   b.mLeft);
      mTop    = max(a.mTop,    b.mTop);
      mRight  = max(a.mRight,  b.mRight);
      mBottom = max(a.mBottom, b.mBottom);
      return true;
    }
    return false;
  }
  
  /** If rectangles a and b intersect, return true and set this rectangle to
      that intersection, otherwise return false and do not change this
      rectangle. For speed, no check to see if a or b are empty is performed.
      If either is, then the return result is undefined. In the debug build,
      we assert that both rectangles are non-empty.
  */
  bool intersectNoEmptyCheck(const ref Rect a, const ref Rect b) {
    assert(&a && &b);
    assert(!a.isEmpty() && !b.isEmpty());
    
    if (a.mLeft < b.mRight && b.mLeft < a.mRight &&
	a.mTop < b.mBottom && b.mTop < a.mBottom) {
      mLeft   = max(a.mLeft,   b.mLeft);
      mTop    = max(a.mTop,    b.mTop);
      mRight  = min(a.mRight,  b.mRight);
      mBottom = min(a.mBottom, b.mBottom);
      return true;
    }
    return false;
  }

  /** If the rectangle specified by left,top,right,bottom intersects this rectangle,
      return true and set this rectangle to that intersection,
      otherwise return false and do not change this rectangle.
      If either rectangle is empty, do nothing and return false.
  */
  bool intersect(T left, T top, T right, T bottom) {
    if (left < right && top < bottom && !this.isEmpty() &&
	mLeft < right && left < mRight && mTop < bottom && top < mBottom) {
      if (mLeft < left) mLeft = left;
      if (mTop < top) mTop = top;
      if (mRight > right) mRight = right;
      if (mBottom > bottom) mBottom = bottom;
      return true;
    }
    return false;
    }
  
  /** Returns true if a and b are not empty, and they intersect
   */
  static bool Intersects(const Rect a, const ref Rect b) {
    return  !a.isEmpty() && !b.isEmpty() &&
      a.mLeft < b.mRight && b.mLeft < a.mRight &&
      a.mTop < b.mBottom && b.mTop < a.mBottom;
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
  void join(const Rect r) {
    if (r.isEmpty())
      return;
    
    if (this.isEmpty())
      this = r;
    else
    {
      if (r.mLeft < mLeft) mLeft = r.mLeft;
      if (r.mTop < mTop) mTop = r.mTop;
      if (r.mRight > mRight) mRight = r.mRight;
      if (r.mBottom > mBottom) mBottom = r.mBottom;
    }
  }
  
  /** Swap top/bottom or left/right if there are flipped.
      This can be called if the edges are computed separately,
      and may have crossed over each other.
      When this returns, left <= right && top <= bottom
  */
  void sort()
  {
    if (mLeft > mRight)
        swap(mLeft, mRight);
    if (mTop > mBottom)
        swap(mLeft, mRight);
  }
  
version(NULL)
{
    /* Set the dst integer rectangle by rounding this rectangle's coordinates
        to their nearest integer values.
    */
    void round(Rect* dst) const {
        assert(dst);
        dst.set(SkScalarRound(mLeft), SkScalarRound(mTop), SkScalarRound(mRight), SkScalarRound(mBottom));
    }

    /** Set the dst integer rectangle by rounding "out" this rectangle, choosing the floor of top and left,
        and the ceiling of right and bototm.
    */
    void roundOut(Rect* dst) const {
        assert(dst);
        dst.set(SkScalarFloor(mLeft), SkScalarFloor(mTop), SkScalarCeil(mRight), SkScalarCeil(mBottom));
    }
}
};

unittest
{
  IRect r = IRect(0,1,2,3);  
}