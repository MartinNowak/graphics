module skia.core.edgebuilder;

private {
  debug import std.stdio : writeln, writefln, writef;
  import std.algorithm : map, min, max, reduce, sort, swap;
  import std.array : Appender, array, back, front, save;

  import skia.core.path;
  import guip.point;
  import guip.rect;
  import skia.core.edge_detail._;
  import skia.math.fast_sqrt;
  import skia.math.fixed_ary;
}

//debug=PRINTF;

////////////////////////////////////////////////////////////////////////////////

//! Using a TLS buffer, so less allocations are necessary once it has
//! soaked some mem.
static Appender!(FEdge[]) app;

FEdge[] buildEdges(in Path path) {
  app.clear();
  path.forEach((Path.Verb verb, in FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        lineEdge(app, fixedAry!2(pts));
        break;
      case Path.Verb.Quad:
        quadraticEdge(app, fixedAry!3(pts));
        break;
      case Path.Verb.Cubic:
        cubicEdge(app, fixedAry!4(pts));
        break;
      }
    });
  return app.data;
}

FEdge[] buildEdges(in Path path, in IRect clip) {
  app.clear();
  path.forEach((Path.Verb verb, in FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        clippedLineEdge(app, fixedAry!2(pts), clip);
        break;
      case Path.Verb.Quad:
        clippedQuadraticEdge(app, fixedAry!3(pts), clip);
        break;
      case Path.Verb.Cubic:
        clippedCubicEdge(app, fixedAry!4(pts), clip);
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
