module skia.core.stroke_detail.joiner;

private {
  import std.math : abs, sin, asin, tan, PI;

  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
}
alias void function(FPoint pt, FVector normalBefore,
                    FVector normalAfter, ref Path inner, ref Path outer) Joiner;

Joiner getJoiner(Paint.Join joinStyle) {
  final switch(joinStyle) {
  case Paint.Join.Miter:
    return &MiterJoiner;
  case Paint.Join.Round:
    return &RoundJoiner;
  case Paint.Join.Bevel:
    return &BevelJoiner;
  }
}

void BevelJoiner(FPoint pt, FVector normalBefore, FVector normalAfter, ref Path inner, ref Path outer) {
  // assert(outer.lastPoint - normalBefore == pt);
  outer.lineTo(pt + normalAfter);
  inner.lineTo(pt - normalAfter);
 }

void RoundJoiner(FPoint pt, FVector normalBefore, FVector normalAfter, ref Path inner, ref Path outer) {
  enum tol = tan(0.1 * 2 * PI / 360);

  auto crossP = crossProduct(normalBefore, normalAfter);
  if (abs(crossP) < tol * abs(dotProduct(normalBefore, normalAfter)))
    return;

  if (crossP > 0) {
    inner.arcTo(pt, pt - normalAfter, Path.Direction.CW);
    outer.lineTo(pt + normalAfter);
  } else if (crossP < 0) {
    outer.arcTo(pt, pt + normalAfter, Path.Direction.CCW);
    inner.lineTo(pt - normalAfter);
  }
}

void MiterJoiner(FPoint pt, FVector normalBefore, FVector normalAfter, ref Path inner, ref Path outer) {
  auto crossP = crossProduct(normalBefore, normalAfter);
  auto radius = normalBefore.length;
  //  assert(normalAfter.length == radius);
  enum miterLimit = sin(2*PI*15/360);
  if (abs(crossP) <  miterLimit * radius * radius) {
    BevelJoiner(pt, normalBefore, normalAfter, inner, outer);
  } else {
    auto angle = asin(crossP / (radius * radius));
    auto midLength = radius / sin(angle * 0.5);
    auto mid = -normalBefore - normalAfter;
    mid.setLength(midLength);
    if (crossP > 0) { // clockwise (see below), but save recalculation
      inner.lineTo(pt + mid);
    } else {
      outer.lineTo(pt + mid);
    }
    outer.lineTo(pt + normalAfter);
    inner.lineTo(pt - normalAfter);
  }
}

bool clockwise(FVector before, FVector after) {
  return crossProduct(before, after) > 0;
}
