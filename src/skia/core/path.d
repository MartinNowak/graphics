module skia.core.path;

private {
  import std.algorithm : swap;
  import std.array;
  import std.conv : to;
  import std.math;
  import std.range;
  import std.traits;

  import skia.core.matrix;
  import skia.core.point;
  // only included for splitBezier which belongs to geometry
  import skia.core.edgebuilder;
  import skia.core.rect;
}
//debug=WHITEBOX;
debug import std.stdio : writeln, printf;

// TODO FPoint
struct Path
{
private:
  FPoint[] points;

  // FIXME Verb[] breaks std.array.front in const function
  ubyte[] verbs;

  FRect _bounds;
  bool boundsIsClean;
  FillType _fillType;
  ubyte isConvex;

public:

  enum FillType : ubyte {
    Winding = 0,
    EvenOdd = 1,
    InverseWinding = 2,
    InverseEvenOdd = 3,
  }
  enum Direction {
    CW,
    CCW,
  }
  enum CubicArcFactor = (SQRT2 - 1.0) * 4.0 / 3.0;

  string toString() const {
    string res;
    res ~= "Path, bounds: " ~ to!string(this._bounds) ~ "\n";
    this.forEach((Verb verb, const FPoint[] pts) {
        res ~= verbToString(verb) ~ ": ";
        foreach(FPoint pt; pts) {
          res ~= to!string(pt) ~ ", ";
        }
        res ~= "\n";
      });
    return res;
  }
  static string verbToString(Verb verb) {
    final switch(verb) {
    case Verb.Move: return "Move";
    case Verb.Line: return "Line";
    case Verb.Quad: return "Quad";
    case Verb.Cubic: return "Cubic";
    case Verb.Close: return "Close";
    }
  }

  void opAssign(in Path path) {
    this.points = path.points.dup;
    this.verbs = path.verbs.dup;
    this._bounds = path._bounds;
    this.boundsIsClean = path.boundsIsClean;
    this._fillType = path._fillType;
    this.isConvex = path.isConvex;
  }

  @property bool empty() const {
    return this.verbs.length == 0
      || this.verbs.length == 1 && this.verbs[0] == Verb.Move;
  }
  @property private void fillType(FillType fillType) {
    return this._fillType = fillType;
  }
  @property FillType fillType() const {
    return this._fillType;
  }
  @property bool inverseFillType() const { return (this.fillType & 2) != 0; }
  void toggleInverseFillType() {
    this._fillType ^= 0x2;
  }

  @property FRect bounds() const {
    if (this.boundsIsClean)
      return this._bounds;
    else {
      auto ncThis = cast(Path*)&this;
      return ncThis.updateBounds();
    }
  }

  @property IRect ibounds() const {
    return this.bounds.round();
  }

  FRect updateBounds() {
    this._bounds = FRect.calcBounds(this.points);
    this.boundsIsClean = true;
    return this._bounds;
  }

  void joinBounds(FRect bounds) {
    if (this.boundsIsClean)
      this._bounds.join(bounds);
  }

  enum Verb : ubyte
  {
    Move = 0,
    Line  = 1,
    Quad  = 2,
    Cubic = 3,
    Close = 4,
  }

  //  alias void delegate(const Verb, const FPoint[]) IterDg;
  void forEach(IterDg)(IterDg dg) const {
    FPoint lastPt;
    FPoint moveTo;

    auto vs = this.verbs.save();
    auto points = this.points.save();

    while (!vs.empty) {
      Verb verb = cast(Verb)vs.front; vs.popFront();

      final switch (verb) {
      case Verb.Move:
	dg(Verb.Move, [points.front]);
        moveTo = points.front;
	lastPt = points.front; points.popFront();
	break;

      case Verb.Line, Verb.Quad, Verb.Cubic:
	dg(verb, [lastPt] ~ take(points, verb));

	auto popped = popFrontN(points, verb - 1);
	assert(popped == verb - 1);
	lastPt = points.front; points.popFront();
	break;

      case Verb.Close:
        if (lastPt != moveTo)
        {
          dg(Verb.Line, [lastPt, moveTo]);
          lastPt = moveTo;
        }
        dg(Verb.Close, []);
      }
    }
  }

  bool isClosedContour() {
    auto r = this.verbs.save();

    if (r.front == Verb.Move)
      r.popFront();

    while(!r.empty) {
      if (r.front == Verb.Move)
        break;
      if (r.front == Verb.Close)
        return true;
      r.popFront();
    }
    return false;
  }

  @property FPoint lastPoint() const {
    return this.points.length == 0 ? FPoint() : this.points[$-1];
  }

  bool lastVerbWas(Verb verb) const {
    return this.verbs.length == 0 ? false : this.verbs[$-1] == verb;
  }

  void ensureStart() {
    if (this.verbs.empty) {
      assert(this.points.length == 0);
      this.points ~= FPoint.init;
      this.verbs ~= Verb.Move;
    }
  }

  void primTo(FPoint[] pts) {
    this.ensureStart();
    this.points ~= pts;
    this.verbs ~= cast(Verb)pts.length;
    this.boundsIsClean = false;
  }

