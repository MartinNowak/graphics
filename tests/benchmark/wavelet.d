module benchmark.wavelet;

import graphics.core.path, graphics.core.wavelet.raster, graphics.math.clamp;
import qcheck._, guip.point, std.range;
import benchmark.registry;

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
      path.close();
      break;
    }
    verbs.popFront;
  }
  return path;
}

bool benchPathToWavelet(Path path) {
  auto wr = pathToWavelet(path, path.ibounds);
  return true;
}

bool benchPathToBlit(Path path) {
  auto clip = path.ibounds;
  auto wr = pathToWavelet(path, path.ibounds);
  auto topLeft = wr.clipRect.pos;

  void dummyBlit(int y, int xstart, int xend, ubyte alpha) {
    assert(fitsIntoRange!("[)")(y, clip.top, clip.bottom));
    assert(fitsIntoRange!("[)")(xstart, clip.left, clip.right));
    assert(fitsIntoRange!("[)")(xend, clip.left, clip.right), to!string(xend) ~ "|" ~ to!string(clip.right));
  }

  writeNodeToGrid!(dummyBlit)(
      wr.root, wr.rootConst, topLeft, 1<< wr.depth);
  return true;
}

/**
 *
 */
void runWavelet(BenchmarkReporter reporter) {
  setRandomSeed(1);
  quickCheck!(benchPathToWavelet, randomPath, count(10), minValue(0), maxValue(1024), maxAlloc(500))();
  quickCheck!(benchPathToBlit, randomPath, count(10), minValue(0), maxValue(1024), maxAlloc(500))();
}
