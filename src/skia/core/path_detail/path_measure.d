module skia.core.path_detail.path_measure;

import std.array, std.algorithm, std.range : assumeSorted;
import skia.core.path, skia.core.edge_detail.algo, skia.math.fixed_ary, skia.math.clamp, skia.util.format;
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

    auto startPts = startT > 0.0
      ? chopBezier(segPoints(start.front, verbs.front), startT, true)
      : segPoints(start.front, verbs.front);

    if (start.length == stop.length) {
      // startD and stopD are in same segment
      assert(stopT > startT);
      auto stopPts = stopT < 1.0
        ? chopBezier(startPts, (stopT - startT) / (1.0 - startT), false)
        : startPts;
      path._points.put(stopPts);
    } else {
      // startD and stopD are in different segments
      path._points.put(startPts);
      path._points.put(this.points[start.front.pointIndex + verbs.front .. stop.front.pointIndex]);
      auto stopPts = stopT < 1.0
        ? chopBezier(segPoints(stop.front, verbs.back), stopT, false)
        : segPoints(stop.front, verbs.back);
      path._points.put(stopPts);
    }
    path._verbs.put(Path.Verb.Move);
    path._verbs.put(verbs);
  }

  static immutable(FPoint[]) chopBezier(in FPoint[] pts, float t, bool returnRight)
  in {
    assert(fitsIntoRange!("()")(t, 0.0f, 1.0f), to!string(t));
  } body {
    switch (pts.length) {
    case 2: return splitBezier(fixedAry!2(pts), t)[returnRight].idup;
    case 3: return splitBezier(fixedAry!2(pts), t)[returnRight].idup;
    case 4: return splitBezier(fixedAry!2(pts), t)[returnRight].idup;
    default: assert(0);
    }
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
      return FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
    case Path.Verb.Quad:
      auto pts = fixedAry!3(this.points[segment.pointIndex .. segment.pointIndex + 3]);
      return FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
    case Path.Verb.Cubic:
      auto pts = fixedAry!4(this.points[segment.pointIndex .. segment.pointIndex + 4]);
      return FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
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
