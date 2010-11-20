module skia.core.region;

import skia.core.rect;
import skia.core.point;
import skia.core.path;
import std.conv : to;
import std.array;
import std.range : isRandomAccessRange, isInputRange;
import std.algorithm : min, max;
debug import std.stdio : writeln;

/** \class SkRegion

    The SkRegion class encapsulates the geometric region used to specify
    clipping areas for drawing.
*/
struct Region {
  IRect bounds;
  RunType[] runs;
  Type type;
  alias int RunType;
  enum Type {
    Empty,
    Rect,
  }
  enum RunType RunTypeSentinel = 0x7FFFFFFF;
  enum RectRegionRuns = 6;

public:
  this(IRect rect) {
    this = rect;
  }

  enum Op {
    kDifference, /// subtract the op region from the first region
    kIntersect,  /// intersect the two regions
    kUnion,      /// union (inclusive-or) the two regions
    kXOR,        /// exclusive-or the two regions
    /** subtract the first region from the op region */
    kReverseDifference,
    kReplace,    /// replace the dst region with the op region
  }

  void opAssign(in Region region) {
    this.bounds = region.bounds;
    this.runs = region.runs.dup;
    this.type = region.type;
  }

  void opAssign(in IRect rect) {
    if (rect.empty) {
      this.setEmpty();
    }
    else {
      this.runs.length = 0;
      this.type = Type.Rect;
      this.bounds = rect;
    }
  }

  void opAssign(in Path path) {
  }

  alias empty isEmpty;
  @property bool empty() const {
    return this.type == Type.Empty;
  }

  bool setEmpty() {
    this.bounds.setEmpty();
    this.runs.length = 0;
    this.type = Type.Empty;
    return false;
  }

  /** Return true if this region is a single, non-empty rectangle */
  bool isRect() const {
    return this.type == Type.Rect
      && !this.bounds.empty;
  }

  /** Return true if this region consists of more than 1 rectangular area */
  bool isComplex() const { return !this.isEmpty() && !this.isRect(); }

  /** Return the bounds of this region. If the region is empty, returns an
      empty rectangle.
  */
  IRect getBounds() {
    return this.bounds;
  }

  /** Returns true if the region is non-empty, and if so, sets the specified
      path to the boundary(s) of the region.
  */
  bool getBoundaryPath(out Path path) {
    assert(this.isComplex());
    //    path = this.runs[1..$];
    return true;
  }

  bool setPath(in Path path, in Region clip) {
    if (clip.empty)
      return this.setEmpty();
    if (path.empty)
      if (path.inverseFillType) {
	this = clip;
	return this.empty;
      }
      else
	return this.setEmpty();

    int pathTop, pathBottom;
    int pathTransitions =
      countPathRunTypeValues(path, pathTop, pathBottom);
    int clipTop, clipBottom;
    int clipTransitions =
      clip.countRunTypeValues(clipTop, clipBottom);
    int top = max(pathTop, clipTop);
    int botttom = min(pathBottom, clipBottom);

    if (top > botttom)
      return this.setEmpty();

    
    assert(false);
  }

  invariant() {
    if (this.type == Type.Empty)
      assert(this.bounds.position == IPoint(0,0)
	     && this.bounds.size == ISize(0,0));
    else {
      assert(!this.bounds.empty);
      if (!this.type == Type.Rect) {
	assert(this.runs.length >= RectRegionRuns);
	{
	  IRect bounds;
	  bool isRect = computeRunBounds(this.runs, bounds);
	  assert(!isRect);
	  assert(bounds == this.bounds);
	}

	auto r = this.runs.save();
	assert(r.front == this.bounds.top);
	r.popFront();
	do {
	  validate_line(r, this.bounds);
	} while (r.front < RunTypeSentinel);
	r.popFront();
	assert(r.length == 0);	
      }      
    }
  }

  
private:

