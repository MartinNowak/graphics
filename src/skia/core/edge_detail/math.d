module skia.core.edge_detail.algo;

private {
  import skia.core.point;
}

bool isLine(T)(in Point!T[] pts) {
  if (pts.length < 2)
    return false;
  auto refVec = pts[$-1] - pts[0];
  foreach(pt; pts[1..$-1]) {
    if (abs(crossProduct(refVec, pt)) > 1e-2) {
      return false;
    }
  }
  return true;
}
