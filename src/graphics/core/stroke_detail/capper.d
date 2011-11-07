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
  parallel.rotateCW();
  path.lineTo(pt - normal + parallel);
  path.lineTo(pt + normal + parallel);
  path.lineTo(pt + normal);
}
