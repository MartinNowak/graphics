module graphics.core.path_detail.path_measure;

import std.array, std.algorithm, std.range : assumeSorted;
import graphics.bezier.chop, graphics.bezier.curve, graphics.core.path, graphics.core.edge_detail.algo,
  graphics.math.fixed_ary, graphics.math.clamp, graphics.util.format;
import guip.point;

struct PathMeasure {
  Path _path;
  alias _path this;
  bool isClosed;
  Appender!(Segment[]) segments;

  this(in Path path) {
    this.buildSegments(path);
  }

  @property float length() const {
    return this.curDist;
  }

  FPoint getPosAtDistance(float distance) const
  out(pt) {
    assert(this.bounds.contains(pt));
  } body {
    assert(!this.empty && this.length > 0);

    distance = clampToRange!float(distance, 0.0f, this.length);

    auto range = segmentRange(distance);
    auto t = calcT(distance, range[0], range[1]);
    auto verb = this.verbs[$ - range.length + 1];
    auto pos = calcPos(range[1], verb, t);
    return pos;
  }

  FPoint getPosAndNormalAtDistance(float distance, out FVector normal) const
  out(pt) {
    assert(this.bounds.contains(pt));
  } body {
    assert(!this.empty && this.length > 0);

    distance = clampToRange!float(distance, 0.0f, this.length);

    auto range = segmentRange(distance);
    auto t = calcT(distance, range[0], range[1]);
    auto verb = this.verbs[$ - range.length + 1];
    auto pos = calcPos(range[1], verb, t);
    normal = calcNormal(range[1], verb, t);
    return pos;
  }

  void appendRangeToPath(float startD, float stopD, ref Path path) {
    startD = clampToRange!float(startD, 0.0f, this.length);
    stopD = clampToRange!float(stopD, 0.0f, this.length);
    if (startD >= stopD)
      return;

    auto start = segmentRange(startD);
    auto startT = calcT(startD, start.front, start[1]);
    start.popFront;
    auto stop = segmentRange(stopD);
    auto stopT = calcT(stopD, stop.front, stop[1]);
    stop.popFront;

    auto verbs = this.verbs[$ - start.length .. $ - stop.length + 1];

    if (start.length == stop.length) {
      // startD and stopD are in same segment
      assert(stopT > startT);
      appendChopped!("[]")(path._points, segPoints(start.front, verbs.front), startT, stopT);
    } else {
      appendChopped!("[)")(path._points, segPoints(start.front, verbs.front), startT, 1.0);

      if (start.length > stop.length + 1)
        path._points.put(this.points[start[1].pointIndex .. stop.front.pointIndex]);

      if (stopT > 0.0) {
        appendChopped!("[]")(path._points, segPoints(stop.front, verbs.back), 0.0, stopT);
      } else {
        path._points.put(this.points[stop.front.pointIndex]);
        verbs.popBack;
      }
    }
    path._verbs.put(Path.Verb.Move);
    path._verbs.put(verbs);
  }

  const(FPoint[]) segPoints(in Segment seg, Path.Verb verb) const {
    return this.points[seg.pointIndex .. seg.pointIndex + verb + 1];
  }

private:

  /**
     Returns the range of segments starting with the one before distance.
   */
  const(Segment)[] segmentRange(float distance) const
  in {
    assert(fitsIntoRange!("[]")(distance, 0.0, this.length));
  } out(range) {
    assert(range.length >= 2, to!string(constSegments)~to!string(distance));
  } body {

    auto sorted = assumeSorted!("a.distance < b.distance")(constSegments);
    auto upperHalf = sorted.upperBound(distComparable(distance));
    assert(upperHalf.length < constSegments.length);
    auto count = upperHalf.length == 0 ? 2 : upperHalf.length + 1;
    return constSegments[$ - count.. $];
  }

  float calcT(float distance, in Segment left, in Segment right) const
  in {
    assert(fitsIntoRange!("[]")(distance, 0.0, this.length));
    assert(fitsIntoRange!("[]")(distance, left.distance, right.distance));
  } out(t) {
    assert(fitsIntoRange!("[]")(t, 0.0f, 1.0f));
  } body {
    return (distance - left.distance) / (right.distance - left.distance);
  }

  //! missing const overload for data[]
  @property const(Segment[]) constSegments() const {
    return cast(const(Segment[]))(cast(Appender!(Segment[]))this.segments).data;
  }

