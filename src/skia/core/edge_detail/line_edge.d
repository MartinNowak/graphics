module skia.core.edge_detail.line_edge;

private {
  import std.conv : to;

  import skia.core.edge_detail.edge;
  import skia.core.point;
}

////////////////////////////////////////////////////////////////////////////////

// TODO: pass in clip rect
void lineEdge(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 2);
  appender.put(makeLine(pts));
}

package:

struct LineEdge(T) {
  @property string toString() const {
    return "LineEdge!" ~ to!string(typeid(T)) ~
      " dx: " ~ to!string(dx);
  }
  this(Point!T p0, Point!T p1) {
    assert(p1.y >= p0.y);
    if (p0.y == p1.y)
      this.dx = 0;
    else
      this.dx = (p1.x - p0.x) / (p1.y - p0.y);
  }
  T dx;
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


Edge!T makeLine(T)(in Point!T[] pts) {
  assert(pts.length == 2);
  auto topI = pts[0].y > pts[1].y ? 1 : 0;
  auto botI = 1 - topI;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = EdgeType.Line;
  res.line = LineEdge!T(pts[topI], pts[botI]);
  return res;
}
