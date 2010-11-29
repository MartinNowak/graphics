module skia.core.path;

import skia.core.point;
import skia.core.rect;

import std.array;
import std.conv : to;
import std.range;
import std.traits;

//debug=WHITEBOX;
debug import std.stdio : writeln, printf;

// TODO FPoint
struct Path
{
private:
  IPoint[] points;

  // FIXME Verb[] breaks std.array.front in const function
  ubyte[] verbs;

  IRect _bounds;
  bool boundsIsDirty;
  ubyte fillType;
  ubyte isConvex;

public:
  string toString() const {
    string res;
    res ~= "Path, bounds: " ~ to!string(this._bounds) ~ "\n";
    this.forEach((Verb verb, const IPoint[] pts) {
        res ~= verbToString(verb) ~ ": ";
        foreach(IPoint pt; pts) {
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
  @property bool empty() const {
    return this.verbs.length == 0
      || this.verbs.length == 1 && this.verbs[0] == Verb.Move;
  }
  @property bool inverseFillType() const { return (this.fillType & 2) != 0; }
  void toggleInverseFillType() {
    this.fillType ^= 2;
  }

  @property IRect bounds() const {
    return this._bounds;
  }
  @property void bounds(in IRect bounds) {
    return this._bounds = bounds;
  }

  enum Verb : ubyte
  {
    Move = 0,
    Line  = 1,
    Quad  = 2,
    Cubic = 3,
    Close,
  }

  static ubyte verbToMaxEdges(Verb verb) {
    /*
     * 0,  //  Verb.Move
     * 1,  //  Verb.Live
     * 2,  //  Verb.Quad
     * 3,  //  Verb.Cubic
     * 0,  //  Verb.Close
     */
    return (verb > 3) ? 0 : verb;
  }

  //  alias void delegate(const Verb, const IPoint[]) IterDg;
  void forEach(IterDg)(IterDg dg) const {
    IPoint lastPt;
    IPoint moveTo;

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

  @property IPoint lastPoint() const {
    return this.points.length == 0 ? IPoint() : this.points[$];
  }

  bool lastVerbWas(Verb verb) const {
    return this.verbs.length == 0 ? false : this.verbs[$] == verb;
  }

  void ensureStart() {
    if (this.verbs.empty) {
      assert(this.points.length == 0);
      this.points ~= IPoint.init;
      this.verbs ~= Verb.Move;
    }
  }

  void primTo(IPoint[] pts) {
    this.ensureStart();
    this.points ~= pts;
    this.verbs ~= cast(Verb)pts.length;
  }

  void rPrimTo(IPoint[] pts) {
    auto lPt = this.lastPoint;
    foreach(ref pt; pts) {
      pt = pt + lPt;
    }
    IPoint pt;
    this.primTo(pts);
  }

  void moveTo(in IPoint pt) {
    if (this.lastVerbWas(Verb.Move)) {
      this.points[$] = pt;
    }
    else {
      this.points ~= pt;
      this.verbs ~= Verb.Move;
    }
    this.boundsIsDirty = true;
  }
  void rMoveTo(in IPoint pt) {
    this.moveTo(this.lastPoint + pt);
  }

  void lineTo(in IPoint pt) {
    this.primTo([pt]);
  }
  void rLineTo(in IPoint pt) {
    this.rPrimTo([pt]);
  }

  void quadTo(in IPoint pt1, in IPoint pt2) {
    this.primTo([pt1, pt2]);
  }
  void rQuadTo(in IPoint pt1, in IPoint pt2) {
    this.rPrimTo([pt1, pt2]);
  }

  void cubicTo(in IPoint pt1, in IPoint pt2, in IPoint pt3) {
    this.primTo([pt1, pt2, pt3]);
  }
  void rCubicTo(in IPoint pt1, in IPoint pt2, in IPoint pt3) {
    this.rPrimTo([pt1, pt2, pt3]);
  }

  void close() {
    if (this.verbs.length > 0) {
      switch (this.verbs[$]) {
      case Verb.Line, Verb.Quad, Verb.Cubic:
        this.verbs ~= Verb.Close;
      default:
        assert(false);
        break;
      }
    }
  }

  void computeBounds() {
    this._bounds = IRect.calcBounds(this.points);
    this.boundsIsDirty = false;
  }

  debug(WHITEBOX) private auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }

  unittest
  {
    Path p;
    p.verbs ~= Verb.Move;
    p.points ~= IPoint(1, 1);
    p.verbs ~= Verb.Line;
    p.points ~= IPoint(1, 3);
    p.verbs ~= Verb.Quad;
    p.points ~= [IPoint(2, 4), IPoint(3, 3)];
    p.verbs ~= Verb.Cubic;
    p.points ~= [IPoint(4, 2), IPoint(2, -1), IPoint(0, 0)];
    p.verbs ~= Verb.Close;

    Verb[] verbExp = [Verb.Move, Verb.Line, Verb.Quad, Verb.Cubic, Verb.Line, Verb.Close];
    IPoint[][] ptsExp = [
      [IPoint(1,1)],
      [IPoint(1,1), IPoint(1,3)],
      [IPoint(1,3), IPoint(2,4), IPoint(3,3)],
      [IPoint(3,3), IPoint(4,2), IPoint(2,-1), IPoint(0,0)],
      [IPoint(0,0), IPoint(1,1)],
      [],
			 ];

    void iterate(const Verb verb, const IPoint[] pts) {
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
