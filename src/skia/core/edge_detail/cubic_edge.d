module skia.core.edge_detail.cubic_edge;

private {
  import std.algorithm : swap, max, map, reduce;
  import std.array : front, back, save;
  version(unittest) import std.array : appender;
  import std.conv : to;
  import std.math : isNaN;

  import skia.core.edge_detail.algo;
  import skia.core.edge_detail.edge;
  import skia.core.edge_detail.line_edge;
  import skia.core.rect;
  import skia.core.point;
  import skia.math.fast_sqrt;
}

////////////////////////////////////////////////////////////////////////////////

 void cubicEdge(R, T)(ref R appender, in Point!T[] pts, const(IRect*) clip=null) {
  assert(pts.length == 4);

  if (isLine(pts)) {
    return lineEdge(appender, [pts.front, pts.back]);
  }

  T[2] unitRoots;
  auto nUnitRoots = cubicUnitRoots(pts, unitRoots);
  debug(PRINTF) writefln("1nd pass n:%s roots: %s",
                         nUnitRoots, unitRoots);

  if (nUnitRoots == 0) {
    appendMonoCubic(appender, pts, clip);
  } else if (nUnitRoots == 1) {
    auto ptss = splitBezier!4(pts, unitRoots[0]);
    appendMonoCubic(appender, ptss[0], clip);
    appendMonoCubic(appender, ptss[1], clip);
  } else {
    assert(nUnitRoots == 2);

    auto ptss = splitBezier!4(pts, unitRoots[0]);
    appendMonoCubic(appender, ptss[0], clip);
    T sndRoot = (unitRoots[1] - unitRoots[0]) / (1 - unitRoots[0]);

    debug {
      auto numRoots = cubicUnitRoots(ptss[1], unitRoots);
      if (numRoots > 0) {
        debug(PRINTF) writefln("2nd pass n:%s roots: %s orig 2nd root: %s",
                               numRoots, unitRoots, sndRoot);
        assert(abs(unitRoots[numRoots - 1] - sndRoot) < 1e-3);
      } else {
        assert(abs(sndRoot - 1) < 5e-4);
      }
    }
    ptss = splitBezier!4(ptss[1], sndRoot);
    appendMonoCubic(appender, ptss[0], clip);
    appendMonoCubic(appender, ptss[1], clip);
  }
}

void clippedCubicEdge(R, T)(ref R appender, in Point!T[] pts, in IRect clip) {
  cubicEdge(appender, pts, &clip);
}

package:

struct CubicEdge(T) {
  @property string toString() const {
    return "CubicEdge!" ~ to!string(typeid(T)) ~
      " p1: " ~ to!string(p1) ~
      " p2: " ~ to!string(p2) ~
      " p3: " ~ to!string(p3) ~
      " oldT: " ~ to!string(oldT);
  }

  this(Point!T p0, Point!T p1, Point!T p2, Point!T p3) {
    Point!T[4] pts = [p0, p1, p2, p3];
    fixRoundingErrors(pts);
    assert(pts[0].y <= pts[1].y && pts[2].y <= pts[3].y);
    // TODO: store coefficients rather than points.
    this.p1 = pts[1];
    this.p2 = pts[2];
    this.p3 = pts[3];
    this.oldT = 0.0;
  }
  Point!T p1;
  Point!T p2;
  Point!T p3;
  T oldT;
};

/**
 * Same as above but allows to provide a template step parameter
 * used for initial guessing of starting values.
 */
T updateCubic(T)(ref Edge!T pthis, T y, T Step){
  assert(Step > 0);
  assert(pthis.type == EdgeType.Cubic);
  auto a = pthis.cubic.oldT;
  auto ya = calcTCubic!("y")(pthis, a) - y;
  if (ya > -1e-5) {
    assert(ya < Edge!T.tol, "tolerance " ~ to!string(ya));
    return pthis.curX;
  }

  auto slope = cubicDerivate(
    [pthis.p0, pthis.cubic.p1, pthis.cubic.p2, pthis.cubic.p3],
    pthis.cubic.oldT);
  assert(slope >= 0);

  T b = 1.0;
  if (slope > 1e-3) {
    b = min(1.0, pthis.cubic.oldT + 1.5 * Step / slope);
  }
  auto yb = calcTCubic!("y")(pthis, b) - y;
  auto t = updateCubicImpl(pthis, y, a, ya, b, yb);
  pthis.curX = calcTCubic!("x")(pthis, t);
  return pthis.curX;
}

