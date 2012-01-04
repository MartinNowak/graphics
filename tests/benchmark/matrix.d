module benchmark.matrix;

private {
  import graphics.core.matrix;
  import guip.point;

  import benchmark.registry, benchmark.reporter;
  import qcheck._;
  import std.stdio;
}

static this() {
  registerBenchmark!(runMatrix)();
}

/**
 * Shared test data
 */
immutable Matrix[] ims;
immutable FPoint[] ipts;
static this() {
  auto config = Config().maxSize(1000).randomizeFields(true);
  ims = getArbitrary!(Matrix[])(config).idup;
  config.maxSize = 10_000;
  ipts = getArbitrary!(FPoint[])(config).idup;
}

/**
 * Matrix x Point routines
 */
void RotTransSSE(BenchmarkReporter reporter) {
  auto pts = ipts.dup;
  void DoTest() {
    foreach(ref m; ims) {
      m.mapPoints(pts);
      pts[] = ipts[];
    }
  }
  reporter.bench(&DoTest);
}

/**
 *
 */
void runMatrix(BenchmarkReporter reporter) {
  RotTransSSE(reporter);
}
