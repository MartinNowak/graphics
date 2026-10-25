module benchmark.reporter;

private {
  import std.stdio : writeln, writefln;
  import std.datetime.stopwatch;
}

enum LogLevel {
  Info,
  Result,
  Error,
  Debug,
}

class BenchmarkReporter {
  size_t testCount;
  LogLevel logLevel;
  const uint numHint;

  this(uint numHint = 50) {
    this.numHint = numHint;
    this.logLevel = LogLevel.Info;
  }

  void reportResult(string testName, double msTime) {
    this.log!(LogLevel.Result)("Benchmark %s %s t:%sms", this.testCount, testName, msTime);
    ++this.testCount;
  }

  void bench(alias func)() {
    this.bench!(func)(this.numHint);
  }

  void bench(alias func)(uint times) {
    enum name = __traits(identifier, func);
    this.log!(LogLevel.Info)("Bench %s count:%s", name, times);
    auto res = time!(typeof(&func))(&func, times);
    this.reportResult(name, res / times);
  }

  /// Run `f` `times` iterations in several rounds and return the
  /// shortest total elapsed time in milliseconds.
  double time(F)(F f, uint times) {
    double best = double.infinity;
    for (int round = 0; round < 3; ++round) {
      StopWatch sw;
      sw.start();
      foreach(_; 0 .. times)
        f();
      sw.stop();
      auto ms = sw.peek.total!"msecs"();
      if (ms < best)
        best = ms;
    }
    return best;
  }

  void log(LogLevel level)(string msg) {
    if (level >= this.logLevel) {
      writeln(msg);
    }
  }

  void log(LogLevel level, Args...)(string fmt, Args args) {
    if (level >= this.logLevel) {
      writefln(fmt, args);
    }
  }

  void info(Args...)(Args args) {
    this.log!(LogLevel.Info)(args);
  }
}