/**
 * Will update the cubic bezier to the next y position.  Called
 * by the scan converter. Sequential calls must increment their y
 * parameter. Returns the x position.
 */
T updateCubic(T)(ref Edge!T pthis, T y) {
  auto t = getTCubic(pthis, y);
  pthis.curX = calcTCubic!("x")(pthis, t);
  return pthis.curX;
}

T getTCubic(T)(ref Edge!T pthis, T y) {
  assert(pthis.type == EdgeType.Cubic);
  auto a = pthis.cubic.oldT;
  auto ya = calcTCubic!("y")(pthis, a) - y;
  if (ya > -1e-5) {
    assert(ya < Edge!T.tol);
    return pthis.curX;
  }

  assert(ya <= 0 && ya < y,
         formatString("ya over zero ya:%.7f a:%.7f", ya, a));

  T b = 1.0;
  auto yb = calcTCubic!("y")(pthis, b) - y - y;
  return updateCubicImpl(pthis, y, a, ya, b, yb);
}

T calcTCubic(string v, T)(in Edge!T pthis, T t) {
  assert(pthis.type == EdgeType.Cubic);
  auto mt = 1 - t;
  auto v0 = mixin("pthis.p0."~v);
  auto v1 = mixin("pthis.cubic.p1."~v);
  auto v2 = mixin("pthis.cubic.p2."~v);
  auto v3 = mixin("pthis.cubic.p3."~v);
  return mt*mt*mt*v0 + 3*t*mt*mt*v1 + 3*t*t*mt*v2 + t*t*t*v3;
}

private:

// TODO: have a look at std.numeric.findRoot, does it apply to this
// problem, is it even a better numerical approach?
T updateCubicImpl(T)(ref Edge!T pthis, T y, T a, T ya, T b, T yb) {
  debug(Illinois) writeln("updateCubicImpl:", "y ", y,
                        " a ", a, " ya ", ya,
                        " b " , b, " yb ", yb);
  assert(0<= a && a <= 1.0);
  assert(0<= b && b <= 1.0);

  if (yb < 0) {
    assert(b <= 1.0);
    b = 1.0;
    yb = calcTCubic!("y")(pthis, b) - y;
    assert(yb >= ya);
  }
  assert(yb > 0);
  assert(ya < 0);
  debug(Illinois) int i;
  T gamma = 1.0;
  for (;;) {
    debug(Illinois) i += 1;
    auto c = (gamma*b*ya - a*yb) / (gamma*ya - yb);
    auto yc = calcTCubic!("y")(pthis, c) - y;
    debug(Illinois) writeln("illinois step: ", i,
                          " a: ", a, " ya: ", ya,
                          " b: ", b, " yb: ", yb,
                          " c: ", c, " yc: ", yc);
    if (abs(yc) < Edge!T.tol) {
      pthis.cubic.oldT = c;
      debug(Illinois) writeln("converged after: ", i,
                              " at: ", pthis.cubic.oldT);
      return c;
    }
    else {
      if (yc * yb < 0) {
        a = b;
        ya = yb;
        gamma = 1.0;
      }
      else {
        gamma = 0.5;
      }
      b = c;
      yb = yc;
    }
  }
}

/**
 * This fixes rounding error that get quite big due to the usage of
 * rsqrt. The bezier is not splitted at the exact roots of the cubic
 * derivative and the monotonic assumption breaks. Should this error
 * grow to big, sqrt could be used again.
 */
