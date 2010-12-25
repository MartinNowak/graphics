module skia.core.edgebuilder;

private {
  debug import std.stdio : writeln, writefln, writef;
  import std.algorithm : map, min, max, reduce, sort, swap;
  import std.array : Appender, array, back, front, save;

  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.edge_detail._;
  import skia.math.fast_sqrt;
}

//debug=PRINTF;
//debug=Illinois; // verbose tracing for Illinois algo.

////////////////////////////////////////////////////////////////////////////////

//! Using a TLS buffer, so less allocations are necessary once it has
//! soaked some mem.
static Appender!(FEdge[]) app;

FEdge[] buildEdges(in Path path) {
  app.clear();
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

FEdge[] buildEdges(in Path path, in IRect clip) {
  app.clear();
  path.forEach((const Path.Verb verb, const FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        clippedLineEdge(app, pts, clip);
        break;
      case Path.Verb.Quad:
        clippedQuadraticEdge(app, pts, clip);
        break;
      case Path.Verb.Cubic:
        clippedCubicEdge(app, pts, clip);
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
