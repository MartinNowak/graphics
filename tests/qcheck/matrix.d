module graphics.core.matrixTest;

private {
  import std.array : appender;
  import std.format : formattedWrite;
  import std.math : abs;

  import graphics.core.matrix;
  import guip.point;

  import graphics.util.format;

  import qcheck._;
}

FPoint Multiply(in Matrix m, FPoint pt) {
  auto xr = pt.x * m[0][0] + pt.y * m[0][1] + m[0][2];
  auto yr = pt.x * m[1][0] + pt.y * m[1][1] + m[1][2];
  auto zr = pt.x * m[2][0] + pt.y * m[2][1] + m[2][2];
  if (zr != 0) {
    xr /= zr;
    yr /= zr;
  }
  return FPoint(xr, yr);
}

void doRun() {
  auto pts = getArbitrary!(FPoint[], size(1000), minValue(0.0), maxValue(2.0), Policies.RandomizeMembers)();
  auto ptsB = pts.idup;
  Matrix m;

  void assertPointsEquality() {
    foreach(i, pt; ptsB) {
      auto mpt = Multiply(m, pt);
      assert(abs(mpt.x - pts[i].x) < 10*float.epsilon, fmtString("unequal pts SSEM:%s FPUM:%s", pts[i], mpt));
      assert(abs(mpt.y - pts[i].y) < 10*float.epsilon, fmtString("unequal pts SSEM:%s FPUM:%s", pts[i], mpt));
    }
  }
  m.setRotate(45);
  m.mapPoints(pts);
  assertPointsEquality();

  pts = ptsB.dup;
  m.setTranslate(100, 100);
  m.mapPoints(pts);
  assertPointsEquality();

  pts = ptsB.dup;
  m.setScale(float.min_normal, float.min_normal);
  m.mapPoints(pts);
  assertPointsEquality();
}

unittest {
  doRun();
}
