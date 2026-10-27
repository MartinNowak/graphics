module graphics.core.stroke_detail.joiner;

private {
  import std.math : abs, sin, asin, tan, PI;
  import std.algorithm : min, max;
  import graphics.core.paint;
  import graphics.core.path;
  import guip.point;
}
alias void function(FPoint pt, FVector normalBefore, FVector normalAfter,
                    ref MutablePathData inner, ref MutablePathData outer,
                    float miterLimit) Joiner;

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
                 ref MutablePathData inner, ref MutablePathData outer,
                 float = 0) {
  // assert(outer.lastPoint - normalBefore == pt);
  outer.lineTo(pt + normalAfter);
  inner.lineTo(pt - normalAfter);
 }

void RoundJoiner(FPoint pt, FVector normalBefore, FVector normalAfter,
                 ref MutablePathData inner, ref MutablePathData outer,
                 float = 0) {
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
                 ref MutablePathData inner, ref MutablePathData outer,
                 float miterLimit) {
  auto crossP = determinant(normalBefore, normalAfter);
  auto radius = normalBefore.length;
  //  assert(normalAfter.length == radius);
  immutable ml = max(miterLimit, 1.0f); // SVG: a miterlimit below 1 is treated as 1
  auto r2 = radius * radius;
  // asin folds the sweep of the normals into (-90, 90]; both a straight
  // continuation and a fold-back collapse to a near-zero sweep there, and
  // the spike of the extended rail is 1 / (2 * sin(sweep/2)) stroke widths
  // deep. The (SVG presentation attribute) limit cuts the spike when that
  // exceeds ml, i.e. sweep < 2 * asin(1 / (2 * ml)) - the old hardcoded
  // 15 degrees are exactly this rule for a miterlimit of 4.
  // normalAfter's length can differ from radius by float noise, letting
  // crossP/r2 land just outside [-1, 1]; clamp rather than asin to NaN.
  auto ratio = crossP / r2;
  ratio = min(max(ratio, -1.0f), 1.0f);
  auto sweep = asin(ratio);
  if (abs(sweep) < 2.0f * asin(0.5f / ml)) {
    BevelJoiner(pt, normalBefore, normalAfter, inner, outer);
  } else {
    auto angle = sweep;
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
    getJoiner(JoinStyle.Bevel)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer, 4);
    assert(outer.lastPoint == FPoint(15, 0));
    assert(inner.lastPoint == FPoint(5, 0));

    // Miter with a right angle: a single spike point on the inner rail
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer, 4);
    // spike at (10,0) + (-5,5), then the two regular rail lines
    assert(inner.points.length == 3);
    assert(outer.points.length == 2);

    // Regression: |crossP| > radius^2 (normals of slightly different
    // lengths, as produced by the stroke pipeline's float noise) must clamp
    // the asin argument instead of yielding NaN.
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(5, -5), FVector(5, 5.1f), inner, outer, 4);
    foreach (p; inner.points)
        assert(p.x == p.x && p.y == p.y); // NaN != NaN
    foreach (p; outer.points)
        assert(p.x == p.x && p.y == p.y);
    assert(outer.lastPoint == FPoint(15, 5.1f)); // pt + normalAfter; spike goes to inner

    // Miter with an extremely shallow angle degrades to Bevel
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(0.01f, -5), inner, outer, 4);
    assert(inner.points.length == 2); // just the bevel line
    assert(outer.points.length == 2);

    // The miterlimit chooses where the extended rail is cut: the same near
    // fold-back (a ~57-width spike) bevels at limit 30 but keeps its point
    // at a limit of 200.
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(0.1f, -5), inner, outer, 30);
    assert(inner.points.length == 2); // beveled
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Miter)(FPoint(10, 0), FVector(0, -5), FVector(0.1f, -5), inner, outer, 200);
    assert(inner.points.length == 3); // spike kept

    // Round joiner skips (near-)straight joins
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Round)(FPoint(10, 0), FVector(0, -5), FVector(0.001f, -5), inner, outer, 4);
    assert(inner.points.length == 1 && outer.points.length == 1);

    // Round joiner with a real corner sweeps an arc onto one rail
    inner.reset(); outer.reset();
    inner.moveTo(FPoint(0, 0));
    outer.moveTo(FPoint(0, 0));
    getJoiner(JoinStyle.Round)(FPoint(10, 0), FVector(0, -5), FVector(5, 0), inner, outer, 4);
    // the arc approximation adds several points onto the inner rail
    assert(inner.points.length >= 3);
    assert(outer.points.length == 2); // plain bevel line on the other side
    assert(outer.lastPoint == FPoint(15, 0));

    // clockwise predicate
    assert(clockwise(FVector(0, -1), FVector(1, 0)));
    assert(!clockwise(FVector(1, 0), FVector(0, -1)));
}
