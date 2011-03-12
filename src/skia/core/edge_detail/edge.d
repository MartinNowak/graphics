module skia.core.edge_detail.edge;

private {
  import std.algorithm : min;
  import std.array : appender;
  import std.traits : isFloatingPoint;

  import skia.core.edge_detail.algo;
  import skia.core.edge_detail.cubic_edge;
  import skia.core.edge_detail.line_edge;
  import skia.core.edge_detail.quad_edge;
  import guip.point;
  import guip.rect;
  import skia.math.fixed_ary;
}

package:

enum EdgeType : byte { Line, Quad, Cubic }

struct Edge(T) if (isFloatingPoint!T) {
  T curX;
  T lastY;
  union {
    // insert the first point in the union, this allows to store fixes Point!T[N] array in the curves.
    Point!T p0;
    LineEdge!T line;
    QuadraticEdge!T quad;
    CubicEdge!T cubic;
  }
  EdgeType type;
  byte winding;       // 1 or -1

  static if (T.dig > 7) {
    enum tol = 1e-4;
  }
  else {
    static assert(T.dig == 6);
    enum tol = 1e-3;
  }

public:

  this(T startX, T lastY) {
    this.curX = startX;
    this.lastY = lastY;
  }

  @property T firstY() const {
    return this.p0.y;
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
    case EdgeType.Line: return "Line";
    case EdgeType.Quad: return "Quad";
    case EdgeType.Cubic: return "Cubic";
    }
  }
  string implString() const {
    final switch(this.type) {
    case EdgeType.Line: return to!string(this.line);
    case EdgeType.Quad: return to!string(this.quad);
    case EdgeType.Cubic: return to!string(this.cubic);
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
    assert(yInc >= 0);
    final switch(this.type) {
    case EdgeType.Line:
      return updateLine(this, y);
    case EdgeType.Quad:
      return updateQuad(this, y);
    case EdgeType.Cubic:
      return yInc == 0
        ? updateCubic(this, y)
        : updateCubic(this, y, yInc);
    }
  }

  T getT()(T y) {
    final switch(this.type) {
    case EdgeType.Line: return getTLine(this, y);
    case EdgeType.Quad: return getTQuad(this.quad.pts, y);
    case EdgeType.Cubic: return getTCubic(this, y);
    }
  }

  T calcT(string v)(T t) if (v == "x" || v == "y") {
    final switch(this.type) {
    case EdgeType.Line: return calcBezier!(v)(this.line.pts, t);
    case EdgeType.Quad: return calcBezier!(v)(this.quad.pts, t);
    case EdgeType.Cubic: return calcBezier!(v)(this.cubic.pts, t);
    }
  }
}

unittest {
  auto app = appender!(Edge!float[])();
  lineEdge(app, fixedAry!2(FPoint(0,0), FPoint(3,2)));
  quadraticEdge(app, fixedAry!3(FPoint(0,0), FPoint(1,2), FPoint(2,3)));
  cubicEdge(app, fixedAry!4(FPoint(0,0), FPoint(1,1), FPoint(2,2), FPoint(3,3)));
  cubicEdge(app, fixedAry!4(FPoint(0,0), FPoint(1,2), FPoint(2,3), FPoint(3,5)));
  assert(app.data[0].type == EdgeType.Line);
  assert(app.data[1].type == EdgeType.Quad);
  assert(app.data[2].type == EdgeType.Line);
  assert(app.data[3].type == EdgeType.Cubic);
}

unittest {
  auto app = appender!(Edge!float[])();
  cubicEdge(app, fixedAry!4(FPoint(0.0, 0.0), FPoint(1.0, 1.0),
                             FPoint(2.0, 4.0), FPoint(4.0, 16.0)));
  assert(app.data.length == 1);
  auto cub = app.data[0];
  assert(cub.type == EdgeType.Cubic);

  auto val = updateCubic(cub, 0.0f, 0.01f); assert(val == 0.0);
  val = updateCubic(cub, 1.0f, 1.0f);
  assert(abs(val - 0.659) < 1e-3, to!string(val));
  val = updateCubic(cub, 1.2f, 0.2f);
  val = updateCubic(cub, 2.0f, 0.8f);
  assert(abs(val - 1.063) < 1e-3);
  val = updateCubic(cub, 4.0f, 2.0f);
  assert(abs(val - 1.658) < 1e-3);
}
