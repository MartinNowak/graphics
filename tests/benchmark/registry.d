module benchmark.registry;

private {
  import std.array : save;
  import std.string;
  import std.typecons;
  import benchmark.reporter;
}

alias void function(BenchmarkReporter) BenchmarkFunc;
alias Tuple!(string, BenchmarkFunc) NameFunc;

private NameFunc[] __registeredBenchmarks;

void registerBenchmark(alias func)() {
  __registeredBenchmarks ~= tuple(__traits(identifier, func), &func);
}

NameFunc[] allBenchmarks()
{
    return __registeredBenchmarks;
}

NameFunc[] selectBenchmarks(string select) {
  NameFunc[] result;
  foreach(benchTup; __registeredBenchmarks) {
    if (indexOf(benchTup[0], select, CaseSensitive.no) != -1) {
      result ~= benchTup;
    }
  }
  return result;
}

NameFunc[] excludeBenchmarks(string exclude) {
  NameFunc[] result;
  foreach(benchTup; __registeredBenchmarks) {
    if (indexOf(benchTup[0], exclude, CaseSensitive.no) == -1)
      continue;

    result ~= benchTup;
  }
  return result;
}
