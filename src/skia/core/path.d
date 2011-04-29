module skia.core.path;

private {
  import std.algorithm : swap;
  import std.array;
  import std.conv : to;
  import std.math;
  import std.numeric : FPTemporary;
  import std.range;
  import std.traits;

  import skia.core.matrix;
  import guip.point;
  import skia.core.edge_detail.algo : splitBezier;
  import skia.core.path_detail._;
  import guip.rect;
  import skia.math.fixed_ary;
}

public import skia.core.path_detail._ : QuadCubicFlattener;

//debug=WHITEBOX;
debug import std.stdio : writeln, printf;
version=CUBIC_ARC;

// TODO: FPoint -> Point!T
struct Path
{
  Appender!(FPoint[]) _points;
  Appender!(Verb[]) _verbs;

private:
  FRect _bounds;
  bool boundsIsClean;
  FillType _fillType;
  ubyte isConvex;

public:

  void reset() {
    this._points.clear();
    this._verbs.clear();
    this.boundsIsClean = false;
    this._bounds = FRect();
  }
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
    this.forEach((Verb verb, in FPoint[] pts) {
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

  this(Path path) {
    this = path;
  }
  ref Path opAssign(in Path path) {
    this._points = appender(path.points.dup);
    this._verbs = appender(path.verbs.dup);
    this._bounds = path._bounds;
    this.boundsIsClean = path.boundsIsClean;
    this._fillType = path._fillType;
    this.isConvex = path.isConvex;
    return this;
  }

  @property bool empty() const {
    return this.verbs.length == 0
      || this.verbs.length == 1 && this.verbs[0] == Verb.Move;
  }
  @property void fillType(FillType fillType) {
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
    return this.bounds.roundOut();
  }

  FRect updateBounds() {
    this._bounds = this.points.length > 0
      ? FRect.calcBounds(this.points)
      : FRect.emptyRect();
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

  alias void delegate(Verb, in FPoint[]) IterDg;
  void forEach(Flattener=NoopFlattener)(IterDg dg) const {
    if (this.empty)
      return;

    FPoint lastPt;
    FPoint moveTo;

    auto vs = this.verbs.save;
    auto points = this.points.save;
    auto flattener = Flattener(dg);

    while (!vs.empty) {
      Verb verb = cast(Verb)vs.front; vs.popFront();

      final switch (verb) {
      case Verb.Move:
	flattener.call(Verb.Move, [points.front]);
        moveTo = points.front;
	lastPt = points.front; points.popFront;
	break;

      case Verb.Line, Verb.Quad, Verb.Cubic:
	flattener.call(verb, [lastPt] ~ take(points, verb));
	auto popped = popFrontN(points, verb - 1);
 	assert(popped == verb - 1);
	lastPt = points.front; points.popFront;
	break;

      case Verb.Close:
        if (lastPt != moveTo)
        {
          flattener.call(Verb.Line, [lastPt, moveTo]);
          lastPt = moveTo;
        }
        flattener.call(Verb.Close, []);
      }
    }
  }

  bool isClosedContour() {
    auto r = this.verbs.save;

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

  @property typeof(retro!(const(FPoint[]))([])) pointsRetro() const {
    return this.points.retro;
  }
  @property const(FPoint[]) points() const {
    return (cast(Path)this)._points.data.save;
  }

  @property FPoint lastPoint() const {
    return this.pointsRetro[0];
  }

  @property Verb[] verbs() const {
    return (cast(Path)this)._verbs.data.save;
  }

  bool lastVerbWas(Verb verb) const {
    return this.verbs.length == 0 ? false : this.verbs[$-1] == verb;
  }

  void ensureStart() {
    if (this.verbs.empty) {
      assert(this.points.length == 0);
      this._points.put(fPoint());
      this._verbs.put(Verb.Move);
    }
  }

  void primTo(R)(R pts) {
    static assert(isInputRange!R);
    this.ensureStart();
    this._points.put(pts);
    this._verbs.put(cast(Verb)walkLength(pts));
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
      this._points.data[$-1] = pt;
    }
    else {
      this._points.put(pt);
      this._verbs.put(Verb.Move);
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
        this._verbs.put(Verb.Close);
        break;
      default:
        assert(false);
        break;
      }
    }
  }

  void addPath(in Path path) {
    this._verbs.put(path.verbs);
    this._points.put(path.points);
    this.boundsIsClean = false;
  }

  void reversePathTo(in Path path) {
    if (path.empty)
      return;

    debug auto initialLength= this.verbs.length;
    this._verbs.reserve(this.verbs.length + path.verbs.length);
    this._points.reserve(this.points.length + path.points.length);

    //! skip initial moveTo
    assert(this.verbs[0] == Verb.Move);
    auto vs = path.verbs[1..$].retro;
    auto rpts = path.pointsRetro;
    rpts.popFront;

    while (!vs.empty) {
      auto verb = vs.front;
      switch (verb) {
      case Verb.Line: .. case Verb.Cubic:
        this.primTo(take(rpts, verb));
        popFrontN(rpts, verb);
        break;
      default:
        assert(0, "bad verb in reversePathTo: " ~ to!string(path.verbs));
        break;
      }
      vs.popFront;
    }
    assert(rpts.empty);
  }

  unittest {
    Path rev;
    rev.moveTo(FPoint(100, 100));
    rev.quadTo(FPoint(40,60), FPoint(0, 0));
    Path path;
    path.moveTo(FPoint(0, 0));
    path.reversePathTo(rev);
    assert(path.verbs == [Verb.Move, Verb.Quad], to!string(path.verbs));
    assert(path.points == [FPoint(0, 0), FPoint(40, 60), FPoint(100, 100)], to!string(path.points));
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
    auto cx = oval.centerX;
    auto cy = oval.centerY;
    auto rx = 0.5 * oval.width;
    auto ry = 0.5 * oval.height;

  version(CUBIC_ARC) {
    auto sx = rx * CubicArcFactor;
    auto sy = ry * CubicArcFactor;

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
  } else {
    enum TAN_PI_8 = tan(PI_4 * 0.5);
    auto sx = rx * TAN_PI_8;
    auto sy = ry * TAN_PI_8;
    auto mx = rx * SQRT1_2;
    auto my = ry * SQRT1_2;
    const L = oval.left;
    const T = oval.top;
    const R = oval.right;
    const B = oval.bottom;

    this.moveTo(FPoint(R, cy));
    if (dir == Direction.CCW) {
      this.quadTo(FPoint(R,  cy - sy), FPoint(cx + mx, cy - my));
      this.quadTo(FPoint(cx + sx,  T), FPoint(cx, T));
      this.quadTo(FPoint(cx - sx,  T), FPoint(cx - mx, cy - my));
      this.quadTo(FPoint(L,  cy - sy), FPoint(L, cy));
      this.quadTo(FPoint(L,  cy + sy), FPoint(cx - mx, cy + my));
      this.quadTo(FPoint(cx - sx,  B), FPoint(cx, B));
      this.quadTo(FPoint(cx + sx,  B), FPoint(cx + mx, cy + my));
      this.quadTo(FPoint(R,  cy + sy), FPoint(R, cy));
    } else {
      this.quadTo(FPoint(R,  cy + sy), FPoint(cx + mx, cy + my));
      this.quadTo(FPoint(cx + sx,  B), FPoint(cx, B));
      this.quadTo(FPoint(cx - sx,  B), FPoint(cx - mx, cy + my));
      this.quadTo(FPoint(L,  cy + sy), FPoint(L, cy));
      this.quadTo(FPoint(L,  cy - sy), FPoint(cx - mx, cy - my));
      this.quadTo(FPoint(cx - sx,  T), FPoint(cx, T));
      this.quadTo(FPoint(cx + sx,  T), FPoint(cx + mx, cy - my));
      this.quadTo(FPoint(R,  cy - sy), FPoint(R, cy));
    }
  } // version(CUBIC_ARC)

    this.close();
  }

  void arcTo(FPoint center, FPoint endPt, Direction dir = Direction.CW) {
    this.ensureStart();
    auto startPt = this.lastPoint;
    FVector start = startPt - center;
    FVector end = endPt - center;
    FPTemporary!float radius = (start.length + end.length) * 0.5;
    FPTemporary!float startAngle = atan2(start.y, start.x);
    FPTemporary!float endAngle = atan2(end.y, end.x);
    FPTemporary!float sweepAngle = endAngle - startAngle;
    if (sweepAngle < 0)
      sweepAngle += 2*PI;
    if (dir == Direction.CCW)
      sweepAngle -= 2*PI;

    assert(abs(sweepAngle) <= 2*PI);
    FPTemporary!float midAngle = startAngle + 0.5 * sweepAngle;
    auto middle = FVector(expi(midAngle));

    if (abs(sweepAngle) > PI_4) {
      middle.setLength(radius);
      FPoint middlePt = center + middle;
      this.arcTo(center, middlePt, dir);
      this.arcTo(center, endPt, dir);
    } else {
      //! based upon a deltoid, calculate length of the long axis.
      FPTemporary!float hc = 0.5 * (startPt - endPt).length;
      FPTemporary!float b = hc / sin(0.5 * (PI - abs(sweepAngle)));
      FPTemporary!float longAxis = sqrt(radius * radius + b * b);
      middle.setLength(longAxis);
      this.quadTo(center + middle, endPt);
    }
  }

  void addArc(FPoint center, FPoint startPt, FPoint endPt, Direction dir = Direction.CW) {
    this.moveTo(center);
    this.lineTo(startPt);
    this.arcTo(center, endPt, dir);
    this.lineTo(center);
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
      void iterate(Verb verb, in FPoint[] pts) {
        final switch (verb) {
        case Verb.Move:
          tmp.moveTo(pts[0]);
          break;
        case Verb.Line:
          tmp.lineTo(pts[1]);
          break;
        case Verb.Quad:
          subdivide(tmp, fixedAry!3(pts), verb);
          break;
        case Verb.Cubic:
          subdivide(tmp, fixedAry!4(pts), verb);
          break;
        case Verb.Close:
          tmp.close();
          break;
        }
      }
      this.forEach(&iterate);
      matrix.mapPoints(tmp._points.data);
      this = tmp;
    } else {
      if (matrix.rectStaysRect && this.points.length > 1) {
        FRect mapped;
        matrix.mapRect(this.bounds, mapped);
        this._bounds = mapped;
      } else {
        this.boundsIsClean = false;
      }

      matrix.mapPoints(this._points.data);
    }
  }
  static void subdivide(size_t K)(ref Path path, in FPoint[K] pts,
                               size_t subLevel=K) if (K==3 || K==4) {
    if (subLevel-- > 0) {
      auto split = splitBezier(pts, 0.5f);
      subdivide(path, split[0], subLevel);
      subdivide(path, split[1], subLevel);
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
    p._verbs.put(Verb.Move);
    p._points.put(FPoint(1, 1));
    p._verbs.put(Verb.Line);
    p._points.put(FPoint(1, 3));
    p._verbs.put(Verb.Quad);
    p._points.put([FPoint(2, 4), FPoint(3, 3)]);
    p._verbs.put(Verb.Cubic);
    p._points.put([FPoint(4, 2), FPoint(2, -1), FPoint(0, 0)]);
    p._verbs.put(Verb.Close);

    Verb[] verbExp = [Verb.Move, Verb.Line, Verb.Quad, Verb.Cubic, Verb.Line, Verb.Close];
    FPoint[][] ptsExp = [
      [FPoint(1,1)],
      [FPoint(1,1), FPoint(1,3)],
      [FPoint(1,3), FPoint(2,4), FPoint(3,3)],
      [FPoint(3,3), FPoint(4,2), FPoint(2,-1), FPoint(0,0)],
      [FPoint(0,0), FPoint(1,1)],
      [],
			 ];

    void iterate(Verb verb, in FPoint[] pts) {
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
