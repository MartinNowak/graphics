module skia.core.edgebuilder;

private {
  import std.algorithm : map, min, sort, swap;
  import std.array : appender, array, back, front;
  import std.math : isNaN, abs, sqrt;
  import std.traits : isFloatingPoint;

  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
}

//debug=PRINTF;
//debug=Illinois; // verbose tracing for Illinois algo.

alias Edge!float FEdge;
struct Edge(T) if (isFloatingPoint!T) {
private:
  Point!T p0;
  T _curX;
  T _lastY;

  static if (T.dig > 7) {
    enum tol = 1e-4;
  }
  else {
    static assert(T.dig == 6);
    enum tol = 1e-3;
  }

  union {
    LineEdge!T line;
    QuadraticEdge!T quad;
    CubicEdge!T cubic;
  }
  enum Type : byte { Line, Quad, Cubic }
  Type type;
  byte _winding;       // 1 or -1

public:

  this(Point!T p0, T lastY) {
    this.p0 = p0;
    this.curX = p0.x;
    this.lastY = lastY;
  }

  @property T curX() const {
    return this._curX;
  }
  @property private void curX(T val) {
    return this._curX = val;
  }
  @property T firstY() const {
    return this.p0.y;
  }
  @property T lastY() const {
    return this._lastY;
  }
  @property private void lastY(T val) {
    return this._lastY = val;
  }
  @property byte winding() const {
    return this._winding;
  }
  @property private void winding(byte w) {
    return this._winding = w;
  }

  @property string toString() const {
    version(VERBOSE) {
      return "{Edge!"~ to!string(typeid(T)) ~
      " | p0: " ~ to!string(this.p0) ~
      " | curX: " ~ to!string(this.curX) ~
      " | lastY: " ~ to!string(this.lastY) ~
      " | winding: " ~ to!string(this.winding) ~
      " | typeImpl: " ~ this.implString() ~ "}\n";
    }
    else {
      return this.typeString() ~ " cX:" ~ to!string(this.curX) ~
        " yB:" ~ to!string(this.firstY) ~
        " yE:" ~ to!string(this.lastY);
    }
  }

  string typeString() const {
    final switch(this.type) {
    case Type.Line: return "Line";
    case Type.Quad: return "Quad";
    case Type.Cubic: return "Cubic";
    }
  }
  string implString() const {
    final switch(this.type) {
    case Type.Line: return to!string(this.line);
    case Type.Quad: return to!string(this.quad);
    case Type.Cubic: return to!string(this.cubic);
    }
  }
  bool intersectsClip(in IRect clip) const {
    assert(this.p0.y < clip.bottom);
    return this.lastY >= clip.top;
  }

  /**
   * Advances the edge state to the y pos. Multiple calls to this
   * function must increase the y paremeter.  Returns the x pos.
   * Optional yInc parameter which allows a more efficient
   * calculation, especially for cubic edges.
   */
  T updateEdge(T y, T yInc=0) {
    assert(yInc > 0);
    final switch(this.type) {
    case Type.Line:
      return this.updateLine(y);
    case Type.Quad:
      return this.updateQuad(y);
    case Type.Cubic:
      return yInc == 0
        ? this.updateCubic(y)
        : this.updateCubic(y, yInc);
    }
  }

  T updateLine(T y) {
    this.curX = this.p0.x + (y - this.p0.y) * this.line.dx;
    return this.curX;
  }

  T updateQuad(T y) {
    assert(this.type == Type.Quad);
    auto pmSqrt = this.quad.fixSqrt + y * this.quad.scale;
    pmSqrt = fast_sqrt(pmSqrt);
    auto t = this.quad.fixAdd + this.quad.addSub ? pmSqrt : -pmSqrt;
    this.curX = this.quadraticCalcX(t);
    return this.curX;
  }
  T quadraticCalcX(T t) {
    assert(this.type == Type.Quad);
    auto oneMt = 1 - t;
    return oneMt*oneMt * this.quad.x0
      + 2*t*oneMt * this.quad.x1
      + t*t * this.quad.x2;
  }

