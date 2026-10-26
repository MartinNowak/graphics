module graphics.core.stroke_detail.capper;

import graphics.core.path, graphics.core.paint, guip.point;

enum CapStyle { Butt, Square, Round, }

alias void function(FPoint pt, FVector normal, ref MutablePathData path) Capper;

Capper getCapper(CapStyle capStyle)
{
    final switch(capStyle)
    {
    case CapStyle.Butt:
        return &ButtCapper;
    case CapStyle.Square:
        return &SquareCapper;
    case CapStyle.Round:
        return &RoundCapper;
    }
}

void ButtCapper(FPoint pt, FVector normal, ref MutablePathData path) {
  // assert(path.lastPoint + normal == pt, to!string(path.lastPoint) ~ to!string(pt) ~ to!string(normal));
  path.lineTo(pt + normal);
}

void RoundCapper(FPoint pt, FVector normal, ref MutablePathData path) {
  // assert(path.lastPoint + normal == pt, to!string(path.lastPoint) ~ to!string(pt) ~ to!string(normal));
  path.arcTo(pt, pt + normal, Path.Direction.CCW);
}

void SquareCapper(FPoint pt, FVector normal, ref MutablePathData path) {
  FVector parallel = normal;
  parallel = parallel.rotatedCW();
  path.lineTo(pt - normal + parallel);
  path.lineTo(pt + normal + parallel);
  path.lineTo(pt + normal);
}

unittest
{
    import std.math : abs;

    // Butt appends a single line to the capped end
    MutablePathData butt;
    butt.moveTo(FPoint(0, 0));
    getCapper(CapStyle.Butt)(FPoint(10, 0), FVector(0, 5), butt);
    assert(butt.verbs == [Path.Verb.Move, Path.Verb.Line]);
    assert(butt.lastPoint == FPoint(10, 5));

    // Square appends three lines, extending past the endpoint
    MutablePathData square;
    square.moveTo(FPoint(0, 0));
    getCapper(CapStyle.Square)(FPoint(10, 0), FVector(0, 5), square);
    assert(square.verbs.length == 4);
    assert(square.lastPoint == FPoint(10, 5));
    // the square cap sticks out by the cap radius along the rotated normal
    assert(abs(square.points[1].x - 5) < 1e-3); // pt - normal + parallel
    assert(abs(square.points[2].x - 5) < 1e-3); // pt + normal + parallel

    // Round sweeps a semicircle of quarter-arc quads
    MutablePathData round;
    round.moveTo(FPoint(10, 0));
    getCapper(CapStyle.Round)(FPoint(10, 0), FVector(0, 5), round);
    assert(round.verbs[0] == Path.Verb.Move);
    assert(round.points.length > 2); // arc segments
    assert(round.lastPoint == FPoint(10, 5));
}
