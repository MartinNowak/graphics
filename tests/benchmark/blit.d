module benchmark.blit;

import graphics.core.blitter_detail, graphics.core.pmcolor;
import qcheck;

import benchmark.registry, benchmark.reporter;

static this() {
  registerBenchmark!(runBlit)();
}

PMColor[] src;
PMColor[] dst;
immutable PMColor color;

// immutable globals may only be initialized in a `shared static this`
shared static this()
{
  color = getArbitrary!(PMColor)();
}

static this()
{
  dst = getArbitraryArray!(PMColor)(128);
}

void benchColor32()
{
    foreach (i; 0 .. 100_000)
        Color32(dst, color);
}

void runBlit(BenchmarkReporter reporter)
{
    reporter.bench!(benchColor32)();
}
