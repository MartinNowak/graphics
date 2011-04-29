module skia.effect.dashpatheffect;

import std.algorithm, std.math;
import skia.core.path, skia.core.patheffect, skia.core.path_detail.path_measure,
  skia.math.fixed_ary, skia.core.edge_detail.algo;
import guip.point;

class DashPathEffect : PathEffect {
  this(float[] intervals) {
    this.intervals = intervals;
    this.intervalLength = reduce!("a+b")(0.0f, intervals);
    this.scaleToFit = scaleToFit;
  }

  Path filterPath(Path path, ref float width) const {
    auto meas = PathMeasure(path);

    auto scale = intervalLength > meas.length
      ? meas.length / intervalLength
      : meas.length / (floor(meas.length / intervalLength) * intervalLength);

    Path result;
    auto dist = 0.0;
    while (dist < meas.length) {
      foreach(i, dash; intervals) {
        auto newDist = dist + dash * scale;
        if ((i & 0x1) == 0)
          meas.appendRangeToPath(dist, newDist, result);
        dist = newDist;
      }
    }
    return result;
  }

  float[] intervals;
  float intervalLength;
  bool scaleToFit;
}