  void rPrimTo(FPoint[] pts) {
    auto lPt = this.lastPoint;
    foreach(ref pt; pts) {
      pt = pt + lPt;
    }
    FPoint pt;
    this.primTo(pts);
  }

  void moveTo(in FPoint pt) {
    if (this.lastVerbWas(Verb.Move)) {
      this.points[$-1] = pt;
    }
    else {
      this.points ~= pt;
      this.verbs ~= Verb.Move;
    }
    this.boundsIsClean = false;
  }
  void rMoveTo(in FPoint pt) {
    this.moveTo(this.lastPoint + pt);
  }

  void lineTo(in FPoint pt) {
    this.primTo([pt]);
  }
  void rLineTo(in FPoint pt) {
    this.rPrimTo([pt]);
  }

  void quadTo(in FPoint pt1, in FPoint pt2) {
    this.primTo([pt1, pt2]);
  }
  void rQuadTo(in FPoint pt1, in FPoint pt2) {
    this.rPrimTo([pt1, pt2]);
  }

  void cubicTo(in FPoint pt1, in FPoint pt2, in FPoint pt3) {
    this.primTo([pt1, pt2, pt3]);
  }
  void rCubicTo(in FPoint pt1, in FPoint pt2, in FPoint pt3) {
    this.rPrimTo([pt1, pt2, pt3]);
  }

  void close() {
    if (this.verbs.length > 0) {
      switch (this.verbs[$-1]) {
      case Verb.Line, Verb.Quad, Verb.Cubic:
        this.verbs ~= Verb.Close;
        break;
      default:
        assert(false);
        break;
      }
    }
  }

  void addRect(in FRect rect, Direction dir = Direction.CW) {
    FPoint[4] quad = rect.toQuad;

    if (dir == Direction.CCW)
      swap(quad[1], quad[3]);

    this.moveTo(quad[0]);
    foreach(pt; quad[1..$]) {
      this.lineTo(pt);
    }
    this.close();
  }

  void addRoundRect(FRect rect, float rx, float ry,
                    Direction dir = Direction.CW) {
    scope(success) this.joinBounds(rect);
    if (rect.empty)
      return;

    auto skip_hori = 2*rx >= rect.width;
    auto skip_vert = 2*ry >= rect.height;
    if (skip_hori && skip_vert)
      return this.addOval(rect, dir);

    if (skip_hori)
      rx = 0.5 * rect.width;
    if (skip_vert)
      ry = 0.5 * rect.height;

    auto sx = rx * CubicArcFactor;
    auto sy = ry * CubicArcFactor;
    this.moveTo(FPoint(rect.right - rx, rect.top));
    if (dir == Direction.CCW) {
      if (!skip_hori)
        this.lineTo(FPoint(rect.left + rx, rect.top));    // top

      this.cubicTo(FPoint(rect.left + rx - sx, rect.top),
                   FPoint(rect.left, rect.top + ry - sy),
                   FPoint(rect.left, rect.top + ry));     // top-left

      if (!skip_vert)
        this.lineTo(FPoint(rect.left, rect.bottom - ry)); // left

      this.cubicTo(FPoint(rect.left, rect.bottom - ry + sy),
                   FPoint(rect.left + rx - sx, rect.bottom),
                   FPoint(rect.left + rx, rect.bottom));         // bot-left
      if (!skip_hori)
        this.lineTo(FPoint(rect.right - rx, rect.bottom));// bottom

      this.cubicTo(FPoint(rect.right - rx + sx, rect.bottom),
                   FPoint(rect.right, rect.bottom - ry + sy),
                   FPoint(rect.right, rect.bottom - ry));      // bot-right
      if (!skip_vert)
        this.lineTo(FPoint(rect.right, rect.top + ry));

      this.cubicTo(FPoint(rect.right, rect.top + ry - sy),
                   FPoint(rect.right - rx + sx, rect.top),
                   FPoint(rect.right - rx, rect.top));         // top-right
    } else {
      this.cubicTo(FPoint(rect.right - rx + sx, rect.top),
                   FPoint(rect.right, rect.top + ry - sy),
                   FPoint(rect.right, rect.top + ry));         // top-right

      if (!skip_vert)
        this.lineTo(FPoint(rect.right, rect.bottom - ry));

      this.cubicTo(FPoint(rect.right, rect.bottom - ry + sy),
                   FPoint(rect.right - rx + sx, rect.bottom),
                   FPoint(rect.right - rx, rect.bottom));      // bot-right

      if (!skip_hori)
        this.lineTo(FPoint(rect.left + rx, rect.bottom));    // bottom

      this.cubicTo(FPoint(rect.left + rx - sx, rect.bottom),
                   FPoint(rect.left, rect.bottom - ry + sy),
                   FPoint(rect.left, rect.bottom - ry));       // bot-left

      if (!skip_vert)
        this.lineTo(FPoint(rect.left, rect.top + ry));       // left

      this.cubicTo(FPoint(rect.left, rect.top + ry - sy),
                   FPoint(rect.left + rx - sx, rect.top),
                   FPoint(rect.left + rx, rect.top));          // top-left

      if (!skip_hori)
        this.lineTo(FPoint(rect.right - rx, rect.top));      // top
    }
    this.close();
  }

