module skia.core.edge_detail.line_edge;

private {
  import std.algorithm : swap;
  import std.conv : to;
  import std.array;

  import skia.core.edge_detail.edge;
  import skia.core.edge_detail.algo;
  import skia.core.rect;
  import skia.core.point;
  import skia.math.clamp;
}

////////////////////////////////////////////////////////////////////////////////

//! TODO: really reject horizontal edges?
void lineEdge(R, T)(ref R appender, Point!T[2] pts) {
  if (pts[0].y == pts[1].y)
    return;

  auto w = sortPoints(pts);
  appender.put(makeLine(pts, w));
}

void clippedLineEdge(R, T)(ref R appender, Point!T[2] pts, in IRect clip) {
  if (pts[0].y == pts[1].y)
    return;

  auto w = sortPoints(pts);
  if (clipPoints(pts, clip))
    appender.put(makeLine(pts, w));
}

bool clipPoints(T)(ref Point!T[2] pts, in IRect clip) {
  assert(pts.front.y <= pts.back.y);
  if (pts.front.y > clip.bottom || pts.back.y < clip.top)
    return false;

  // clip the line to top
  if (pts.front.y < clip.top) {
    pts.front.x = pts.front.x + (clip.top - pts.front.y) * slope(pts);
    pts.front.y = clip.top;
  }
  return true;
}

/** A fully clipped line, but rather using thi only clip line's top and clip the rest while blitting.

void clippedLineEdge(R, T)(ref R appender, in Point!T[] pts, in IRect clip) {
  assert(pts.length == 2);
  if ((pts[0].y < clip.top && pts[1].y < clip.top)
      || (pts[0].y > clip.bottom && pts[1].y > clip.bottom))
    return;

  if (pts[0].y == pts[1].y) {
    Point!T[2] xpts = [
      Point!T(clampToRange(pts[0].x, clip.left, clip.right), pts[0].y),
      Point!T(clampToRange(pts[1].x, clip.left, clip.right), pts[1].y),
    ];
    appender.put(makeLine(xpts));
    return;
  }

  const slopeY = (pts[1].x - pts[0].x) / (pts[1].y - pts[0].y);
  T xFromY(T y) {
    return y == pts[0].y ? pts[0].x
    : y == pts[1].y ? pts[1].x
    : pts[0].x + y * slopeY;
  }

  const slopeX = (pts[1].y - pts[0].y) / (pts[1].x - pts[0].x);
  T yFromX(T x) {
    return pts[0].y + x * slopeX;
  }

  auto y0 = clampToRange(pts[0].y, clip.top, clip.bottom);
  auto cpt0 = Point!T(xFromY(y0), y0);
  auto y1 = clampToRange(pts[1].y, clip.top, clip.bottom);
  auto cpt1 = Point!T(xFromY(y1), y1);

  //! Add vertical lines, so that path gets filled correctly.
  void appendVertical(T x, ref Point!T yClamped) {
    auto y = yFromX(x);
    Point!T[2] vertical = [Point!T(x, yClamped.y), Point!T(x, y)];
    //! Keep winding correct
    if (x > yClamped.x)
      swap(vertical[0], vertical[1]);

    appender.put(makeLine(vertical));

    //! clamp point to x boundary
    yClamped.y = y;
    yClamped.x = x;
  }

  auto x0 = clampToRange(cpt0.x, clip.left, clip.right);
  if (x0 != cpt0.x) {
    appendVertical(x0, cpt0);
  }

  auto x1 = clampToRange(cpt1.x, clip.left, clip.right);
  if (x1 != cpt1.x) {
    appendVertical(x1, cpt1);
  }

  appender.put(makeLine([cpt0, cpt1]));
}

unittest {
  auto app = appender!(Edge!float[])();
  //! Line fully within clip
  auto pts = [FPoint(0.0f, 0.0f), FPoint(10.0f, 10.0f)];
  clippedLineEdge(app, pts, IRect(100, 100));
  assert(app.data.length == 1);
  assert(app.data[0].firstY == 0.0f);
  assert(app.data[0].lastY == 10.0f);

  app.clear();
  //! Line fully outside clip
  clippedLineEdge(app, pts, IRect(11, 11, 10, 10));
  assert(app.data.length == 0);

  app.clear();
  //! Test y clipped line
  clippedLineEdge(app, pts, IRect(0, 2, 10, 8));
  assert(app.data.length == 1);
  assert(app.data[0].p0 == FPoint(2.0f, 2.0f));
  assert(app.data[0].lastY == 8.0f);
  assert(app.data[0].line.dx == 1.0f);

  app.clear();
  //! Test x clipped line
  clippedLineEdge(app, pts, IRect(2, 0, 8, 10));
  assert(app.data.length == 3);
  //! The vertical substitute
  assert(app.data[0].p0 == FPoint(2.0f, 0.0f));
  assert(app.data[0].lastY == 2.0f);
  assert(app.data[0].line.dx == 0.0f);
  //! Another vertical substitute
  assert(app.data[1].p0 == FPoint(8.0f, 8.0f));
  assert(app.data[1].lastY == 10.0f);
  assert(app.data[1].line.dx == 0.0f);
  //! Choped middle part
  assert(app.data[2].p0 == FPoint(2.0f, 2.0f), to!string(app.data[2]));
  assert(app.data[2].lastY == 8.0f);
  assert(app.data[2].line.dx == 1.0f);

  app.clear();
  //! Test x and y clipped line, left chopped
  clippedLineEdge(app, pts, IRect(2, 0, 10, 9));
  assert(app.data.length == 2);
  //! The vertical substitute
  assert(app.data[0].p0 == FPoint(2.0f, 0.0f));
  assert(app.data[0].lastY == 2.0f);
  //! Choped part
  assert(app.data[1].p0 == FPoint(2.0f, 2.0f));
  assert(app.data[1].lastY == 9.0f);
  assert(app.data[1].line.dx == 1.0f);

  app.clear();
  //! Test x and y clipped line, right chopped
  clippedLineEdge(app, pts, IRect(0, 0, 8, 9));
  assert(app.data.length == 2);
  //! The vertical substitute
  assert(app.data[0].p0 == FPoint(8.0f, 8.0f));
  assert(app.data[0].lastY == 9.0f);
  assert(app.data[0].line.dx == 0.0f);
  //! Choped part
  assert(app.data[1].p0 == FPoint(0.0f, 0.0f));
  assert(app.data[1].lastY == 8.0f);
  assert(app.data[1].line.dx == 1.0f);
}
*/

