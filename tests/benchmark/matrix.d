module benchmark.matrix;

import graphics.core.matrix;
import guip.point;

import benchmark.registry, benchmark.reporter;
import qcheck;
import std.stdio;

static this() {
  registerBenchmark!(runMatrix)();
}

/**
 * Shared test data
 */
immutable Matrix[] ims;
immutable FPoint[] ipts;
static this() {
  Config config = {maxSize: 1000};
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
