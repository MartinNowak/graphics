module skia.core.path_detail.path_measure;

private {
  import std.array : Appender, front, back;
  import std.bitmanip : bitfields;
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

  FPoint getPosAndNormalAtDistance(float distance, out FVector normal) const {
    assert(!this.empty && this.length > 0);

    float t;
    auto segment = getSegmentFromDistance(distance, t);
    FPoint pos;
    calcPosNormal(segment, t, pos, normal);
    return pos;
  }

private:

  Segment getSegmentFromDistance(float distance, out float t) const {
    assert(distance >= 0);

    distance = clampToRange!float(distance, 0.0f, this.length);

    auto sorted = assumeSorted!("a.distance < b.distance")(this.constSegments);
    auto lowerHalf = sorted.lowerBound(distComparable(distance));

    auto segment = this.constSegments[lowerHalf.length];

    if (lowerHalf.length == this.constSegments.length)
      t = 1.0f;
    else if (lowerHalf.length == 0) {
      // TODO: review case where distance == 0 and does not compare
      // smaller than the initial move segment
      t = 0.0f;
      return this.constSegments[1];
    }
    else {
      auto prevSegment = this.constSegments[lowerHalf.length - 1];
      auto segLength = segment.distance - prevSegment.distance;
      assert(segLength > 0);
      t = (distance - prevSegment.distance) / segLength;
    }
    return segment;
  }

  //! missing const overload for data[]
  @property const(Segment[]) constSegments() const {
    return cast(const(Segment[]))(cast(Appender!(Segment[]))this.segments).data;
  }

  void buildSegments(in Path path) {
    path.forEach!(QuadCubicFlattener)((Path.Verb verb, in FPoint[] pts){
        final switch(verb) {
        case Path.Verb.Move:
          this.segments.put(getSegment(this.curDist, verb, this.points.length));
          this.moveTo(pts[0]);
          break;

        case Path.Verb.Line:
          auto dist = this.curDist + curveLength(fixedAry!2(pts));
          this.segments.put(getSegment(dist, verb, this.points.length - 1));
          this.lineTo(pts[1]);
          break;

        case Path.Verb.Quad:
          auto dist = this.curDist + curveLength(fixedAry!3(pts));
          this.segments.put(getSegment(dist, verb, this.points.length - 1));
          this.quadTo(pts[1], pts[2]);
          break;

        case Path.Verb.Cubic:
          auto dist = this.curDist + curveLength(fixedAry!4(pts));
          this.segments.put(getSegment(dist, verb, this.points.length - 1));
          this.cubicTo(pts[1], pts[2], pts[3]);
          break;

        case Path.Verb.Close:
          this.isClosed = true;
          break;
        }
      });
  }

  static float curveLength(size_t K)(FPoint[K] pts)
  {
    return distance(pts.front, pts.back);
  }

  void calcPosNormal(in Segment segment, float t, out FPoint pos, out FVector normal) const {
    switch (segment.type) {
    case Path.Verb.Line:
      auto pts = fixedAry!2(this.points[segment.pointIndex .. segment.pointIndex + 2]);
      pos = FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      normal.rotateCW();
      break;

    case Path.Verb.Quad:
      auto pts = fixedAry!3(this.points[segment.pointIndex .. segment.pointIndex + 3]);
      pos = FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      normal.rotateCW();
      break;

    case Path.Verb.Cubic:
      auto pts = fixedAry!4(this.points[segment.pointIndex .. segment.pointIndex + 4]);
      pos = FPoint(calcBezier!("x")(pts, t), calcBezier!("y")(pts, t));
      normal.setNormalize(calcBezierDerivative!("x")(pts, t), calcBezierDerivative!("y")(pts, t));
      normal.rotateCW();
      break;

    default:
      assert(0, to!string(segment.type));
    }
  }

  @property float curDist() const {
    return this.constSegments.length ? this.constSegments[$ - 1].distance : 0.0f;
  }
}

private:

struct Segment {
  float distance;
  alias Path.Verb Verb;
  mixin(bitfields!(
      Verb, "type", 2,
      size_t, "pointIndex", 30));
}

Segment getSegment(float distance, Path.Verb verb, size_t pointIndex) {
  assert(pointIndex >= 0, "invalid point index");
  Segment seg;
  seg.distance = distance;
  seg.type = verb;
  seg.pointIndex = pointIndex;
  return seg;
}

Segment distComparable(float dist) {
  Segment seg;
  seg.distance = dist;
  return seg;
}