  /**
   * Will update the cubic bezier to the next y position.  Called
   * by the scan converter. Sequential calls must increment their y
   * parameter. Returns the x position.
   */
  T updateCubic(T y) {
    assert(this.type == Type.Cubic);
    auto a = this.cubic.oldT;
    auto ya = cubicCalc!"y"(a) - y;
    assert(ya <= 0);
    if (ya > -tol)
      return this.curX;

    assert(ya < y);

    auto b = 1.0;
    auto yb = cubicCalc!"y"(b) - y - y;
    this.curX = updateCubicImpl(y, a, ya, b, yb);
    return this.curX;
  }

  /**
   * Same as above but allows to provide a template step parameter
   * used for initial guessing of starting values.
   */
  T updateCubic(T y, T Step){
    assert(Step > 0);
    assert(this.type == Type.Cubic);
    auto a = this.cubic.oldT;
    auto ya = cubicCalc!"y"(a) - y;
    assert(ya <= 0);
    if (ya > -tol)
      return this.curX;

    auto slope = cubicDerivate(
      [this.p0, this.cubic.p1, this.cubic.p2, this.cubic.p3],
      this.cubic.oldT);
    assert(slope >= 0);
    T b = 1.0;
    if (slope > 1e-3) {
      b = min(1.0, this.cubic.oldT + 1.5 * Step / slope);
    }
    auto yb = cubicCalc!"y"(b) - y;
    this.curX = updateCubicImpl(y, a, ya, b, yb);
    return this.curX;
  }

