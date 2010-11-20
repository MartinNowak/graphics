module skia.core.path;

import skia.core.point;
import skia.core.rect;

import std.array;

debug=WHITEBOX;

// TODO FPoint
class Path
{
  IPoint[] points;
  Verb[] verbs;
  IRect bounds;
  bool boundsIsDirty;
  ubyte fillType;
  ubyte isConvex;

  @property bool empty() const {
    return this.verbs.length == 0
      || this.verbs.length == 1 && this.verbs[0] == Verb.Move;
  }
  @property bool inverseFillType() const { return (this.fillType & 2) != 0; }
  enum Verb : ubyte
  {
    Move  = 0,
    Line  = 1,
    Quad  = 2,
    Cubic = 3,
    Close,
    Done,
  }
  enum NeedMoveToState
  {
    AfterClose,
    AfterCons,
    AfterPrefix,
  }
  struct Iter {
    IPoint[] points;
    Verb[] verbs;
    IPoint moveTo;
    IPoint lastPt;
    bool forceClose;
    // TODO initialization
    bool needClose;
    NeedMoveToState needMoveTo;
    bool closeLine;

    debug(WHITEBOX) private auto opDispatch(string m, Args...)(Args a) {
      throw new Exception("Unimplemented property "~m);
    }

    this(Path path, bool forceClose) {
      assert(!(path is null));
      this.verbs = path.verbs.save();
      this.points = path.points.save();
      this.forceClose = forceClose;
    }

    bool isClosedContour() {
      if (this.forceClose)
	return true;
      
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


    Verb next(out IPoint[4] pts) {     
      if (this.verbs.length == 0) {
	if (this.needClose) {
	  if (this.autoClose(pts) == Verb.Line)
	    return Verb.Line;
	  this.needClose = false;
	  return Verb.Close;
	}
	return Verb.Done;
      }


      Verb verb = this.verbs.front; this.verbs.popFront();

      final switch (verb) {

      case Verb.Move:
	if (this.needClose) {
	  this.verbs = this.verbs[-1..$];
	  verb = this.autoClose(pts);
	  if (verb == Verb.Close) {
	    this.needClose = false;
	  }
	  return verb;
	}
	if (this.verbs.length == 0) {
	  return Verb.Done;
	}
	this.moveTo = this.points[0];
	pts[0] = this.points.front;
	this.points.popFront();
	this.needMoveTo = NeedMoveToState.AfterCons;
	this.needClose = this.forceClose;
	break;

      case Verb.Line, Verb.Quad, Verb.Cubic : {
	if (this.consMoveTo(pts))
	  return Verb.Move;

	auto nPoints = verb;
	pts[1..1 + nPoints] = this.points[0..nPoints];
	this.lastPt = this.points[nPoints-1];

	if (verb == Verb.Line)
	  this.closeLine = false;

	while (nPoints-- > 0)
	  this.points.popFront();

	break;
      }

      case Verb.Close:
	verb = this.autoClose(pts);
	if (verb == Verb.Line)
	  this.verbs = this.verbs[-1..$];
	else
	  this.needClose = false;
	this.needMoveTo = NeedMoveToState.AfterClose;
	break;
      }
      return verb;
    }

    bool consMoveTo(out IPoint[4] pts) {
      if (this.needMoveTo == NeedMoveToState.AfterClose) {
	pts[0] = this.moveTo;
	this.needClose = this.forceClose;
	this.needMoveTo = NeedMoveToState.AfterCons;
	this.verbs = this.verbs[-1..$];
	return true;
      }

      if (this.needMoveTo == NeedMoveToState.AfterCons) {
	pts[0] = this.moveTo;
	this.needMoveTo = NeedMoveToState.AfterPrefix;
      }
      else {
	assert(this.needMoveTo == NeedMoveToState.AfterPrefix);
	pts[0] = this.points[-1];
      }
      return false;
    }

    Verb autoClose(out IPoint[4] pts) {
      if (this.lastPt != this.moveTo) {
	//! TODO: Floating point equality of NAN Points
	pts[] = [this.lastPt, this.moveTo];
	this.lastPt = this.moveTo;
	this.closeLine = true;
	return Verb.Line;
      }
      return Verb.Close;
    }
  }

  debug(WHITEBOX) private auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }

}