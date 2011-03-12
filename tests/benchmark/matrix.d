module benchmark.matrix;

private {
  import skia.core.matrix;
  import FLOAT = skia.core.matrix_detail.multiply;
  import SSE = skia.core.matrix_detail.multiply_sse;
  import guip.point;

  import benchmark._;
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
  ms = getArbitrary!(Matrix[], size(1_000), Policies.RandomizeMembers)();
  pts = getArbitrary!(FPoint[], size(10_000), Policies.RandomizeMembers)();
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
 * Matrix x Matrix routines
 */
void FLOATMatrixMultiplication() {
  Matrix lhs;
  lhs.setRotate(10);
  foreach(ref m; ms) {
    auto m2 = FLOAT.multiplyMatrices(lhs, m);
  }
}

void SSEMatrixMultiplication() {
  Matrix lhs;
  lhs.setRotate(10);
  foreach(ref m; ms) {
    auto m2 = SSE.multiplyMatrices(lhs, m);
  }
}

/**
 *
 */
void runMatrix(BenchmarkReporter reporter) {
  RotTransSSE(reporter);
  reporter.bench!FLOATMatrixMultiplication();
  reporter.bench!SSEMatrixMultiplication();
}
