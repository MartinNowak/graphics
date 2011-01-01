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

/** \class SkRegion

    The SkRegion class encapsulates the geometric region used to specify
    clipping areas for drawing.
*/
struct Region {
  package enum Type {
    Empty,
    Rect,
    Complex,
  }

  ScanLines scanLines;
  Type type;

public:
  this(IRect rect) {
    this = rect;
  }

  this(in Path path, in Region clip) {
    this.setPath(path, clip);
  }

  string toString() const {
    string res;
    res ~= "Region, bounds: " ~ to!string(this.bounds) ~ "\n";
    res ~= "\tType: " ~ typeToString(this.type) ~ "\n";
    res ~= "\tScanLines: " ~ this.scanLines.toString() ~ "\n";
    return res;
  }
  static string typeToString(Type type) {
    /*    final switch(type) {
    case Type.Empty: return "Empty";
    case Type.Rect: return "Rect";
    case Type.Complex: return "Complex";
    }*/
    return "";
  }

  enum Op {
    Difference, /// subtract the op region from the first region
    Intersect,  /// intersect the two regions
    Union,      /// union (inclusive-or) the two regions
    XOR,        /// exclusive-or the two regions
    /** subtract the first region from the op region */
    ReverseDifference,
    Replace,    /// replace the dst region with the op region
  }

  bool op(in Region other, Region.Op op) {
    return false;
  }

  bool op(in Region rgna, in Region rgnb, Region.Op op) {
    if (op == Region.Op.Replace) {
      this = rgnb;
    }

    final switch(op) {
    case Region.Op.Difference:
      if (rgna.empty)
        return this.setEmpty();
      if (rgnb.empty || !IRect.intersects(rgna.bounds, rgnb.bounds))
        return this.setRegion(rgna);
      break;

    case Region.Op.ReverseDifference:
      if (rgnb.empty)
        return this.setEmpty();
      if (rgna.empty || !IRect.intersects(rgnb.bounds, rgna.bounds))
        return this.setRegion(rgnb);
      break;

    case Region.Op.Intersect:
      {
        IRect bounds;
        if (rgna.empty || rgnb.empty
            || !bounds.intersect(rgna.bounds, rgnb.bounds))
          return this.setEmpty();
        if (rgna.isRect() || rgnb.isRect())
          return this.setRect(bounds);
        break;
      }

    case Region.Op.Union:
      if (rgna.empty)
        return this.setRegion(rgnb);
      if (rgnb.empty)
        return this.setRegion(rgna);
      if (rgna.isRect() && rgna.bounds.contains(rgnb.bounds))
        return this.setRegion(rgna);
      if (rgnb.isRect() && rgnb.bounds.contains(rgna.bounds))
        return this.setRegion(rgnb);
      break;

    case Region.Op.XOR:
      if (rgna.empty)
        return this.setRegion(rgnb);
      if (rgnb.empty)
        return this.setRegion(rgna);
      break;

    case Region.Op.Replace:
      // handled above
      assert(0);
    }

    auto oppedScanLines = operate(rgna.scanLines, rgnb.scanLines, op);
    return this.setScanLines(oppedScanLines);
  }

  const(ScanLines) operate(in ScanLines a, in ScanLines b, Region.Op op) {
    return a;
  }

  void opAssign(in IRect rect) {
    if (rect.empty) {
      this.setEmpty();
    }
    else {
      this.scanLines = rect;
      this.type = Type.Rect;
    }
  }

  void opAssign(in Path path) {
    this.setPath(path, Region(path.ibounds));
  }

  void opAssign(in Region region) {
    this.scanLines = region.scanLines;
    this.type = region.type;
  }

  void opAssign(in ScanLines scanLines) {
    this.scanLines = scanLines;
    this.type = scanLines.getType();
  }

  bool setEmpty() {
    this = Region.init;
    return false;
  }

  bool setRegion(in Region other) {
    this = other;
    return this.empty;
  }

  bool setRect(in IRect rect) {
    this = rect;
    return this.empty;
  }

  bool setScanLines(in ScanLines sl) {
    this = sl;
    return this.empty;
  }

  alias empty isEmpty;
  @property bool empty() const {
    return this.type == Type.Empty;
  }

  /** Return true if this region is a single, non-empty rectangle */
  bool isRect() const {
    return this.type == Type.Rect
      && !this.bounds.empty;
  }

  /** Return true if this region consists of more than 1 rectangular area */
  bool isComplex() const { return this.type == Type.Complex; }

  @property IRect bounds() const {
    return this.scanLines.bounds;
  }

  bool quickReject(in IRect rect) const {
    return this.empty || rect.empty ||
      !this.bounds.intersects(rect);
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

    int top = max(path.ibounds.top, clip.bounds.top);
    int bottom = min(path.ibounds.bottom, clip.bounds.bottom);
    if (top >= bottom)
      return this.setEmpty();

    scope auto builder = new RgnBuilder();

    Scan.fillPath(path, clip, builder);
    builder.done();

    this.scanLines = builder.scanLines;
    return this.scanLines.bounds().empty;
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
      auto r = this.scanLines.scanLines;
      assert(r.length > ScanLines.NumRectScanLines);

      IRect ir;
      ir.top    = this.scanLines.top;
      foreach(sl; r) {
        ir.bottom = sl.lastY;
        foreach(sp; sl.spans) {
          ir.left = sp.begin;
          ir.right = sp.end;
          dg(ir);
        }
        ir.top = ir.bottom;
      }
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
  assert(r.bounds == IRect(20, 20));
  r.setEmpty();
  assert(r.isEmpty());
  assert(r.bounds == IRect(0, 0));

  auto path = Path();
  path.toggleInverseFillType();
  auto clip = Region(IRect(100, 100));
  scope auto blitter = new RgnBuilder();

  Scan.fillPath(path, clip, blitter);
  blitter.done();

  r = blitter.scanLines;
  assert(r.isRect());
  assert(r.bounds == IRect(100, 100));
}