  static void BuildRectRuns(in IRect bounds,
		     out RunType runs[])
  {
    runs[] = [bounds.top, bounds.bottom,
	      bounds.left, bounds.right,
	      RunTypeSentinel, RunTypeSentinel];
  }
  
  static bool computeRunBounds(R)(in R range, out IRect bounds)
    if (isRandomAccessRange!R)
  {
    auto r = range.save();
    assert(r.length > 0);
    assert(r.front != RunTypeSentinel);

    if (r.length == RectRegionRuns)
    {
      IRect rect;
      rect.top = r.front; r.popFront();
      assert(rect.top != RunTypeSentinel);
      
      rect.bottom = r.front; r.popFront();
      assert(rect.bottom != RunTypeSentinel);

      rect.left = r.front; r.popFront();
      assert(rect.left != RunTypeSentinel);

      rect.right = r.front; r.popFront();
      assert(rect.right != RunTypeSentinel);

      assert(r.front == RunTypeSentinel);
      r.popFront();
      assert(r.front == RunTypeSentinel);
      r.popFront();
      assert(!rect.empty);

      bounds = rect;
      return true;
    }

    int left = int.max;
    int right = int.min;
    int bottom;
    bounds.top = r.front; r.popFront();
    do {
      bottom = r.front; r.popFront();
      if (r.front < RunTypeSentinel)
      {
	left = min(left, r.front);
	skipScanline(r);
	right = max(right, r[-2]);
      }
      else
	r.popFront();
    } while(r.front < RunTypeSentinel);
    bounds.left = left;
    bounds.right = right;
    bounds.bottom = bottom;
    return false;
  }

  /*  Pass in a scanline, beginning with the Left value of the pair
      (i.e. not the Y beginning)
  */
  static void skipScanline(R)(ref R r)
  if (isInputRange!R)
  {
    while (r.front != RunTypeSentinel)
    {
      auto tmp = r.front; r.popFront();
      assert(tmp < r.front); r.popFront();
    }
    r.popFront(); // set past sentinel
  }

  static validate_line(R)(ref R r, in IRect bounds)
  if (isInputRange!R)
  {
    assert(r.front > bounds.top);
    assert(r.front <= bounds.bottom);
    r.popFront();
    // empty span
    int prevRight = bounds.left - 1;
    while(r.front < RunTypeSentinel)
    {
      int left = r.front; r.popFront();
      int right = r.front; r.popFront();
      assert(left < right);
      assert(left > prevRight);
      assert(right <= bounds.right);
      prevRight = right;
    }
    r.popFront();
  }

////////////////////////////////////////////////////////////////////////////////
// Region Path helpers should go into an own module
////////////////////////////////////////////////////////////////////////////////

  static int countRunTypeValues(out int top, out int bottom) {
    return 0;
  }
  static int countPathRunTypeValues(in Path path, out int top, out int bottom) {
    static const ubyte gPathVerbToInitialLastIndex[] = [
        0,  //  kMove_Verb
        1,  //  kLine_Verb
        2,  //  kQuad_Verb
        3,  //  kCubic_Verb
        0,  //  kClose_Verb
        0   //  kDone_Verb
    ];

    static const ubyte gPathVerbToMaxEdges[] = [
        0,  //  kMove_Verb
        1,  //  kLine_Verb
        2,  //  kQuad_VerbB
        3,  //  kCubic_Verb
        0,  //  kClose_Verb
        0   //  kDone_Verb
    ];

    IPoint pts[4];
    auto iter = Path.Iter(pts);
    Path.Verb verb;
    int maxEdges;
    top = int.max;
    bottom = int.min;

    while ((verb = iter.next(pts)) != Path.Verb.Done) {
      
    }

  }
}

unittest
{
  Region r;
  assert(r.empty);
  r = IRect(20, 20);
  assert(!r.isEmpty());
  assert(r.isRect());
  assert(!r.isComplex());
  assert(r.getBounds() == IRect(20, 20));
  r.setEmpty();
  assert(r.isEmpty());
  assert(r.getBounds() == IRect(0, 0));
}