  void buildSegments(in Path path) {
    path.forEach!(QuadCubicFlattener)((Path.Verb verb, in FPoint[] pts){
        final switch(verb) {
        case Path.Verb.Move:
          this.segments.put(getSegment(this.curDist, this.points.length));
          this.moveTo(pts[0]);
          break;

        case Path.Verb.Line:
          auto dist = this.curDist + curveLength(fixedAry!2(pts));
          this.segments.put(getSegment(dist, this.points.length - 1));
          this.lineTo(pts[1]);
          break;

        case Path.Verb.Quad:
          auto dist = this.curDist + curveLength(fixedAry!3(pts));
          this.segments.put(getSegment(dist, this.points.length - 1));
          this.quadTo(pts[1], pts[2]);
          break;

        case Path.Verb.Cubic:
          auto dist = this.curDist + curveLength(fixedAry!4(pts));
          this.segments.put(getSegment(dist, this.points.length - 1));
          this.cubicTo(pts[1], pts[2], pts[3]);
          break;

        case Path.Verb.Close:
          this.isClosed = true;
          break;
        }
      });
    assert(this.verbs.length == this.segments.data.length);
  }

  static float curveLength(size_t K)(FPoint[K] pts)
  {
    return distance(pts.front, pts.back);
  }

  FPoint calcPos(in Segment segment, Path.Verb verb, float t) const {
    switch (verb) {
    case Path.Verb.Line:
      auto pts = fixedAry!2(this.points[segment.pointIndex .. segment.pointIndex + 2]);
      return evalBezier(pts, t);
    case Path.Verb.Quad:
      auto pts = fixedAry!3(this.points[segment.pointIndex .. segment.pointIndex + 3]);
      return evalBezier(pts, t);
    case Path.Verb.Cubic:
      auto pts = fixedAry!4(this.points[segment.pointIndex .. segment.pointIndex + 4]);
      return evalBezier(pts, t);
    default:
      assert(0, to!string(verb));
    }
  }

  FVector calcNormal(in Segment segment, Path.Verb verb, float t) const {
    FVector normal;
    switch (verb) {
    case Path.Verb.Line:
      auto pts = fixedAry!2(this.points[segment.pointIndex .. segment.pointIndex + 2]);
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      break;
    case Path.Verb.Quad:
      auto pts = fixedAry!3(this.points[segment.pointIndex .. segment.pointIndex + 3]);
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      break;
    case Path.Verb.Cubic:
      auto pts = fixedAry!4(this.points[segment.pointIndex .. segment.pointIndex + 4]);
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      break;
    default:
      assert(0, to!string(verb));
    }
    normal.rotateCCW();
    return normal;
  }

  @property float curDist() const {
    return this.constSegments.length ? this.constSegments[$ - 1].distance : 0.0f;
  }
}

private:

struct Segment {
  @property string toString() const {
    return "Segment " ~ to!string(distance);
  }
  float distance;
  uint pointIndex;
}

Segment getSegment(float distance, size_t pointIndex) {
  assert(pointIndex >= 0, "invalid point index");
  Segment seg;
  seg.distance = distance;
  seg.pointIndex = checkedTo!uint(pointIndex);
  return seg;
}

Segment distComparable(float dist) {
  Segment seg;
  seg.distance = dist;
  return seg;
}

static void appendChopped(string interval="[]")(ref Appender!(FPoint[]) app, in FPoint[] pts, double startT, double stopT)
in {
  assert(fitsIntoRange!("[]")(startT, 0.0, 1.0));
  assert(fitsIntoRange!("[]")(stopT, 0.0, 1.0));
  assert(stopT > startT);
} body {
  switch(pts.length) {
  case 2: trimApp!(interval)(app, chopBezier(fixedAry!2(pts), startT, stopT)); break;
  case 3: trimApp!(interval)(app, chopBezier(fixedAry!3(pts), startT, stopT)); break;
  case 4: trimApp!(interval)(app, chopBezier(fixedAry!4(pts), startT, stopT)); break;
  default: assert(0);
  }
}

void trimApp(string interval, size_t K)(ref Appender!(FPoint[]) app, FPoint[K] pts) {
  enum leftOff = intervalOffset(interval[0]);
  enum rightOff = intervalOffset(interval[1]);
  app.put(pts[leftOff .. $ - rightOff]);
}

FPoint[K] chopBezier(size_t K)(FPoint[K] pts, double startT, double stopT) {
  if (startT > 0.0)
    pts = splitBezier(pts, startT)[1];

  if (startT > 0.0 && stopT < 1.0)
    stopT = (stopT - startT) / (1.0 - startT);

  if (stopT < 1.0)
    pts = splitBezier(pts, stopT)[0];

  return pts;
}

size_t intervalOffset(dchar c) {
  switch (c) {
  case '(': return 1;
  case ')': return 1;
  case '[': return 0;
  case ']': return 0;
  default: assert(0);
  }
}
