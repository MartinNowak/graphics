module benchmark.math;

private  {
  import benchmark._;
  import skia.core.edgebuilder : fastSqrt;
}

static this() {
  registerBenchmark!(runMath)();
}

void benchFastSqrt() {
  real sum = 0.0;
  for (auto i = 0; i < 1_000_000; ++i) {
    sum += fastSqrt(i);
  }
}

void runMath(BenchmarkReporter reporter) {
  reporter.bench!(benchFastSqrt)();
}