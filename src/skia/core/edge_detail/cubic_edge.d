module skia.core.edge_detail.cubic_edge;

private {
  import std.algorithm : swap, max, map, reduce;
  import std.array : front, back, save;
  version(unittest) import std.array : appender;
  import std.conv : to;
  import std.math;
  import std.numeric : FPTemporary;

  import skia.core.edge_detail.algo;
  import skia.core.edge_detail.edge;
  import skia.core.edge_detail.line_edge;
  import skia.bezier.chop;
  import guip.rect;
  import guip.point;
  import skia.math.fast_sqrt;
  import skia.math.fixed_ary;

  import skia.util.format;

  debug import std.stdio;
}

// debug=Illinois; // verbose tracing for Illinois algo.

////////////////////////////////////////////////////////////////////////////////

void cubicEdge(R, T)(ref R appender, Point!T[4] pts, const(IRect*) clip=null) {
  if (isLine(pts)) {
    return lineEdge(appender, fixedAry!2(pts.front, pts.back));
  }

  T[2] unitRoots;
  auto nUnitRoots = cubicUnitRoots(pts, unitRoots);
  debug(PRINTF) writefln("1nd pass n:%s roots: %s",
                         nUnitRoots, unitRoots);

  if (nUnitRoots == 0) {
    appendMonoCubic(appender, pts, clip);
  } else if (nUnitRoots == 1) {
    auto ptss = splitBezier(pts, unitRoots[0]);
    appendMonoCubic(appender, ptss[0], clip);
    appendMonoCubic(appender, ptss[1], clip);
  } else {
    assert(nUnitRoots == 2);

    auto ptss = splitBezier(pts, unitRoots[0]);
    appendMonoCubic(appender, ptss[0], clip);
    T sndRoot = (unitRoots[1] - unitRoots[0]) / (1 - unitRoots[0]);

    debug {
      auto numRoots = cubicUnitRoots(ptss[1], unitRoots);
      if (numRoots > 0) {
        debug(PRINTF) writefln("2nd pass n:%s roots: %s orig 2nd root: %s",
                               numRoots, unitRoots, sndRoot);
        assert(approxEqual(unitRoots[numRoots - 1], sndRoot));
      } else {
        assert(abs(sndRoot - 1) < 5e-4);
      }
    }
    ptss = splitBezier(ptss[1], sndRoot);
    appendMonoCubic(appender, ptss[0], clip);
    appendMonoCubic(appender, ptss[1], clip);
  }
}

void clippedCubicEdge(R, T)(ref R appender, Point!T[4] pts, in IRect clip) {
  cubicEdge(appender, pts, &clip);
}

package:

struct CubicEdge(T) {
  @property string toString() const {
    return "CubicEdge!" ~ to!string(typeid(T)) ~
      " pts: " ~ to!string(this.pts) ~
      " oldT: " ~ to!string(oldT);
  }

  this(Point!T[4] pts) {
    fixRoundingErrors(pts);
    assert(pts[0].y <= pts[1].y && pts[2].y <= pts[3].y);
    this.pts = pts;
    this.oldT = 0.0;
  }
  Point!T[4] pts;
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
  FPTemporary!T ya = calcBezier!("y")(pthis.cubic.pts, a) - y;
  if (ya > -1e-5) {
    assert(ya < Edge!T.tol, "tolerance " ~ to!string(ya));
    return pthis.curX;
  }

  auto slope = calcBezierDerivative!("y")(pthis.cubic.pts, pthis.cubic.oldT);
  assert(slope >= 0);

  T b = 1.0;
  if (slope > 1e-3) {
    b = min(1.0, pthis.cubic.oldT + 1.5 * Step / slope);
  }
  FPTemporary!T yb = calcBezier!("y")(pthis.cubic.pts, b) - y;
  auto t = updateCubicImpl!(T)(pthis.cubic.pts, y, a, ya, b, yb);
  pthis.cubic.oldT = t;
  pthis.curX = calcBezier!("x")(pthis.cubic.pts, t);
  return pthis.curX;
}

/**
 * Will update the cubic bezier to the next y position.  Called
 * by the scan converter. Sequential calls must increment their y
 * parameter. Returns the x position.
 */
T updateCubic(T)(ref Edge!T pthis, T y) {
  auto t = getTCubic(pthis, y);
  pthis.curX = calcBezier!("x")(pthis.cubic.pts, t);
  return pthis.curX;
}

T getTCubic(T)(ref Edge!T pthis, T y) {
  assert(pthis.type == EdgeType.Cubic);
  auto a = pthis.cubic.oldT;
  FPTemporary!T ya = calcBezier!("y")(pthis.cubic.pts, a) - y;
  if (ya > -1e-5) {
    assert(ya < Edge!T.tol);
    return pthis.curX;
  }

  assert(ya <= 0 && ya < y,
         fmtString("ya over zero ya:%.7f a:%.7f", ya, a));

  T b = 1.0;
  FPTemporary!T yb = calcBezier!("y")(pthis.cubic.pts, b) - y;
  auto newT =updateCubicImpl!(T)(pthis.cubic.pts, y, a, ya, b, yb);
  pthis.cubic.oldT = newT;
  return newT;
}