  void addOval(FRect oval, Direction dir = Direction.CW) {
    float cx = oval.centerX();
    float cy = oval.centerY();
    float rx = 0.5f * oval.width;
    float ry = 0.5f * oval.height;
    float sx = rx * CubicArcFactor;
    float sy = ry * CubicArcFactor;

    this.moveTo(FPoint(cx + rx, cy));
    if (dir == Direction.CCW) {
      this.cubicTo(FPoint(cx + rx, cy - sy), FPoint(cx + sx, cy - ry),
                   FPoint(cx, cy - ry));
      this.cubicTo(FPoint(cx - sx, cy - ry), FPoint(cx - rx, cy - sy),
                   FPoint(cx - rx, cy));
      this.cubicTo(FPoint(cx - rx, cy + sy), FPoint(cx - sx, cy + ry),
                   FPoint(cx, cy + ry));
      this.cubicTo(FPoint(cx + sx, cy + ry), FPoint(cx + rx, cy + sy),
                   FPoint(cx + rx, cy));
    } else {
      this.cubicTo(FPoint(cx + rx, cy + sy), FPoint(cx + sx, cy + ry),
                   FPoint(cx, cy + ry));
      this.cubicTo(FPoint(cx - sx, cy + ry), FPoint(cx - rx, cy + sy),
                   FPoint(cx - rx, cy));
      this.cubicTo(FPoint(cx - rx, cy - sy), FPoint(cx - sx, cy - ry),
                   FPoint(cx, cy - ry));
      this.cubicTo(FPoint(cx + sx, cy - ry), FPoint(cx + rx, cy - sy),
                   FPoint(cx + rx, cy));
    }
  }

  Path transformed(in Matrix matrix) const {
    Path res;
    res = this;
    res.transform(matrix);
    return res;
  }

  void transform(in Matrix matrix) {
    if (matrix.perspective) {
      Path tmp;
      //! Bezier curves are only invariant to affine transformations.
      void iterate(const Verb verb, const FPoint[] pts) {
        final switch (verb) {
        case Verb.Move:
          tmp.moveTo(pts[0]);
          break;
        case Verb.Line:
          tmp.lineTo(pts[1]);
          break;
        case Verb.Quad:
          subdivide!3(tmp, pts, verb);
          break;
        case Verb.Cubic:
          subdivide!4(tmp, pts, verb);
          break;
        case Verb.Close:
          tmp.close();
          break;
        }
      }
      this.forEach(&iterate);
      matrix.mapPoints(tmp.points);
      this = tmp;
    } else {
      if (matrix.rectStaysRect && this.points.length > 1) {
        FRect mapped;
        matrix.mapRect(this.bounds, mapped);
        this._bounds = mapped;
      } else {
        this.boundsIsClean = false;
      }

      matrix.mapPoints(this.points);
    }
  }
  static void subdivide(int K)(ref Path path, in FPoint[] pts,
                               int subLevel=K) if (K==3 || K==4) {
    if (--subLevel >= 0) {
      auto split = splitBezier!K(pts, 0.5f);
      subdivide!K(path, split[0], subLevel);
      subdivide!K(path, split[1], subLevel);
    } else {
      static if (K == 3)
        path.quadTo(pts[1], pts[2]);
      else
        path.cubicTo(pts[1], pts[2], pts[3]);
    }
  }

  debug(WHITEBOX) private auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }

  unittest
  {
    Path p;
    p.verbs ~= Verb.Move;
    p.points ~= FPoint(1, 1);
    p.verbs ~= Verb.Line;
    p.points ~= FPoint(1, 3);
    p.verbs ~= Verb.Quad;
    p.points ~= [FPoint(2, 4), FPoint(3, 3)];
    p.verbs ~= Verb.Cubic;
    p.points ~= [FPoint(4, 2), FPoint(2, -1), FPoint(0, 0)];
    p.verbs ~= Verb.Close;

    Verb[] verbExp = [Verb.Move, Verb.Line, Verb.Quad, Verb.Cubic, Verb.Line, Verb.Close];
    FPoint[][] ptsExp = [
      [FPoint(1,1)],
      [FPoint(1,1), FPoint(1,3)],
      [FPoint(1,3), FPoint(2,4), FPoint(3,3)],
      [FPoint(3,3), FPoint(4,2), FPoint(2,-1), FPoint(0,0)],
      [FPoint(0,0), FPoint(1,1)],
      [],
			 ];

    void iterate(const Verb verb, const FPoint[] pts) {
      assert(verb == verbExp[0]);
      assert(pts == ptsExp[0]);
      verbExp.popFront();
      ptsExp.popFront();
    }
    p.forEach(&iterate);

    assert(p.isClosedContour() == true);
    assert(p.empty() == false);
  }

}
