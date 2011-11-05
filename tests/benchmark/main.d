module benchmark.main;

private {
  import std.algorithm : find;
  import std.array : empty;
  import benchmark.registry : selectBenchmarks, excludeBenchmarks, NameFunc;
  import benchmark.reporter;

  import graphics._;
  //  pragma(build, benchmark);

  import benchmark.matrix;
  import benchmark.wavelet;
}

int main(string[] argv) {
  scope auto reporter = new BenchmarkReporter(10);

  if (argv.length > 1) {

    if (!argv[1..$].find("-l").empty || !argv[1..$].find("--list").empty) {
      auto benchmarks = excludeBenchmarks("");
      foreach(ref benchTup; benchmarks) {
        writeln(benchTup[0]);
      }
      return 0;
    }
  }
  auto benchmarks = argv.length > 1 ? selectBenchmarks(argv[1]) :
    excludeBenchmarks("");

  foreach(ref testTup; benchmarks) {
    reporter.info("--------------------Run BenchMarkSuite %s--------------------", testTup[0]);
    testTup[1](reporter);
  }
  return 0;
}
