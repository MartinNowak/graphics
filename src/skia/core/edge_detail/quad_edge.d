module skia.core.edge_detail.quad_edge;

private {
  import std.array : front, back;
  import std.conv : to;

  import skia.core.edge_detail.algo;
  import skia.core.edge_detail.edge;
  import skia.core.edge_detail.line_edge;
  import skia.core.rect;
  import skia.core.point;
  import skia.math.fixed_ary;

  import skia.util.format;
}

void quadraticEdge(R, T)(ref R appender, Point!T[3] pts) {
  if (isLine(pts)) {
    return lineEdge(appender, fixedAry!2(pts.front, pts.back));
  }

  if (monotonicY(pts)) {
    appendMonoQuad(appender, pts);
  } else {
    appendSplittedQuad(appender, pts);
  }
}

void clippedQuadraticEdge(R, T)(ref R appender, Point!T[3] pts, in IRect clip) {
  if (isLine(pts)) {
    Point!T[2] line = [pts.front, pts.back];
    return clippedLineEdge(appender, line, clip);
  }

  if (monotonicY(pts)) {
    appendMonoQuad(appender, pts, &clip);
  } else {
    appendSplittedQuad(appender, pts, &clip);
  }

}

package:

struct QuadraticEdge(T) {
  @property string toString() const {
    return "QuadraticEdge!" ~ to!string(typeid(T)) ~
      " pts: " ~ to!string(this.pts);
  }
  this(Point!T[3] pts) {
    assert(pts.front.y <= pts.back.y);
    this.pts = pts;
  }
  Point!T[3] pts;
};


T updateQuad(T)(ref Edge!T pthis, T y) {
  assert(pthis.type == EdgeType.Quad);

  auto t = getTQuad(pthis.quad.pts, y);
  pthis.curX = calcBezier!("x")(pthis.quad.pts, t);
  return pthis.curX;
}

T getTQuad(T)(ref Point!T[3] pts, T y) {
  if (y >= pts.back.y)
    return 1.0;
  if (y <= pts.front.y)
    return 0.0;

  T[2] roots;
  auto nRoots = quadIntersection(pts, y, roots);
  assert(nRoots == 1, formatString("y:%.7f quadPts:%s roots:%s",
                                   y, pts, roots));
  return roots[0];
}

private:

/**
 * Given the parametric eq.:
 * y(t) = (1-t)^2*y0 + 2*t*(1-t)*y1 + t^2*y2
 * the derivative is:
 * dy/dt = 2*t(y0-2y1+y2) + 2*(y1-y0)
 * Finding t at the extremum
 */
void appendSplittedQuad(R, T)(ref R appender, Point!T[3] pts, const (IRect*) clip=null) {
  T denom = pts[0].y - 2*pts[1].y + pts[2].y;
  T numer = pts[0].y - pts[1].y;
  T tValue;
  if (valid_unit_divide(numer, denom, tValue)) {
    auto ptss = splitBezier(pts, tValue);
    appendMonoQuad(appender, ptss[0], clip);
    appendMonoQuad(appender, ptss[1], clip);
  } else {
    // set middle y to the closest y of border points
    pts[1].y = abs(pts[0].y - pts[1].y) < abs(pts[2].y - pts[1].y)
      ? pts[0].y
      : pts[2].y;

    appendMonoQuad(appender, pts, clip);
  }
}

/**
 * Constructs a quad bezier, checks for clip bounds and appends a
 * quad starting a clip.top.
 */
void appendMonoQuad(R, T)(ref R appender, Point!T[3] pts, const(IRect*) clip=null) {
  auto w = sortPoints(pts);

  if (!clip || clipPoints(pts, *clip))
    appender.put(makeQuad(pts, w));
}

bool clipPoints(T)(ref Point!T[3] pts, in IRect clip) {
  assert(pts.front.y <= pts.back.y);
  if (pts.front.y >= clip.bottom || pts.back.y <= clip.top)
    return false;

  if (pts.front.y < clip.top) {
    auto t = getTQuad(pts, cast(T)clip.top);
    auto ptss = splitBezier(pts, t);
    pts = ptss[1];

    //! avoid rounding errors;
    assert(abs(pts.front.y - clip.top) < 10 * float.epsilon);
    pts[0].y = clip.top;
  }
  return true;
}

unittest {
  auto pts = fixedAry!3(FPoint(3.12613, 0.230524),
                             FPoint(4.67817, 2.7919),
                             FPoint(4.38304, 0.389878));
  auto app = appender!(Edge!float[])();
  quadraticEdge(app, pts);
  assert(app.data.length == 2, to!string(app.data));
}

Edge!T makeQuad(T)(in Point!T[3] pts, byte winding) {
  if (isLine(pts)) {
    return makeLine(fixedAry!2(pts.front, pts.back), winding);
  }

  auto res = Edge!T(pts.front.x, pts.back.y);
  res.winding = winding;
  res.type = EdgeType.Quad;
  res.quad = QuadraticEdge!T(pts);
  return res;
}

bool monotonicY(T)(in Point!T[] pts) {
  return (pts[0].y - pts[1].y) * (pts[1].y - pts[2].y) >= -1e-3;
}
