module skia.core.path_detail.path_measure;

private {
  import std.array : Appender, front, back;
  import std.range : assumeSorted;

  import skia.core.path;
  import guip.point;
  import skia.core.edge_detail.algo;

  import skia.math.fixed_ary;
  import skia.math.clamp;
}

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

private:

  /**
     Returns the range of segments starting with the one before distance.
   */
  const(Segment[]) segmentRange(float distance) const
  in {
    assert(fitsIntoRange!("[]")(distance, 0.0, this.length));
  } out(range) {
    assert(range.length >= 2);
  } body {

    auto sorted = assumeSorted!("a.distance < b.distance")(constSegments);
    auto lowerHalf = sorted.lowerBound(distComparable(distance));
    assert(lowerHalf.length < constSegments.length);
    auto start = lowerHalf.length == 0 ? 0 : lowerHalf.length - 1;
    return constSegments[start .. $];
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
