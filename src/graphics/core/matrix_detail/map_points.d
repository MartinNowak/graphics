module graphics.core.matrix_detail.map_points;

private {
  import std.conv : to;
  import graphics.core.matrix;
  import guip.point;
}

alias void function(in Matrix, FPoint[]) MapPtsFunc;
MapPtsFunc mapPtsFunc(ubyte typeMaskTrans) {
  switch(typeMaskTrans) {
  case 0:
    return &IdentityPts;
  case 1:
    return &TransPts;
  case 2:
    return &ScalePts;
  case 3:
    return &ScaleTransPts;
  case 4, 6:
    return &RotPts;
  case 5, 7:
    return &RotTransPts;
  default:
    return &PerspPts;
  }
}

static void IdentityPts(in Matrix, FPoint[]) {
  return;
}

static void TransPts(in Matrix m, FPoint[] pts) {
  assert(m.typeMaskTrans == Matrix.Type.Translative, to!string(m.typeMaskTrans));

  auto tPt = FPoint(m[0][2], m[1][2]);
  foreach(ref pt; pts) {
    pt += tPt;
  }
}

static void ScalePts(in Matrix m, FPoint[] pts) {
  assert(m.typeMaskTrans == Matrix.Type.Scaling, to!string(m.typeMaskTrans));

  auto sPt = FPoint(m[0][0], m[1][1]);
  foreach(ref pt; pts) {
    pt *= sPt;
  }
}

static void ScaleTransPts(in Matrix m, ref FPoint[] pts) {
  assert(m.typeMaskTrans == (Matrix.Type.Translative | Matrix.Type.Scaling));

  auto tPt = FPoint(m[0][2], m[1][2]);
  auto sPt = FPoint(m[0][0], m[1][1]);
  foreach(ref pt; pts) {
    pt *= sPt;
    pt += tPt;
  }
}

static void RotPts(in Matrix m, FPoint[] pts) {
  assert((m.typeMaskTrans & (Matrix.Type.Perspective | Matrix.Type.Translative)) == 0);

  auto sPt = FPoint(m[0][0], m[1][1]);
  foreach(ref pt; pts) {
    auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
    pt = pt * sPt + skewPt;
  }
}

static void RotTransPts(in Matrix m, FPoint[] pts) {
  assert((m.typeMaskTrans & Matrix.Type.Perspective) == 0);

  auto sPt = FPoint(m[0][0], m[1][1]);
  auto tPt = FPoint(m[0][2], m[1][2]);

  foreach(ref pt; pts) {
    auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
    pt = pt * sPt + skewPt + tPt;
  }
}

static void PerspPts(in Matrix m, FPoint[] pts) {
  assert(m.typeMaskTrans & Matrix.Type.Perspective);

  auto sPt = FPoint(m[0][0], m[1][1]);
  auto tPt = FPoint(m[0][2], m[1][2]);

  auto p0 = m[2][0];
  auto p1 = m[2][1];
  auto p2 = m[2][2];

  foreach(ref pt; pts) {
    auto z = pt.x * p0 + pt.y * p1 + p2;
    auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
    pt = pt * sPt + skewPt + tPt;
    if (z)
      pt /= z;
  }
}

unittest {
  Matrix m;
  m.reset();
  m[0][0] = 2.0f;
  m[0][1] = -1.0f;
  m[1][0] = 0.5f;
  m[1][2] = 1.0f;
  auto pts = [FPoint(5.0f, 5.0f), FPoint(1.0f, 1.0f), FPoint(2.0f, 3.0f), FPoint(-1.0f, 4.0f)];
  RotTransPts(m, pts);
  assert(pts == [FPoint(5.0f, 8.5f), FPoint(1.0f, 2.5f), FPoint(1.0f, 5.0f), FPoint(-6.0f, 4.5f)],
         to!string(pts));
}
