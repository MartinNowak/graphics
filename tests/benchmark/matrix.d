module benchmark.matrix;

import graphics.core.matrix;
import guip.point;

import benchmark.registry, benchmark.reporter;
import qcheck;

static this() {
  registerBenchmark!(runMatrix)();
}

/**
 * Shared test data
 */
immutable Matrix[] ims;
immutable FPoint[] ipts;
FPoint[] pts;
// immutable globals may only be initialized in a `shared static this`
shared static this() {
  Config config = {maxSize: 1000};
  ims = getArbitrary!(Matrix[])(config).idup;
  config.maxSize = 10_000;
  ipts = getArbitrary!(FPoint[])(config).idup;
  pts = ipts.dup;
}

/**
 * Matrix x Point routines
 */
void benchMapPoints() {
  foreach(ref m; ims) {
    m.mapPoints(pts);
    pts[] = ipts[];
  }
}

void runMatrix(BenchmarkReporter reporter) {
  reporter.bench!(benchMapPoints)();
}
