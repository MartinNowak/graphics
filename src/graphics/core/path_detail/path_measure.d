module graphics.core.path_detail.path_measure;

import std.array, std.algorithm, std.range, std.c.string;
import graphics.bezier.chop, graphics.bezier.curve, graphics.core.path, graphics.bezier.curve, graphics.math.clamp;
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
    auto verb = _data.verbs[$ - range.length + 1];
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
    auto verb = _data.verbs[$ - range.length + 1];
    auto pos = calcPos(range[1], verb, t);
    normal = calcNormal(range[1], verb, t);
    return pos;
  }

  const(FPoint[]) segPoints(in Segment seg, Path.Verb verb) const {
    return _data.points[seg.pointIndex .. seg.pointIndex + verb + 1];
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

    void buildSegments(in Path path)
    {
        foreach(verb, pts; &path.apply!QuadCubicFlattener)
        {
            final switch(verb) {
            case Path.Verb.Move:
                this.segments.put(getSegment(this.curDist, this.points.length));
                this.moveTo(pts[0]);
                break;

            case Path.Verb.Line:
                auto dist = this.curDist + curveLength!2(pts);
                this.segments.put(getSegment(dist, this.points.length - 1));
                this.lineTo(pts[1]);
                break;

            case Path.Verb.Quad:
                auto dist = this.curDist + curveLength!3(pts);
                this.segments.put(getSegment(dist, this.points.length - 1));
                this.quadTo(pts[1], pts[2]);
                break;

            case Path.Verb.Cubic:
                auto dist = this.curDist + curveLength!4(pts);
                this.segments.put(getSegment(dist, this.points.length - 1));
                this.cubicTo(pts[1], pts[2], pts[3]);
                break;

            case Path.Verb.Close:
                this.isClosed = true;
                break;
            }
        };
        assert(this.verbs.length == this.segments.data.length);
    }

    static float curveLength(size_t K)(in FPoint[] pts)
    {
        assert(pts.length >= K);
        return distance(pts[0], pts[K-1]);
    }

    FPoint calcPos(in Segment segment, Path.Verb verb, float t) const
    {
        switch (verb)
        {
        case Path.Verb.Line:
            FPoint[2] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 2 * FPoint.sizeof);
            return evalBezier(pts, t);
        case Path.Verb.Quad:
            FPoint[3] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 3 * FPoint.sizeof);
            return evalBezier(pts, t);
        case Path.Verb.Cubic:
            FPoint[4] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 4 * FPoint.sizeof);
            return evalBezier(pts, t);

        default:
            assert(0);
        }
    }

    FVector calcNormal(in Segment segment, Path.Verb verb, float t) const
    {
        FVector normal;
        switch (verb)
        {
        case Path.Verb.Line:
            FPoint[2] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 2 * FPoint.sizeof);
            normal.setNormalize(evalBezierDer(pts, t));
            break;
        case Path.Verb.Quad:
            FPoint[3] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 3 * FPoint.sizeof);
            normal.setNormalize(evalBezierDer(pts, t));
            break;
        case Path.Verb.Cubic:
            FPoint[4] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 4 * FPoint.sizeof);
            normal.setNormalize(evalBezierDer(pts, t));
            break;

        default:
            assert(0);
        }
        normal.rotateCCW();
        return normal;
    }

    @property float curDist() const
    {
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

static void appendChopped(string interval="[]")(ref Appender!(immutable(FPoint)[]) app,
                                                in FPoint[] pts, double startT, double stopT)
in
{
  assert(fitsIntoRange!("[]")(startT, 0.0, 1.0));
  assert(fitsIntoRange!("[]")(stopT, 0.0, 1.0));
  assert(stopT > startT);
}
body
{
  switch(pts.length)
  {
  case 2:
      FPoint[2] fpts = void;
      memcpy(fpts.ptr, pts.ptr, 2 * FPoint.sizeof);
      chopBezier(fpts, startT, stopT);
      trimApp!(interval)(app, fpts);
      break;

  case 3:
      FPoint[3] fpts = void;
      memcpy(fpts.ptr, pts.ptr, 3 * FPoint.sizeof);
      chopBezier(fpts, startT, stopT);
      trimApp!(interval)(app, fpts);
      break;

  case 4:
      FPoint[4] fpts = void;
      memcpy(fpts.ptr, pts.ptr, 4 * FPoint.sizeof);
      chopBezier(fpts, startT, stopT);
      trimApp!(interval)(app, fpts);
      break;

  default:
      assert(0);
  }
}

void trimApp(string interval, size_t K)(ref Appender!(immutable(FPoint)[]) app, FPoint[K] pts)
{
    enum leftOff = intervalOffset(interval[0]);
    enum rightOff = intervalOffset(interval[1]);
    app.put(pts[leftOff .. $ - rightOff]);
}

void chopBezier(size_t K)(ref FPoint[K] pts, double startT, double stopT)
{
    FPoint[K] tmp = void;
    if (startT > 0.0)
        splitBezier(tmp, pts, startT);

    if (startT > 0.0 && stopT < 1.0)
        stopT = (stopT - startT) / (1.0 - startT);

    if (stopT < 1.0)
    {
        splitBezier(tmp, pts, stopT);
        pts = tmp;
    }
}

size_t intervalOffset(dchar c)
{
    switch (c) {
    case '(': return 1;
    case ')': return 1;
    case '[': return 0;
    case ']': return 0;
    default: assert(0);
    }
}
