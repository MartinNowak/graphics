module graphics.effect.patheffects;

import std.algorithm, std.math, std.range;
import graphics.core.path, graphics.core.patheffect, graphics.core.path_detail.path_measure;
import guip.point, guip.rect;

class DashPathEffect : PathEffect {
  this(float[] intervals) {
    this.intervals = intervals;
    this.intervalLength = reduce!("a+b")(0.0f, intervals);
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
}


class DotPathEffect : PathEffect {
  this(float dotsize, float dotdist) {
    this.dotsize = dotsize;
    this.dotdist = dotdist;
  }

  this(float dotsize) {
    this(dotsize, 2 * dotsize);
  }

  Path filterPath(Path path, ref float width) const {
    auto meas = PathMeasure(path);

    auto scaledDist = meas.length / floor(meas.length / this.dotdist);

    Path result;
    // @@ BUG @@ segfaults
    //    auto getPos = &meas.getPosAtDistance;
    //    foreach(pos; map!(getPos)(iota(0.0f, meas.length, scaledDist))) {
    foreach(t; iota(0.0f, meas.length, scaledDist)) {
      auto pos = meas.getPosAtDistance(t);
      auto diag = 0.5 * FVector(this.dotsize, this.dotsize);
      auto fr = FRect(pos - diag, pos + diag);
      result.addOval(fr);
    }
    return result;
  }

  float dotsize, dotdist;
}
