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

static this()
{
  src = getArbitraryArray!(PMColor)(128);
  dst = getArbitraryArray!(PMColor)(128);
  color = getArbitrary!(PMColor)();
}

void benchColor32()
{
    foreach (i; 0 .. 100_000)
        Color32(dst, src, color);
}

void runBlit(BenchmarkReporter reporter)
{
    reporter.bench(&benchColor32);
}
