module skia.core.path_detail.flattener;

private {
  import std.traits : ReturnType;
  import std.math : cos, PI;

  import skia.core.path;
  import skia.core.point;
  import skia.math.fixed_ary;
  import skia.core.edge_detail.algo : splitBezier;
  debug import std.stdio;
}

static assert(is(ReturnType!(Path.IterDg) == void), "need to adopt Flattener::call()");

struct NoopFlattener {
  private Path.IterDg dg;
  this(Path.IterDg dg) {
    this.dg = dg;
  }

  void call(Path.Verb verb, in FPoint[] pts) {
    this.dg(verb, pts);
  }
}

struct QuadCubicFlattener {
  private Path.IterDg dg;
  this(Path.IterDg dg) {
    this.dg = dg;
  }

  void call(Path.Verb verb, in FPoint[] pts) {
    final switch (verb) {
    case Path.Verb.Move, Path.Verb.Close:
      return this.dg(verb, pts);

    case Path.Verb.Line:
      return this.__line(pts);

    case Path.Verb.Quad:
      return this.__quad(pts);

    case Path.Verb.Cubic:
      return this.__cubic(pts);
    }
  }

  void __line(in FPoint[] pts) {
    assert(pts.length == 2);

    if (degenerate(pts[0], pts[1]))
      return;
    else
      return this.dg(Path.Verb.Line, pts);
  }

  void __quad(in FPoint[] pts) {
    assert(pts.length == 3);

    if (degenerate(pts[0], pts[1]))
      return this.__line(pts[1 .. $]);
    else if (degenerate(pts[1], pts[2]))
      return this.__line(pts[0 .. $ - 1]);
    else{
      if (tooCurvy(pts[1] - pts[0], pts[2] - pts[1])) {
        auto ptss = splitBezier(fixedAry!3(pts), 0.5);
        this.__quad(ptss[0]);
        this.__quad(ptss[1]);
      } else {
        this.dg(Path.Verb.Quad, pts);
      }
    }
  }

  void __cubic(in FPoint[] pts) {
    assert(pts.length == 4);

    if (degenerate(pts[0], pts[1]))
      return this.__quad(pts[1 .. $]);
    else if (degenerate(pts[2], pts[3]))
      return this.__quad(pts[0 .. $ - 1]);
    else{
      if (tooCurvy(pts[1] - pts[0], pts[2] - pts[1])
          || tooCurvy(pts[2] - pts[1], pts[3] - pts[2])) {
        auto ptss = splitBezier(fixedAry!4(pts), 0.5);
        this.__cubic(ptss[0]);
        this.__cubic(ptss[1]);
      } else {
        this.dg(Path.Verb.Cubic, pts);
      }
    }
  }
}

private bool degenerate(FPoint pt1, FPoint pt2) {
  enum tol = 1e-3;
  return distance(pt1, pt2) < tol;
}

private bool tooCurvy(FVector v1, FVector v2) {
  // angle between v1 and v2 < +/-45 deg?
  //  const limit = SQRT1_2 * v1.length * v2.length;
  enum tol = cos(45 * 2 * PI / 360);
  return dotProduct(v1, v2) < tol * v1.length * v2.length;
}