package:

struct LineEdge(T) {
  @property string toString() const {
    return "LineEdge!" ~ to!string(typeid(T)) ~
      " pts: " ~ to!string(pts) ~
      " dx: " ~ to!string(dx);
  }
  this(Point!T[2] pts) {
    assert(pts.front.y <= pts.back.y);
    this.pts = pts;
    this.dx = slope(pts);
  }
  Point!T[2] pts;
  T dx;
}

T slope(T)(Point!T[2] pts) {
  if (pts.front.y == pts.back.y)
    return 0;
  else
    return (pts.back.x - pts.front.x) / (pts.back.y - pts.front.y);
}

T updateLine(T)(ref Edge!T pthis, T y) {
  pthis.curX = pthis.p0.x + (y - pthis.p0.y) * pthis.line.dx;
  return pthis.curX;
}

T getTLine(T)(in Edge!T pthis, T y) {
  return (y - pthis.firstY) / (pthis.lastY - pthis.firstY);
}

T calcTLine(string v, T)(in Edge!T pthis, T t) {
  assert(pthis.type == EdgeType.Line);
  static if (v == "y") {
    return t * (pthis.lastY - pthis.firstY) + pthis.firstY;
  } else {
    return t * (pthis.lastY - pthis.firstY) * pthis.line.dx + pthis.p0.x;
  }
}


Edge!T makeLine(T)(Point!T[2] pts, byte winding) {
  auto res = Edge!T(pts.front.x, pts.back.y);
  res.winding = winding;
  res.type = EdgeType.Line;
  res.line = LineEdge!T(pts);
  return res;
}
