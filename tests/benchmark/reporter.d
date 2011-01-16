module benchmark.reporter;

private {
  import std.stdio : writeln, writefln;
  import Date = std.date;
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
    auto results = Date.benchmark!(func)(times);
    this.reportResult(name, results[0] / times);
  }
  void bench(Dg)(Dg dg) {
    this.bench(dg, this.numHint);
  }
  void bench(Dg)(Dg dg, size_t times) {
    enum name = __traits(identifier, dg);
    this.log!(LogLevel.Info)("Bench %s count:%s", name, times);

    immutable t = Date.getUTCtime;
    foreach (j; 0 .. times)
    {
      dg();
    }
    immutable delta = Date.getUTCtime - t;

    this.reportResult(name, delta / times);
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