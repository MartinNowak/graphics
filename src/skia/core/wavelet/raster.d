module skia.core.wavelet.raster;

import std.array, std.bitmanip, std.datetime, std.math, std.random, std.conv : to;
import skia.math.clamp, skia.math.rounding, skia.util.format;
import guip.bitmap, guip.point, guip.size;

//version=DebugNoise;

struct Node {
  @property string toString() const {
    auto str = fmtString("Node coeffs:%s", coeffs);
    foreach(i, ch; children)
      if (ch !is null)
        str ~= fmtString("\n%d:%s", i, ch.toString());
    return str;
  }

  void insertEdge(FPoint[2] pts, uint depth) {
    auto q0 = Quadrant(pts[0]);
    auto q1 = Quadrant(pts[1]);
    if (q0.right != q1.right) {
      auto qb0 = q0;
      auto qb1 = q1;
      real t = (0.5 - pts[0].x) / (pts[1].x - pts[0].x);
      FPoint split = FPoint(0.5, pts[0].y + t * (pts[1].y - pts[0].y));
      if (q0.bottom == side(split.y)) {
        insertInto(q0, [pts[0], split], depth);
        pts[0] = split;
        q0.right = !(q0.right);
      } else {
        insertInto(q1, [split, pts[1]], depth);
        pts[1] = split;
        q1.right = !(q1.right);
      }
    }

    assert(q0.right == q1.right, to!string(q0.idx)~"|"~to!string(q1.idx));
    if (q0.bottom != q1.bottom) {
      real t = (0.5 - pts[0].y) / (pts[1].y - pts[0].y);
      FPoint split = FPoint(pts[0].x + t * (pts[1].x - pts[0].x), 0.5);
      insertInto(q0, [pts[0], split], depth);
      pts[0] = split;
    }

    insertInto(q1, pts, depth);
  }

  void insertInto(Quadrant q, FPoint[2] pts, uint depth) {
    auto qpt = FPoint(q.right, q.bottom);
    pts[0] = pts[0] * 2 - qpt;
    pts[1] = pts[1] * 2 - qpt;
    calcCoeffs(pts, q);
    isBoundary[q.idx] = true;
    if (depth > 0)
      getChild(q).insertEdge(pts, --depth);
  }

  void calcCoeffs(FPoint[2] pts, Quadrant q)
  {
    auto norm0 = (1.f / 8.f) * (pts[1].y - pts[0].y);
    auto norm1 = (1.f / 8.f) * (pts[0].x - pts[1].x);
    auto lin0 = pts[0].x + pts[1].x;
    auto lin1 = pts[0].y + pts[1].y;

    switch (q.idx) {
    case 0: // (0, 0)
      const float com = lin0 * norm0;
      this.coeffs[0] += com;
      this.coeffs[2] += com;
      this.coeffs[1] += lin1 * norm1;

      break;
    case 1: // (1, 0)
      const float com = (2.f - lin0) * norm0;
      this.coeffs[0] += com;
      this.coeffs[2] += com;
      this.coeffs[1] += lin1 * norm1;

      break;
    case 2: // (0, 1)
      const float com = lin0 * norm0;
      this.coeffs[0] += com;
      this.coeffs[2] -= com;
      this.coeffs[1] += (2.f - lin1) * norm1;

      break;
    case 3: // (1, 1)
      const float com = (2.f - lin0) * norm0;
      this.coeffs[0] += com;
      this.coeffs[2] -= com;
      this.coeffs[1] += (2.f - lin1) * norm1;

      break;
    default: assert(0);
    }
  }

  ref Node getChild(Quadrant q) {
    if (children[q.idx] is null) {
      children[q.idx] = new Node;
    }
    return *children[q.idx];
  }

  Node*[4] children;
  float[3] coeffs = 0.0f;
  bool[4] isBoundary;
}

struct WaveletRaster {

  this(uint depth) {
    this.depth = depth;
  }

  void insertEdge(FPoint[2] pts) {
    assert(pointsAreClipped(pts));
    this.rootConst +=
      0.5 * (pts[0].x * pts[1].y - pts[0].y * pts[1].x);
    root.insertEdge(pts, depth);
  }

