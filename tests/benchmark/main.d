module benchmark.main;

import std.algorithm, std.stdio;
import benchmark.registry, benchmark.reporter;

import graphics;

import benchmark.matrix;
import benchmark.wavelet;

int main(string[] argv) {
  scope auto reporter = new BenchmarkReporter(10);

  if (argv.length > 1) {

    if (canFind(argv[1..$], "-l") || canFind(argv[1..$], "--list")) {
      auto benchmarks = allBenchmarks();
      foreach(ref benchTup; benchmarks) {
        writeln(benchTup[0]);
      }
      return 0;
    }
  }
  // auto benchmarks = allBenchmarks();
  auto benchmarks = argv.length > 1 ? selectBenchmarks(argv[1]) : excludeBenchmarks("");

  foreach(ref testTup; benchmarks) {
    reporter.info("--------------------Run BenchMarkSuite %s--------------------", testTup[0]);
    testTup[1](reporter);
  }
  return 0;
}
