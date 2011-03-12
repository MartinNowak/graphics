module benchmark.edges;

private {
  import std.array : appender;
  import std.random : uniform;
  import skia.core.edge_detail._;
  import guip.point;

  import benchmark._;
  import qcheck._;
  import std.stdio;
}

static this() {
  registerBenchmark!(runEdges)();
}

Edge!T cubicMaker(T)(Point!T[4] pts) {
  auto app = appender!(Edge!T[]);
  app.clear();
  cubicEdge(app, pts);
  assert(app.data.length > 0);
  auto idx = uniform(0u, app.data.length);
  assert(app.data[idx].cubic.oldT == 0.0);
  assert(app.data[idx].type == 2);
  return app.data[idx];
}

/**
 * Shared test data
 */
FEdge[] edges;
static this() {
  edges = getArbitrary!(FEdge[], size(1000), cubicMaker!float, minValue(0), maxValue(1000))();
}

void CubicEdgeUpdate() {
  for (auto edgeIdx = 0; edgeIdx < edges.length; ++edgeIdx) {
    auto yStart = edges[edgeIdx].firstY;
    auto yInc = (edges[edgeIdx].lastY - edges[edgeIdx].firstY) * 0.001;
    for (auto i = 0; i < 100; ++i) {
      edges[edgeIdx].updateEdge(yStart + i * yInc, yInc);
    }
  }
}

/**
 *
 */
void runEdges(BenchmarkReporter reporter) {
  reporter.bench!CubicEdgeUpdate(1);
}
