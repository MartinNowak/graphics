module skia.core.edgebuilder;

private {
  debug import std.stdio : writeln, writefln, writef;
  import std.algorithm : map, min, max, reduce, sort, swap;
  import std.array : appender, array, back, front, save;

  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.edge_detail._;
  import skia.math.fast_sqrt;
}

//debug=PRINTF;
//debug=Illinois; // verbose tracing for Illinois algo.

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
