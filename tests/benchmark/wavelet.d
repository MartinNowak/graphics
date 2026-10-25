module benchmark.wavelet;

import graphics, graphics.core.blitter, graphics.core.draw, graphics.core.matrix, graphics.math.clamp;
import qcheck, guip.point, std.range;
import benchmark.registry, benchmark.reporter;

static this() {
  registerBenchmark!(runWavelet)();
}

Path randomPath(Path.Verb[] verbs, FPoint[] pts) {
  auto numVerbs = verbs.length;
  auto numPts = pts.length;

  Path path;
 loop: while (!verbs.empty) {
    final switch (verbs.front) {
    case Path.Verb.Move:
      if (path.lastVerbWas(Path.Verb.Move))
          break;
      if (pts.length < 1)
        break loop;
      path.moveTo(pts.front);
      pts.popFront;
      break;

    case Path.Verb.Line:
      if (pts.length < 1)
        break loop;
      path.lineTo(pts.front);
      pts.popFront;
      break;

    case Path.Verb.Quad:
      if (pts.length < 2)
        break loop;
      path.quadTo(pts.front, pts[1]);
      pts.popFront; pts.popFront;
      break;

    case Path.Verb.Cubic:
      if (pts.length < 3)
        break loop;
      path.cubicTo(pts.front, pts[1], pts[2]);
      pts.popFront; pts.popFront; pts.popFront;
      break;

    case Path.Verb.Close:
      if (!path.lastVerbWas(Path.Verb.Move))
        path.close();
      break;
    }
    verbs.popFront;
  }
  return path;
}

Path path;
static this()
{
  Config config = {maxSuccess: 20, minValue: 0, maxValue: 1024, maxSize: 500};
  randomSeed = 1;

  do
      path = getArbitrary!(Path, randomPath)(config);
  while (path.empty);
}

void benchWaveletBlitPath()
{
  auto clip = path.ibounds;

  // NullBlitter keeps this a traversal + scratch-rasterization
  // benchmark; the span contract invariants (`y` in `[top, bottom)`,
  // `xstart`/`xend` in `[left, right]`) now live in the debug asserts
  // of `WaveletRaster.blit`.
  Matrix mat;
  scope auto blitter = new NullBlitter();
  waveletBlitPath(path, clip, mat, blitter);
}

void runWavelet(BenchmarkReporter reporter) {
  reporter.bench!(benchWaveletBlitPath)();
}
