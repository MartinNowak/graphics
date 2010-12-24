module skia.core.edge_detail.quad_edge;

private {
  import std.array : front, back;
  import std.conv : to;

  import skia.core.edge_detail.algo;
  import skia.core.edge_detail.edge;
  import skia.core.edge_detail.line_edge;
  import skia.core.point;
}

//debug=QUAD;

void quadraticEdge(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 3);

  if (isLine(pts)) {
    return lineEdge(appender, [pts.front, pts.back]);
  }

  if (monotonicY(pts)) {
    appender.put(makeQuad(pts));
  } else {
    appendSplittedQuad(appender, pts);
  }
}

package:

struct QuadraticEdge(T) {
  @property string toString() const {
    auto msg = "QuadraticEdge!" ~ to!string(typeid(T)) ~
      " a, b, c: " ~ to!string(this.coeffs);
    debug(QUAD) {
      msg ~= " p1: " ~ to!string(this.p1) ~
        " p2: " ~ to!string(this.p2);
    }
    return msg;
  }
  this(Point!T p0, Point!T p1, Point!T p2) {
    this.coeffs[0] = p0.y - 2*p1.y + p2.y;
    this.coeffs[1] = (-2*p0.y + 2*p1.y);
    this.coeffs[2] = p0.y;
    this.x0 = p0.x;
    this.x1 = p1.x;
    this.x2 = p2.x;
    debug(QUAD) {
      this.p1 = p1;
      this.p2 = p2;
    }
  }
  T[3] coeffs;
  T x0, x1, x2;
  debug(QUAD) {
    Point!T p1, p2;
  }
};


T updateQuad(T)(ref Edge!T pthis, T y) {
  assert(pthis.type == EdgeType.Quad);

  auto t = getTQuad(pthis, y);
  pthis.curX = calcTQuad!("x")(pthis, t);
  return pthis.curX;
}

T getTQuad(T)(ref Edge!T pthis, T y) {
  if (y >= pthis.lastY)
    return 1.0;
  if (y <= pthis.firstY)
    return 0.0;

  T[2] roots;
  auto coeffs = pthis.quad.coeffs;
  coeffs[2] -= y;
  auto nRoots = quadUnitRoots(coeffs, roots);
  assert(nRoots == 1, formatString("y:%.7f coeffs:%s roots:%s",
                                   y, coeffs, roots));
  auto t = roots[0];
  debug (QUAD) {
    auto revY = calcTQuad!("y")(t);
    //      assert(abs(y - revY) < abs(y) * 10 * Edge!T.tol,
    //       formatString("t:%s y:%s revY:%s edge:%s", t, y, revY, this));
  }
  return t;
}

T calcTQuad(string v, T)(in Edge!T pthis, T t) {
  assert(pthis.type == EdgeType.Quad);
  static if (v == "y") {
    debug (QUAD) {
      auto mt = 1 - t;
      return mt*mt*pthis.p0.y + 2*t*mt*pthis.quad.p1.y + t*t*pthis.quad.p2.y;
    }
    auto a = pthis.quad.coeffs[0];
    auto b = pthis.quad.coeffs[1];
    auto c = pthis.quad.coeffs[2];
    return t*t*a + t*b + c;
  } else {
    auto oneMt = 1 - t;
    return oneMt*oneMt*pthis.quad.x0 + 2*oneMt*t*pthis.quad.x1 + t*t*pthis.quad.x2;
  }
}


private:

/**
 * Given the parametric eq.:
 * y(t) = (1-t)^2*y0 + 2*t*(1-t)*y1 + t^2*y2
 * the derivative is:
 * dy/dt = 2*t(y0-2y1+y2) + 2*(y1-y0)
 * Finding t at the extremum
 */
void appendSplittedQuad(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 3);
  T denom = pts[0].y - 2*pts[1].y + pts[2].y;
  T numer = pts[0].y - pts[1].y;
  T tValue;
  if (valid_unit_divide(numer, denom, tValue)) {
    auto ptss = splitBezier!3(pts, tValue);
    appender.put(makeQuad(ptss[0]));
    appender.put(makeQuad(ptss[1]));
  } else {
    //! Force monotonic
    Point!T[3] forced = pts[0 .. 3];
    // set middle y to the closest y of border points
    forced[1].y = abs(pts[0].y - pts[1].y) < abs(pts[2].y - pts[1].y)
      ? pts[0].y
      : pts[2].y;

    appender.put(makeQuad(forced));
  }
}

unittest {
  FPoint[3] pts = [FPoint(3.12613, 0.230524),
                   FPoint(4.67817, 2.7919),
                   FPoint(4.38304, 0.389878)];
  auto app = appender!(Edge!float[])();
  quadraticEdge(app, pts);
  assert(app.data.length == 2);
}

Edge!T makeQuad(T)(in Point!T[] pts) {
  assert(pts.length == 3);

  if (isLine(pts))
    return makeLine([pts[0], pts[2]]);

  auto topI = pts[0].y > pts[2].y ? 2 : 0;
  auto botI = 2 - topI;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = EdgeType.Quad;
  res.quad = QuadraticEdge!T(pts[topI], pts[1], pts[botI]);
  return res;
}

// TODO: move this part into skia.core.geometry
bool monotonicY(T)(in Point!T[] pts) {
  return (pts[0].y - pts[1].y) * (pts[1].y - pts[2].y) > 0;
}
