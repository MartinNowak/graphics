module graphics.core.stroke_detail.joiner;

private {
  import std.math : abs, sin, asin, tan, PI;

  import graphics.core.paint;
  import graphics.core.path;
  import guip.point;
}
alias void function(FPoint pt, FVector normalBefore, FVector normalAfter,
                    ref MutablePathData inner, ref MutablePathData outer) Joiner;

enum JoinStyle { Miter, Round, Bevel, }

Joiner getJoiner(JoinStyle joinStyle)
{
    final switch(joinStyle)
    {
    case JoinStyle.Miter:
        return &MiterJoiner;
    case JoinStyle.Round:
        return &RoundJoiner;
    case JoinStyle.Bevel:
        return &BevelJoiner;
    }
}

void BevelJoiner(FPoint pt, FVector normalBefore, FVector normalAfter,
                 ref MutablePathData inner, ref MutablePathData outer) {
  // assert(outer.lastPoint - normalBefore == pt);
  outer.lineTo(pt + normalAfter);
  inner.lineTo(pt - normalAfter);
 }

void RoundJoiner(FPoint pt, FVector normalBefore, FVector normalAfter,
                 ref MutablePathData inner, ref MutablePathData outer) {
  enum tol = tan(0.1 * 2 * PI / 360);

  auto crossP = determinant(normalBefore, normalAfter);
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

void MiterJoiner(FPoint pt, FVector normalBefore, FVector normalAfter,
                 ref MutablePathData inner, ref MutablePathData outer) {
  auto crossP = determinant(normalBefore, normalAfter);
  auto radius = normalBefore.length;
  //  assert(normalAfter.length == radius);
  enum miterLimit = sin(2*PI*15/360);
  if (abs(crossP) <  miterLimit * radius * radius) {
    BevelJoiner(pt, normalBefore, normalAfter, inner, outer);
  } else {
    auto angle = asin(crossP / (radius * radius));
    auto midLength = radius / sin(angle * 0.5);
    auto mid = -normalBefore - normalAfter;
    mid = mid.scaledTo(midLength);
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
  return determinant(before, after) > 0;
}

unittest
{
    import std.math : abs;

    // Bevel: straight lines to both rails at the new normal
    MutablePathData inner, outer;
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Bevel)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer);
    assert(outer.lastPoint == FPoint(15, 0));
    assert(inner.lastPoint == FPoint(5, 0));

    // Miter with a right angle: a single spike point on the inner rail
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer);
    // spike at (10,0) + (-5,5), then the two regular rail lines
    assert(inner.points.length == 3);
    assert(outer.points.length == 2);
    assert(outer.lastPoint == FPoint(15, 0));

    // Miter with an extremely shallow angle degrades to Bevel
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(0.01f, -5), inner, outer);
    assert(inner.points.length == 2); // just the bevel line
    assert(outer.points.length == 2);

    // Round joiner skips (near-)straight joins
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Round)(FPoint(10, 0), FVector(0, -5), FVector(0.001f, -5), inner, outer);
    assert(inner.points.length == 1 && outer.points.length == 1);

    // Round joiner with a real corner sweeps an arc onto one rail
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Round)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer);
    // the arc approximation adds several points onto the inner rail
    assert(inner.points.length >= 3);
    assert(outer.points.length == 2); // plain bevel line on the other side
    assert(outer.lastPoint == FPoint(15, 0));

    // clockwise predicate
    assert(clockwise(FVector(0, -1), FVector(1, 0)));
    assert(!clockwise(FVector(1, 0), FVector(0, -1)));
}
