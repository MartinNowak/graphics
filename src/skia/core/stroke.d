module skia.core.stroke;

private {
  import std.traits : isDynamicArray, Unqual;
  import std.math : abs;

  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.stroke_detail._;
}

//! TODO: implement joiner
struct Stroke {
  const Paint paint;
  float radius;
  float invMiterLimit;

  Path outer, inner;
  FPoint prevPt, firstOuterPt;
  FVector firstNormal, firstUnitNormal;
  bool prevIsLine;

  Capper capper;
  Joiner joiner;

  this(in Paint paint, float width) {
    assert(width > 0);
    this.paint = paint;
    this.radius = width * 0.5;
    this.capper = getCapper(paint.capStyle);
    this.joiner = getJoiner(paint.joinStyle);
  }

  FVector getNormal(FPoint pt1, FPoint pt2) {
    FVector normal = pt1 - pt2;
    normal.setLength(radius);
    normal.rotateCCW();
    return normal;
  }

  Path strokePath(in Path path) {
    if (radius <= 0)
      return Path();

    path.forEach((const Path.Verb verb, const FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move:
        this.moveTo(pts[0]);
        break;
      case Path.Verb.Line:
        this.lineTo(fixedAry!2(pts[0..2]));
        break;
      case Path.Verb.Quad:
        // this.quadTo(fixedAry!3(pts[0..3]));
        break;
      case Path.Verb.Cubic:
        // this.cubicTo(fixedAry!4(pts[0..4]));
        break;
      case Path.Verb.Close:
        // this.close(pts[?]);
        break;
      }
      });

    this.close();
    return this.outer;
  }

  //! TODO: get normal, maybe caching last point is necessary.
  void open(FPoint pt) {
    this.inner.moveTo(pt - FPoint(this.radius, 0));
    this.outer.moveTo(pt + FPoint(this.radius, 0));
  }

  void close() {
    this.outer.lineTo(this.inner.lastPoint);
    this.outer.reversePathTo(this.inner);
  }
  void join(FPoint[2] pts, FVector normal) {
  }

  void moveTo(FPoint pt) {
    this.open(pt);
  }

  void line_to(FPoint currPt, FVector normal) {
    this.outer.lineTo(currPt + normal);
    this.inner.lineTo(currPt - normal);
  }

  void lineTo(FPoint[2] pts) {
    if (degenerateLine(pts[0], pts[1])) {
        return;
    }
    auto normal = getNormal(pts[0], pts[1]);
    this.join(pts, normal);
    this.line_to(pts[1], normal);
  }

  static bool degenerateLine(FPoint a, FPoint b) {
    enum tol = 1e-3;
    return distance(a, b) < tol;
  }
}

//! TODO: move somewhere useful.
static Unqual!(typeof(T[0]))[N] fixedAry(size_t N, T)(in T dynAry) if(isDynamicArray!T)
  in {
    assert(dynAry.length >= N);
  } body {
  typeof(return) result;
  foreach(i, ref resVal; result) {
    resVal = dynAry[i];
  }
  return  result;
}