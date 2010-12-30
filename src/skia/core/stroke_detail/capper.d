module skia.core.stroke_detail.capper;

private {
  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
}
alias void function(FPoint pt, FVector normal, ref Path path) Capper;
Capper getCapper(Paint.Cap capStyle) {
  final switch(capStyle) {
  case Paint.Cap.Butt:
    return &ButtCapper;
  case Paint.Cap.Square:
    return &SquareCapper;
  case Paint.Cap.Round:
    return &RoundCapper;
  }
}

void ButtCapper(FPoint pt, FVector normal, ref Path path) {
  // assert(path.lastPoint + normal == pt, to!string(path.lastPoint) ~ to!string(pt) ~ to!string(normal));
  path.lineTo(pt + normal);
}

void RoundCapper(FPoint pt, FVector normal, ref Path path) {
  // assert(path.lastPoint + normal == pt, to!string(path.lastPoint) ~ to!string(pt) ~ to!string(normal));
  path.arcTo(pt, pt + normal, Path.Direction.CCW);
}

void SquareCapper(FPoint pt, FVector normal, ref Path path) {
  FVector parallel = normal;
  parallel.rotateCW();
  path.lineTo(pt - normal + parallel);
  path.lineTo(pt + normal + parallel);
  path.lineTo(pt + normal);
}