void fixRoundingErrors(T)(ref Point!T[4] pts) {
  //! TODO deactivate tests in release
  auto tol = 1e-2 * reduce!(max)(
    map!("a.y < 0 ? -a.y : a.y")(pts.save));

  if (pts[2].y > pts[3].y) {
    assert(pts[2].y - pts[3].y <= tol,
           formatString("failed pts: %s diff: %s tol: %s",
                          pts, pts[2].y - pts[3].y, tol));
    swap(pts[2].y, pts[3].y);
  }
  if (pts[0].y > pts[1].y) {
    assert(pts[0].y - pts[1].y <= tol,
           formatString("failed pts: %s diff: %s tol: %s",
                        pts, pts[0].y - pts[1].y, tol));
    swap(pts[1].y, pts[0].y);
  }
}

/**
 * Constructs a quad bezier, checks for clip bounds and appends a
 * quad starting a clip.top.
 */
void appendMonoCubic(R, T)(ref R appender, in Point!T[] pts, const(IRect*) clip=null) {
  auto edge = makeCubic(pts);

  if (!(clip is null)) {
    if (edge.firstY > clip.bottom || edge.lastY < clip.top)
      return;

    // clip the quad to top
    if (edge.firstY < clip.top) {
      auto t = getTCubic(edge, cast(T)clip.top);
      auto ptss =
        splitBezier!4([edge.p0, edge.cubic.p1, edge.cubic.p2, edge.cubic.p3], t);
      auto winding = edge.winding;
      edge = makeCubic(ptss[1]);
      edge.winding = winding;
    }
  }

  appender.put(edge);
}

Edge!T makeCubic(T)(in Point!T[] pts) {
  assert(pts.length == 4);

  if (isLine(pts))
    makeLine([pts[0], pts[3]]);

  auto topI = pts[0].y > pts[3].y ? 3 : 0;
  auto botI = 3 - topI;
  auto ttopI = topI > botI ? 2 : 1;
  auto bbotI = topI > botI ? 1 : 2;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = EdgeType.Cubic;
  res.cubic = CubicEdge!T(pts[topI], pts[ttopI], pts[bbotI], pts[botI]);
  return res;
}

/** Cubic'(t) = At^2 + Bt + C, where
    A = 3(-a + 3(b - c) + d)
    B = 6(a - 2b + c)
    C = 3(b - a)
*/
T[3] cubicDerivateCoeffs(T)(in Point!T[] pts) {
  assert(pts.length == 4);
  T[3] coeffs;
  coeffs[0] = pts[3].y - pts[0].y + 3*(pts[1].y - pts[2].y);
  coeffs[1] = 2*(pts[0].y - 2*pts[1].y + pts[2].y);
  coeffs[2] = pts[1].y - pts[0].y;
  return coeffs;
}

T cubicDerivate(T)(in Point!T[] pts, T t) {
  auto coeffs = cubicDerivateCoeffs(pts);
  return 3*(t*t*coeffs[0] + t*coeffs[1] + coeffs[2]);
}

/**
 * Find roots of the derivative dy(t)/dt, keeping only those that fit
 * between 0 < t < 1.
 */
int cubicUnitRoots(T)(in Point!T[] pts, out T[2] unitRoots) {
  // we divide A,B,C by 3 to simplify
  return quadUnitRoots(cubicDerivateCoeffs(pts), unitRoots);
}

unittest {
  auto app = appender!(Edge!float[])();
  cubicEdge(app, [FPoint(362.992, 383.095),
                  FPoint(365.64, 352.835),
                  FPoint(370.016, 328.499),
                  FPoint(372.767, 328.74)]);
  auto edge1 = app.data[0];
  auto edge2 = app.data[1];

  auto slope1 = cubicDerivate(
    [edge1.p0, edge1.cubic.p1, edge1.cubic.p2, edge1.cubic.p3],
    0.0f);
  auto slope2 = cubicDerivate(
    [edge2.p0, edge2.cubic.p1, edge2.cubic.p2, edge2.cubic.p3],
    0.0f);
  assert(slope1 >= 0);
  assert(slope2 >= 0);
}
