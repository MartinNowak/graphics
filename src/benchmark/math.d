module benchmark.skia_math;

private  {
  import benchmark._;
  import skia.core.edgebuilder : fastSqrt;
  import skia.math.m128;
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

void loadm128() {
  m128 var;
  for (auto i = 0; i < 1_000_000; ++i) {
    var = m128(i, i, i, i);
  }
}

void runMath(BenchmarkReporter reporter) {
  reporter.bench!(loadm128)();
  reporter.bench!(benchFastSqrt)();
}