  void insertEdge(FPoint[3] pts) {
    assert(pointsAreClipped(pts));
    assert(0, "unimplemented");
  }

  void insertEdge(FPoint[4] pts) {
    assert(pointsAreClipped(pts));
    assert(0, "unimplemented");
  }

  bool pointsAreClipped(in FPoint[] pts) {
    foreach(pt; pts)
      if (!fitsIntoRange!("[]")(pt.x, 0.0f, 1.0f) || !fitsIntoRange!("[]")(pt.y, 0.0f, 1.0f))
        return false;

    return true;
  }

  Node root;
  float rootConst = 0.0f;
  uint depth;
}

void writeGridValue(float val, IPoint off, ubyte[] grid, uint locRes, uint globRes) {
  assert(locRes > 0);
  version(DebugNoise) {
    enum noise = 55;
    auto ubval = clampTo!ubyte(val * (255-noise) + uniform(0, noise));
  } else {
    auto ubval = clampTo!ubyte(val * 255);
  }
  foreach(y; off.y .. off.y + locRes) {
    auto left = y * globRes + off.x;
    grid[left .. left + locRes] = ubval;
  }
}

void writeNodeToGrid(in Node n, float val, IPoint offset, ubyte[] grid, uint locRes, uint globRes)
{
  uint locRes2 = locRes / 2;

  auto cval = val + n.coeffs[0]  + n.coeffs[1] + n.coeffs[2];
  if (n.children[0] !is null)
    writeNodeToGrid(*n.children[0], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val - n.coeffs[0] + n.coeffs[1] - n.coeffs[2];
  offset.x += locRes2;
  if (n.children[1] !is null)
    writeNodeToGrid(*n.children[1], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val + n.coeffs[0] - n.coeffs[1] - n.coeffs[2];
  offset.x -= locRes2;
  offset.y += locRes2;
  if (n.children[2] !is null)
    writeNodeToGrid(*n.children[2], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val - n.coeffs[0] - n.coeffs[1] + n.coeffs[2];
  offset.x += locRes2;
  if (n.children[3] !is null)
    writeNodeToGrid(*n.children[3], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);
}

struct Quadrant {
  this(FPoint pt) {
    this.right = side(pt.x);
    this.bottom = side(pt.y);
  }

  @property bool right() const { return (this.idx & 0x1) != 0; }
  @property void right(bool b) { if (b) this.idx |= 0x1; else this.idx &= ~0x1; }

  @property bool bottom() const { return (this.idx & 0x2) != 0; }
  @property void bottom(bool b) { if (b) this.idx |= 0x2; else this.idx &= ~0x2; }

  ubyte idx;
}

bool side(float val) {
  return val < 0.5 ? false : true;
}

void main() {
  enum Depth = 8;
  enum Resolution = 1 << Depth;
  auto bmp = Bitmap();
  bmp.setConfig(Bitmap.Config.A8, Resolution, Resolution);
  bmp.getBuffer!ubyte()[] = 127;
  void runInsert() {
    WaveletRaster wr = WaveletRaster(Depth-1);
    wr.insertEdge([FPoint(0.2, 0), FPoint(0.4, 0.0)]);
    wr.insertEdge([FPoint(0.4, 0.0), FPoint(0.5, 1)]);
    wr.insertEdge([FPoint(0.5, 1), FPoint(0.25, 1)]);
    wr.insertEdge([FPoint(0.25, 1), FPoint(0.2, 0)]);
    auto grid = bmp.getBuffer!ubyte[];
    writeNodeToGrid(wr.root, wr.rootConst, IPoint(0, 0), grid, Resolution, Resolution);
  }

  auto r = benchmark!(runInsert)(1);
  std.stdio.writeln(r[0].hnsecs);

//  auto grid = bmp.getBuffer!ubyte[];
//  foreach(y; 0 .. Resolution) {
//    std.stdio.writeln(grid[y*Resolution .. y*Resolution + Resolution]);
//  }
  bmp.save("output.bmp");
}