  // TODO: have a look at std.numeric.findRoot, does it apply to this
  // problem, is it even a better numerical approach?
  T updateCubicImpl(T y, T a, T ya, T b, T yb) {
    debug(Illinois) writeln("updateCubicImpl:", "y ", y,
                          " a ", a, " ya ", ya,
                          " b " , b, " yb ", yb);
    assert(0<= a && a <= 1.0);
    assert(0<= b && b <= 1.0);

    if (yb < 0) {
      assert(b < 1.0);
      b = 1.0;
      yb = cubicCalc!"y"(b) - y;
      assert(yb >= ya);
    }
    assert(yb > 0);
    assert(ya < 0);
    debug(Illinois) int i;
    T gamma = 1.0;
    for (;;) {
      debug(Illinois) i += 1;
      auto c = (gamma*b*ya - a*yb) / (gamma*ya - yb);
      auto yc = cubicCalc!"y"(c) - y;
      debug(Illinois) writeln("illinois step: ", i,
                            " a: ", a, " ya: ", ya,
                            " b: ", b, " yb: ", yb,
                            " c: ", c, " yc: ", yc);
      if (abs(yc) < tol) {
        this.cubic.oldT = c;
        debug(Illinois) writeln("converged after: ", i,
                                " at: ", this.cubic.oldT);
        return cubicCalc!"x"(c);
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


  T cubicCalc(string v)(T t)
    if (v == "x" || v == "y")
  {
    assert(this.type == Type.Cubic);
    auto mt = 1 - t;
    auto v0 = mixin("this.p0."~v);
    auto v1 = mixin("this.cubic.p1."~v);
    auto v2 = mixin("this.cubic.p2."~v);
    auto v3 = mixin("this.cubic.p3."~v);
    return mt*mt*mt*v0 + 3*t*mt*mt*v1 + 3*t*t*mt*v2 + t*t*t*v3;
  }
}

unittest {
  auto app = appender!(FEdge[])();
  cubicEdge(app, [FPoint(0.0, 0.0), FPoint(1.0, 1.0),
                  FPoint(2.0, 4.0), FPoint(4.0, 16.0)]);
  assert(app.data.length == 1);
  auto cub = app.data[0];
  assert(cub.type == FEdge.Type.Cubic);

  auto val = cub.updateCubic(0.0, 0.01); assert(val == 0.0);
  val = cub.updateCubic(1.0, 1.0);
  assert(abs(val - 0.659) < 1e-3);
  val = cub.updateCubic(1.2, 0.2);
  val = cub.updateCubic(2.0, 0.8);
  assert(abs(val - 1.063) < 1e-3);
  val = cub.updateCubic(4.0, 2.0);
  assert(abs(val - 1.658) < 1e-3);
}


////////////////////////////////////////////////////////////////////////////////

version(NO_SSE) {
  float fast_sqrt(float n) {
    return sqrt(n);
  }
} else {
  float fast_sqrt(float n)
  {
    assert(n >= 0);

    if (n == 0)
      return 0;

    asm {
      rsqrtss XMM0, n;
      mulss XMM0, n;
      movss n, XMM0;
    }

    return n;
  }
}

unittest {
  real errorSum = 0.0;
  size_t j;
  for (float i = 1.0/1000; i<=1000; i+=1.0/1000, ++j) {
    auto dev = fast_sqrt(i) - sqrt(i);
    errorSum += dev * dev;
  }
  auto error = sqrt(errorSum / j);
  assert(error < 3e-3);
}

struct LineEdge(T) {
  @property string toString() const {
    return "LineEdge!" ~ to!string(typeid(T)) ~
      " dx: " ~ to!string(dx);
  }
  this(FPoint p0, FPoint p1) {
    assert(p1.y >= p0.y);
    this.dx = (p1.x - p0.x) / (p1.y - p0.y);
  }
  T dx;
}

struct QuadraticEdge(T) {
  @property string toString() const {
    return "QuadraticEdge!" ~ to!string(typeid(T)) ~
      " scale: " ~ to!string(scale) ~
      " fixSqrt: " ~ to!string(fixSqrt) ~
      " fixAdd: " ~ to!string(fixAdd);
  }
  this(Point!T p0, Point!T p1, Point!T p2) {
    auto a = p0.y - 2*p1.y + p2.y;
    assert(abs(a) > 1e-7);
    this.scale = 1 / a;
    auto p = (-2*p0.y + 2*p1.y) * this.scale;
    auto q = p0.y * this.scale;
    this.fixAdd = -p * 0.5;
    this.fixSqrt = (p * p * 0.25) - q;
    this.x0 = p0.x;
    this.x1 = p1.x;
    this.x2 = p2.x;
    this.addSub = a >= 0;
  }
  T x0, x1, x2;
  T scale;
  T fixAdd;
  T fixSqrt;
  bool addSub;
};

struct CubicEdge(T) {
  @property string toString() const {
    return "CubicEdge!" ~ to!string(typeid(T)) ~
      " p1: " ~ to!string(p1) ~
      " p2: " ~ to!string(p2) ~
      " p3: " ~ to!string(p3) ~
      " oldT: " ~ to!string(oldT);
  }
  this(Point!T p0, Point!T p1, Point!T p2, Point!T p3) {
    this.p1 = p1;
    this.p2 = p2;
    this.p3 = p3;
    this.oldT = 0.0;
  }
  Point!T p1;
  Point!T p2;
  Point!T p3;
  T oldT;
};


////////////////////////////////////////////////////////////////////////////////

// TODO: pass in clip rect
void lineEdge(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 2);
  auto topI = pts[0].y > pts[1].y ? 1 : 0;
  auto botI = 1 - topI;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = Edge!T.Type.Line;
  res.line = LineEdge!T(pts[topI], pts[botI]);
  appender.put(res);
}

bool isLine(T)(in Point!T[] pts) {
  if (pts.length < 2)
    return false;
  auto refVec = pts[$-1] - pts[0];
  foreach(pt; pts[1..$-1]) {
    if (abs(crossProduct(refVec, pt)) > Edge!T.tol) {
      return false;
    }
  }
  return true;
}

////////////////////////////////////////////////////////////////////////////////

// Edge quadraticEdge(in IPoint[] pts, in IRect clip);
void quadraticEdge(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 3);

  if (isLine(pts)) {
    return lineEdge(appender, [pts.front, pts.back]);
  }

  if (monotonicY(pts)) {
    appender.put(makeQuad(pts));
  }
  else {
    auto ptss = splitIntoMonotonicQuads(pts);
    auto edges = map!makeQuad(ptss);
    foreach(edge ;edges) {
      appender.put(edge);
    }
  }
}

Edge!T makeQuad(T)(in Point!T[] pts) {
  assert(pts.length == 3);
  auto topI = pts[0].y > pts[2].y ? 2 : 0;
  auto botI = 2 - topI;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = FEdge.Type.Quad;
  res.quad = QuadraticEdge!T(pts[topI], pts[1], pts[botI]);
  return res;
}

// TODO: move this part into skia.core.geometry
bool monotonicY(in FPoint[] pts) {
  return (pts[0].y - pts[1].y) * (pts[1].y - pts[2].y) > 0;
}

int valid_unit_divide(T)(T numer, T denom, out T ratio) {
  if (numer * denom <= 0) {
    return 0;
  }

  T r = numer / denom;
  assert(r >= 0);
  if (r == 0 || r >= 1) {
    return 0;
  }
  static if (isFloatingPoint!T) {
    if (isNaN(r)) {
      return 0;
    }
  }
  ratio = r;
  return 1;
}

/**
 * Given the parametric eq.:
 * y(t) = (1-t)^2*y0 + 2*t*(1-t)*y1 + t^2*y2
 * the derivative is:
 * dy/dt = 2*t(y0-2y1+y2) + 2*(y1-y0)
 * Finding t at the extremum
 */
Point!T[3][] splitIntoMonotonicQuads(T)(in Point!T[] pts) {
  assert(pts.length == 3);
  assert(!monotonicY(pts));
  T denom = pts[0].y - 2*pts[1].y + pts[2].y;
  T numer = pts[1].y - pts[0].y;
  T tValue;
  if (valid_unit_divide(numer, denom, tValue)) {
    return splitBezier!3(pts, tValue);
  }
  else {
    return forceMonotonicQuad(pts);
  }
}

Point!T[3][1] forceMonotonicQuad(T)(in Point!T[] pts) {
  Point!T[3][1] result;
  result[0] = pts;

  // set middle y to the closest y of border points
  result[0][1].y = abs(pts[0].y - pts[1].y) < abs(pts[2].y - pts[1].y)
    ? pts[0].y
    : pts[2].y;
  return result;
}


////////////////////////////////////////////////////////////////////////////////

// Edge cubicEdge(in IPoint[] pts, in IRect clip);
void cubicEdge(R, T)(ref R appender, in Point!T[] pts) {
  assert(pts.length == 4);

  if (isLine(pts)) {
    return lineEdge(appender, [pts.front, pts.back]);
  }

  T[2] unitRoots;
  auto nUnitRoots = cubicUnitRoots(pts, unitRoots);
  Point!T[4] right = pts;
  for (auto i = 0; i < nUnitRoots; ++i) {
    auto ptss = splitBezier!4(right, unitRoots[i]);
    appender.put(makeCubic(ptss[0]));
    right = ptss[1];
  }
  appender.put(makeCubic(right));
}

Edge!T makeCubic(T)(in Point!T[] pts) {
  assert(pts.length == 4);
  auto topI = pts[0].y > pts[2].y ? 3 : 0;
  auto botI = 3 - topI;
  auto ttopI = topI > botI ? 2 : 1;
  auto bbotI = topI > botI ? 1 : 2;
  auto res = Edge!T(pts[topI], pts[botI].y);
  res.winding = topI > botI ? 1 : -1;
  res.type = Edge!T.Type.Cubic;
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

int quadUnitRoots(T)(T[3] coeffs, out T[2] roots) {
  auto a = coeffs[0];
  auto b = coeffs[1];
  auto c = coeffs[2];

  auto r = b*b - 4*a*c;
  if (r < 0)
    return 0;
  static if (isFloatingPoint!T) {
    if (isNaN(r))
      return 0;
  }
  r = fast_sqrt(r);
  auto q = b < 0 ? -(b-r)/2 : -(b+r)/2;
  int rootIdx;
  rootIdx += valid_unit_divide(q, a, roots[rootIdx]);
  rootIdx += valid_unit_divide(c, q, roots[rootIdx]);
  if (rootIdx == 2) {
    if (roots[0] > roots[1])
      swap(roots[0], roots[1]);
    if (roots[0] == roots[1])
      rootIdx -= 1;
  }
  return rootIdx;
}

////////////////////////////////////////////////////////////////////////////////

FEdge[] buildEdges(in Path path) {
  auto app = appender!(FEdge[])();
  path.forEach((const Path.Verb verb, const FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        lineEdge(app, pts);
        break;
      case Path.Verb.Quad:
        quadraticEdge(app, pts);
        break;
      case Path.Verb.Cubic:
        cubicEdge(app, pts);
        break;
      }
    });
  return app.data;
}


unittest {
  auto path = Path();
  path.moveTo(point(0.0f, 0.0f));
  path.rLineTo(point(1.0f, 1.0f));
  path.cubicTo(point(3.0f, 2.0f), point(5.0f, 1.0f), point(6.0f, -1.0f));
  auto edges = buildEdges(path);
}

////////////////////////////////////////////////////////////////////////////////

unittest {
  auto app = appender!(FEdge[])();
  lineEdge(app, [FPoint(0,0), FPoint(3,2)]);
  quadraticEdge(app, [FPoint(0,0), FPoint(1,2), FPoint(2,3)]);
  cubicEdge(app, [FPoint(0,0), FPoint(1,1), FPoint(2,2), FPoint(3,3)]);
  cubicEdge(app, [FPoint(0,0), FPoint(1,2), FPoint(2,3), FPoint(3,5)]);
  assert(app.data[0].type == FEdge.Type.Line);
  assert(app.data[1].type == FEdge.Type.Quad);
  assert(app.data[2].type == FEdge.Type.Line);
  assert(app.data[3].type == FEdge.Type.Cubic);
}

////////////////////////////////////////////////////////////////////////////////
/**
 * Split bezier curve with de Castlejau algorithm.
 */
Point!T[K][2] splitBezier(int K, T)(in Point!T[] pts, T tValue) if (K>=2) {
  assert(0 < tValue && tValue < 1);

  T oneMt = 1 - tValue;

  Point!T split(Point!T p0, Point!T p1) {
    return p0 * oneMt + p1 * tValue;
  }

  Point!T[K] left;
  Point!T[K] tmp;
  left[0] = pts[0];
  foreach(i,ref pt; tmp) {
    pt = pts[i];
  }

  int k = K;
  while (--k > 0) {
    for (int i = 0; i < k ; ++i) {
      tmp[i] = split(tmp[i], tmp[i+1]);
    }
    left[K-k] = tmp[0];
  }
  return [left, tmp];
}

unittest {
  auto pts = [point(0.0, 0.0), point(1.0, 1.0)];
  auto split = splitBezier!2(pts, 0.5);
  auto exp = point(0.0, 0.0);
  assert(split[0][0] == exp);
  exp = point(0.5, 0.5);
  assert(split[0][1] == exp);
  assert(split[1][0] == exp);
  exp = point(1.0, 1.0);
  assert(split[1][1] == exp);
}

unittest {
  auto pts = [point(0.0, 0.0), point(2.0, 2.0), point(4.0, 0.0)];
  auto split = splitBezier!3(pts, 0.25);
}