T getTCubic(T)(in Point!T[4] pts, T y) {
  T a = 0;
  FPTemporary!T ya = calcBezier!("y")(pts, a) - y;
  T b = 1.0;
  FPTemporary!T yb = calcBezier!("y")(pts, b) - y;
  return updateCubicImpl!(T)(pts, y, a, ya, b, yb);
}

private:

// TODO: have a look at std.numeric.findRoot, does it apply to this
// problem, is it even a better numerical approach?
T updateCubicImpl(T)(ref Point!T[4] pts, T y, T a, FPTemporary!T ya,
                     T b, FPTemporary!T yb) {
  debug(Illinois) writeln("updateCubicImpl:", "y ", y,
                        " a ", a, " ya ", ya,
                        " b " , b, " yb ", yb);
  assert(0<= a && a <= 1.0);
  assert(0<= b && b <= 1.0);

  if (yb < 0) {
    assert(b <= 1.0);
    b = 1.0;
    yb = calcBezier!("y")(pts, b) - y;
    assert(yb >= ya);
  }
  assert(yb > 0);
  assert(ya < 0);
  debug(Illinois) int i;
  FPTemporary!T gamma = 1.0;
  while (true) {
    debug(Illinois) i += 1;
    FPTemporary!T c = (gamma*b*ya - a*yb) / (gamma*ya - yb);
    FPTemporary!T yc = calcBezier!("y")(pts, c) - y;
    debug(Illinois) writeln("illinois step: ", i,
                          " a: ", a, " ya: ", ya,
                          " b: ", b, " yb: ", yb,
                          " c: ", c, " yc: ", yc);
    if (abs(yc) < Edge!T.tol) {
      debug(Illinois) writeln("converged after: ", i,
                              " at: ", c);
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
        //gamma = yb / (yb + yc);
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
           fmtString("failed pts: %s diff: %s tol: %s",
                          pts, pts[2].y - pts[3].y, tol));
    swap(pts[2].y, pts[3].y);
  }
  if (pts[0].y > pts[1].y) {
    assert(pts[0].y - pts[1].y <= tol,
           fmtString("failed pts: %s diff: %s tol: %s",
                        pts, pts[0].y - pts[1].y, tol));
    swap(pts[1].y, pts[0].y);
  }
}

/**
 * Constructs a quad bezier, checks for clip bounds and appends a
 * quad starting a clip.top.
 */
void appendMonoCubic(R, T)(ref R appender, Point!T[4] pts, const(IRect*) clip=null) {
  auto w = sortPoints(pts);

  if (!clip || clipPoints(pts, *clip))
    appender.put(makeCubic(pts, w));
}

bool clipPoints(T)(ref Point!T[4] pts, in IRect clip) {
  assert(pts.front.y <= pts.back.y);
  if (pts.front.y >= clip.bottom || pts.back.y <= clip.top)
    return false;

  // clip the line to top
  if (pts.front.y < clip.top) {
    auto t = getTCubic(pts, cast(T)clip.top);
    auto ptss = splitBezier(pts, t);
    pts = ptss[1];

    //! avoid rounding errors;
    pts[0].y = clip.top;
  }
  return true;
}

Edge!T makeCubic(T)(in Point!T[4] pts, byte winding) {
  if (isLine(pts)) {
    return makeLine(fixedAry!2(pts[0], pts[3]), winding);
  }

  auto res = Edge!T(pts.front.x, pts.back.y);
  res.winding = winding;
  res.type = EdgeType.Cubic;
  res.cubic = CubicEdge!T(pts);
  return res;
}

/** Cubic'(t) = At^2 + Bt + C, where
    A = 3(-a + 3(b - c) + d)
    B = 6(a - 2b + c)
    C = 3(b - a)
*/
T[3] cubicDerivateCoeffs(T)(in Point!T[4] pts) {
  T[3] coeffs;
  coeffs[0] = pts[3].y - pts[0].y + 3*(pts[1].y - pts[2].y);
  coeffs[1] = 2*(pts[0].y - 2*pts[1].y + pts[2].y);
  coeffs[2] = pts[1].y - pts[0].y;
  return coeffs;
}


/**
 * Find roots of the derivative dy(t)/dt, keeping only those that fit
 * between 0 < t < 1.
 */
int cubicUnitRoots(T)(in Point!T[4] pts, out T[2] unitRoots) {
  // we divide A,B,C by 3 to simplify
  return quadUnitRoots(cubicDerivateCoeffs(pts), unitRoots);
}

unittest {
  auto app = appender!(Edge!float[])();
  cubicEdge(app, fixedAry!4(FPoint(362.992, 383.095),
                             FPoint(365.64, 352.835),
                             FPoint(370.016, 328.499),
                             FPoint(372.767, 328.74)));
  auto edge1 = app.data[0];
  auto edge2 = app.data[1];


  auto slope1 = calcBezierDerivative!("y")(edge1.cubic.pts, 0.0f);
  auto slope2 = calcBezierDerivative!("y")(edge2.cubic.pts, 0.0f);
  assert(slope1 >= 0);
  assert(slope2 >= 0);
}
