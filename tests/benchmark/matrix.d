module benchmark.matrix;

private {
  import graphics.core.matrix;
  import guip.point;

  import benchmark.registry;
  import qcheck._;
  import std.stdio;
}

static this() {
  registerBenchmark!(runMatrix)();
}

/**
 * Shared test data
 */
Matrix[] ms;
FPoint[] pts;
static this() {
  ms = getArbitrary!(Matrix[], maxAlloc(1_000), Policies.RandomizeMembers)();
  pts = getArbitrary!(FPoint[], maxAlloc(10_000), Policies.RandomizeMembers)();
}

/**
 * Matrix x Point routines
 */
void RotTransSSE(BenchmarkReporter reporter) {
  auto ptsB = pts.idup;
  void DoTest() {
    foreach(ref m; ms) {
      m.mapPoints(pts);
      pts = ptsB.dup;
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
