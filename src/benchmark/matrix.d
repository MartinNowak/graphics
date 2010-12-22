module benchmark.matrix;

private {
  import skia.core.matrix;
  import skia.core.point;

  import benchmark._;
  import quickcheck._;
  import std.stdio;
}

static this() {
  registerBenchmark!(runMatrix)();
}

Matrix[] ms;
FPoint[] pts;
static this() {
  ms = getArbitrary!(Matrix[], size(1_000), Policies.RandomizeMembers)();
  pts = getArbitrary!(FPoint[], size(10_000), Policies.RandomizeMembers)();
}

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

void runMatrix(BenchmarkReporter reporter) {
  RotTransSSE(reporter);
}