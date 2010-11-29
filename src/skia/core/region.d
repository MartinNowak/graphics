module skia.core.region;

private {
  import Scan = skia.core.scan;
  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.regionpath;
  import std.algorithm : min, max;
  import std.array;
  import std.conv : to;
  import std.range : isForwardRange, isInputRange;
  debug import std.stdio : writeln, writefln;
}

/*
 */
package alias int RunType;

/** \class SkRegion

    The SkRegion class encapsulates the geometric region used to specify
    clipping areas for drawing.
*/
struct Region {
  IRect bounds;
  RunType[] runs;
  Type type;

  enum Type {
    Empty = 0,
    Rect,
    Complex,
  }
  enum RunType RunTypeSentinel = 0x7FFFFFFF;
  enum RectRegionRuns = 6;

public:
  this(IRect rect) {
    this = rect;
  }

  string toString() const {
    string res;
    res ~= "Region, bounds: " ~ to!string(this.bounds) ~ "\n";
    res ~= "\tType: " ~ typeToString(this.type) ~ "\n";
    res ~= "\tnum runs: " ~ to!string(this.runs.length) ~ "\n";
    return res;
  }
  static string typeToString(Type type) {
    final switch(type) {
    case Type.Empty: return "Empty";
    case Type.Rect: return "Rect";
    case Type.Complex: return "Complex";
    }
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

  void opAssign(in RunType[] runs) {
    this.runs = runs.dup;
    Region.computeRunBounds(this.runs, this.bounds);
    this.type = Type.Complex;
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
    this.setPath(path, Region(path.bounds));
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
  bool isComplex() const { return this.type == Type.Complex; }

  /** Return the bounds of this region. If the region is empty, returns an
      empty rectangle.
  */
  IRect getBounds() const {
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

  /** Sets the region to the clipped path and returns if the resulting
   *  region is empty.
   */
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
    int bottom = min(pathBottom, clipBottom);

    if (top >= bottom)
      return this.setEmpty();

    auto maxHeight = bottom - top;
    auto maxTransitions = max(pathTransitions, clipTransitions);
    assert(maxHeight > 0);
    //    scope auto builder = new RgnBuilder(maxHeight, maxTransitions);
    scope auto builder = new RgnBuilder();

    Scan.fillPath(path, clip, builder);
    builder.done();

    int count = builder.computeRunCount();
    if (count == 0) {
      this.setEmpty();
    }
    else if (count == RectRegionRuns) {
      this = builder.getRect();
    }
    else {
      this = builder.getRuns();
    }
    return false;
  }

  alias void delegate(in IRect rect) IterDg;
  void forEach(IterDg dg) const {
    if (this.empty) {
      return;
    }

    if (this.isRect()) {
      dg(this.bounds);
      return;
    }
    else {
      auto r = this.runs.save();
      IRect ir;
      ir.top    = r.front; r.popFront;
      ir.bottom = r.front; r.popFront;
      ir.left   = r.front; r.popFront;
      ir.right  = r.front; r.popFront;

      while (r.front < RunTypeSentinel) {
        dg(ir);
        auto prevFront = r.front; r.popFront;

        if (r.front != RunTypeSentinel) {
          ir.bottom = prevFront;
        }
        else { // empty line
          ir.top = prevFront;
          r.popFront;
          ir.bottom = r.front;
        }

        assert(r.front < RunTypeSentinel);
        ir.left = r.front; r.popFront;
        ir.right = r.front; r.popFront;
      }
    }
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
	  bool isRect = Region.computeRunBounds(this.runs, bounds);
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
    if (isForwardRange!R)
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
        // FIXME array access must be unsigned
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
  static uint skipScanline(R)(ref R r)
  if (isInputRange!R)
  {
    uint res = 0;
    while (r.front != RunTypeSentinel)
    {
      auto tmp = r.front; r.popFront();
      assert(tmp < r.front); r.popFront();
    }
    r.popFront(); // set past sentinel
    return res;
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

  int countRunTypeValues(out int top, out int bottom) const {
    int maxT;

    if (this.isRect())
      maxT = 2;
    else {
      auto runs = this.runs.save();
      runs.popFront();
      do {
        runs.popFront();
        maxT = max(maxT, skipScanline(runs));
      } while(runs.front < RunTypeSentinel);
    }
    top = this.bounds.top;
    bottom = this.bounds.bottom;
    return maxT;
  }

  static int countPathRunTypeValues(
    in Path path,
    out int top,
    out int bottom) {
    uint maxEdges;
    int locTop = int.max;
    int locBottom = int.min;

    void findBounds(const Path.Verb verb, const IPoint[] pts) {
      maxEdges += Path.verbToMaxEdges(verb);
      foreach(pt; pts) {
        locTop = min(locTop, pt.y);
        locBottom = max(locBottom, pt.y);
      }
    }
    path.forEach(&findBounds);

    assert(top <= bottom);
    top = locTop;
    bottom = locBottom;
    return maxEdges;
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

  auto path = Path();
  path.toggleInverseFillType();
  auto clip = Region(IRect(100, 100));

  // some copy paster code as opAssign(Path) is
  // not fully working now.
  scope auto blitter = new RgnBuilder();

  Scan.fillPath(path, clip, blitter);
  blitter.done();
  int count = blitter.computeRunCount();
  if (count == 0) {
    r.setEmpty();
  }
  else if (count == Region.RectRegionRuns) {
    r = blitter.getRect();
  }
  else {
    r = blitter.getRuns();
  }
  assert(r.isRect());
  assert(r.getBounds() == IRect(100, 100));
}
