module graphics.core.path_detail.path_measure;

import core.stdc.string;
import std.array, std.algorithm, std.conv, std.range;
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
    assert(range.length >= 2);
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
        }
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
            normal = evalBezierDer(pts, t).normalized;
            break;
        case Path.Verb.Quad:
            FPoint[3] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 3 * FPoint.sizeof);
            normal = evalBezierDer(pts, t).normalized;
            break;
        case Path.Verb.Cubic:
            FPoint[4] pts = void;
            memcpy(pts.ptr, _data.points.ptr + segment.pointIndex, 4 * FPoint.sizeof);
            normal = evalBezierDer(pts, t).normalized;
            break;

        default:
            assert(0);
        }
        normal = normal.rotatedCCW();
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

unittest
{
    import graphics.core.testing : near, nearP, polyline;
    import std.math : sqrt;

    enum tol = 1e-3f;

    // empty path
    auto m0 = PathMeasure(Path.init);
    assert(m0.empty && m0.length == 0.0f);

    // polyline (0,0)->(3,4)->(6,4)->(6,8): length 5 + 3 + 4
    auto m = PathMeasure(polyline(FPoint(0, 0), FPoint(3, 4), FPoint(6, 4), FPoint(6, 8)));
    assert(near(m.length, 12.0f, tol));

    // positions clamp to the ends and interpolate within a segment
    assert(nearP(m.getPosAtDistance(0.0f), FPoint(0, 0), tol));
    assert(nearP(m.getPosAtDistance(5.0f), FPoint(3, 4), tol));
    assert(nearP(m.getPosAtDistance(6.5f), FPoint(4.5f, 4), tol));
    assert(nearP(m.getPosAtDistance(100.0f), FPoint(6, 8), tol)); // clamps
    assert(nearP(m.getPosAtDistance(-5.0f), FPoint(0, 0), tol));  // clamps

    FVector normal;
    auto pos = m.getPosAndNormalAtDistance(6.5f, normal);
    assert(nearP(pos, FPoint(4.5f, 4), tol));
    assert(near(normal.x, 0.0f, tol) && near(normal.y, -1.0f, tol)); // tangent +x, rotated CCW

    // subranges: inside one segment, across several segments, and ending
    // exactly on a segment boundary (stopT == 0: the closing verb is dropped
    // instead of chopping a zero-length sliver)
    Path sub;
    m.appendRangeToPath(2.0f, 7.0f, sub);
    assert(near(PathMeasure(sub).length, 5.0f, tol));

    Path longRange;
    m.appendRangeToPath(1.0f, 11.0f, longRange);
    assert(near(PathMeasure(longRange).length, 10.0f, tol));

    Path toBoundary;
    m.appendRangeToPath(1.0f, 5.0f, toBoundary);
    assert(near(PathMeasure(toBoundary).length, 4.0f, tol));

    Path sub2;
    m.appendRangeToPath(7.0f, 7.0f, sub2);
    assert(sub2.empty);

    // a closed triangle: the synthesized closing edge is measured, too
    // (Path.apply emits a closing Line before Close)
    Path tri;
    tri.moveTo(FPoint(0, 0));
    tri.lineTo(FPoint(10, 0));
    tri.lineTo(FPoint(10, 10));
    tri.close();
    auto mt = PathMeasure(tri);
    assert(mt.isClosed);
    assert(near(mt.length, 10.0f + 10.0f + 10.0f * sqrt(2.0f), tol));
}

unittest
{
    import graphics.core.testing : near, nearP;
    import std.math : sqrt;

    enum tol = 1e-3f;
    FVector normal;

    // a quad's measured length lies between chord and control polygon;
    // position and normal extraction take the quad branch of calcPos/calcNormal
    Path q;
    q.moveTo(FPoint(0, 0));
    q.quadTo(FPoint(10, 0), FPoint(10, 10));
    auto mq = PathMeasure(q);
    float chord = 10.0f * sqrt(2.0f);
    assert(mq.length >= chord - 1e-3f && mq.length <= 20.0f + 1e-3f);
    auto qmid = mq.getPosAndNormalAtDistance(mq.length * 0.5f, normal);
    assert(qmid.x > 0.0f && qmid.y > 0.0f && qmid.x < 10.0f && qmid.y < 10.0f);
    assert(near(normal.length, 1.0f, tol)); // normals are unit length

    // likewise for a cubic: its arch peak sits near (5, 7.5)
    Path c;
    c.moveTo(FPoint(0, 0));
    c.cubicTo(FPoint(0, 10), FPoint(10, 10), FPoint(10, 0));
    auto mc = PathMeasure(c);
    assert(mc.length > 0.0f);
    assert(nearP(mc.getPosAtDistance(0.0f), FPoint(0, 0), tol));
    assert(nearP(mc.getPosAtDistance(mc.length), FPoint(10, 0), tol));
    auto mid = mc.getPosAtDistance(mc.length * 0.5f);
    assert(nearP(mid, FPoint(5, 7.5), 0.5f)); // the arch's peak
    auto at = mc.getPosAndNormalAtDistance(mc.length * 0.25f, normal);
    assert(at.y > 0.0f && near(normal.length, 1.0f, tol));
}

unittest
{
    import graphics.core.testing : near, nearP;
    import std.array : appender;

    enum tol = 1e-3;

    // interval trimming
    assert(intervalOffset('[') == 0 && intervalOffset(']') == 0);
    assert(intervalOffset('(') == 1 && intervalOffset(')') == 1);

    auto app = appender!(immutable(FPoint)[]);
    FPoint[2] seg = [FPoint(0, 0), FPoint(1, 1)];
    trimApp!"[]"(app, seg);
    assert(app.data.length == 2);
    trimApp!"()" (app, seg);
    assert(app.data.length == 2); // open on both ends: a 2-point segment has nothing left

    // chopping the middle half of a straight segment
    app = appender!(immutable(FPoint)[]);
    appendChopped(app, seg[], 0.25, 0.75);
    assert(app.data.length == 2);
    assert(nearP(app.data[0], FPoint(0.25, 0.25), tol));
    assert(nearP(app.data[1], FPoint(0.75, 0.75), tol));

    // chopping a quad at t=0..0.5 keeps all three control points
    app = appender!(immutable(FPoint)[]);
    FPoint[3] quad = [FPoint(0, 0), FPoint(2, 0), FPoint(2, 2)];
    appendChopped(app, quad[], 0.0, 0.5);
    assert(app.data.length == 3);
    assert(nearP(app.data[$-1], FPoint(1.5, 0.5), tol)); // point on curve at t=0.5

    // chopping a cubic at 0.25..0.75: exact de Casteljau section points
    app = appender!(immutable(FPoint)[]);
    FPoint[4] cubic = [FPoint(0, 0), FPoint(0, 10), FPoint(10, 10), FPoint(10, 0)];
    appendChopped(app, cubic[], 0.25, 0.75);
    assert(app.data.length == 4);
    assert(nearP(app.data[0], FPoint(1.5625, 5.625), tol)); // cubic(t=0.25)
    assert(nearP(app.data[3], FPoint(8.4375, 5.625), tol)); // cubic(t=0.75)

    // segment comparators
    auto s = getSegment(1.5f, 3);
    assert(s.distance == 1.5f && s.pointIndex == 3);
    assert(distComparable(2.0f).distance == 2.0f);
    assert(s.toString.length > 0);
}
