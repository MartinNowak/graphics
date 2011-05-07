module skia.core.wavelet.raster;

import std.array, std.bitmanip, std.datetime, std.math, std.random, std.conv : to;
import skia.math.clamp, skia.math.rounding, skia.util.format,
  skia.core.edge_detail.algo;
import guip.bitmap, guip.point, guip.size;

//version=DebugNoise;

struct Node {
  @property string toString() const {
    auto str = fmtString("Node coeffs:%s", coeffs);
    foreach(i; 0 .. 4)
      if (hasChild(i))
        str ~= fmtString("\n%d:%s", i, children[i].toString());
    return str;
  }

  void insertEdge(size_t K)(FPoint[K] pts, uint depth) {
    float x = pts[0].x - 0.5;
    float y = pts[0].y - 0.5;

    foreach(i; 1 .. K) {
      float nx = pts[i].x - 0.5;
      float ny = pts[i].y - 0.5;

      // TODO: evaluate vs. intersection calculation
      if (x * nx < -1e-5 || y * ny < -1e-5) {
        auto ptss = splitBezier(pts, 0.5);
        insertEdge(ptss[0], depth);
        insertEdge(ptss[1], depth);
        return;
      }

      x += nx;
      y += ny;
    }

    Quadrant q;
    q.right = !(x < 0.0);
    q.bottom = !(y < 0.0);
    insertInto(q, pts, depth);
  }

  void insertInto(size_t K)(Quadrant q, FPoint[K] pts, uint depth) {
    auto qpt = FPoint(q.right, q.bottom);
    foreach(ref pt; pts)
      pt = pt * 2 - qpt;
    calcCoeffs(pts, q);
    if (depth > 0)
      getChild(q.idx).insertEdge(pts, --depth);
  }

  void calcCoeffs(size_t K)(FPoint[K] pts, Quadrant q)
  {
    auto Kx = (1.f / 4.f) * (pts[$-1].y - pts[0].y);
    auto Ky = (1.f / 4.f) * (pts[0].x - pts[$-1].x);
    static if (K == 2) {
      // auto Lcommon = (1.f / 8.f) * crossProduct(pts[1], pts[0]);
      // auto Ldiff = (1.f / 8.f) * (pts[0].x * pts[0].y - pts[1].x * pts[1].y);

      auto Lx = (1.f / 2.f) * Kx * (pts[0].x + pts[1].x);
      auto Ly = (1.f / 2.f) * Ky * (pts[0].y + pts[1].y);
    } else static if (K == 3) {
        auto Lcommon = (1.f / 24.f) * (
            2 * (crossProduct(pts[0], pts[1]) + crossProduct(pts[1], pts[2]))
            + crossProduct(pts[0], pts[2])
        );
        auto Ldiff = (3.f / 24.f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y);
        auto Lx = Lcommon + Ldiff;
        auto Ly = Lcommon - Ldiff;
      } else static if (K == 4) {
        auto Lcommon = (1.f / 80.f) * (
            3 * (
                2 * (crossProduct(pts[2], pts[3]) + crossProduct(pts[0], pts[1]))
                + crossProduct(pts[1], pts[2])
                + crossProduct(pts[1], pts[3])
                + crossProduct(pts[0], pts[2])
            )
            + crossProduct(pts[0], pts[3])
        );
        auto Ldiff = (10.f / 80.f) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y);
        auto Lx = Lcommon + Ldiff;
        auto Ly = Lcommon - Ldiff;
      } else
        static assert(0, "more than 4 control points unsupported");

    switch (q.idx) {
    case 0: // (0, 0)
      this.coeffs[0] += Lx;
      this.coeffs[1] += Ly;
      this.coeffs[2] += Lx;

      break;
    case 1: // (1, 0)
      this.coeffs[0] += Kx - Lx;
      this.coeffs[1] += Ly;
      this.coeffs[2] += Kx - Lx;

      break;
    case 2: // (0, 1)
      this.coeffs[0] += Lx;
      this.coeffs[1] += Ky - Ly;
      this.coeffs[2] += -Lx;

      break;
    case 3: // (1, 1)
      this.coeffs[0] += Kx - Lx;
      this.coeffs[1] += Ky - Ly;
      this.coeffs[2] += -Kx + Lx;

      break;
    default: assert(0);
    }
  }

  ref Node getChild(uint idx) {
    if (this.chmask == 0) {
      children.length = 4; //insertInPlace(pos, Node());
    }
    this.chmask |= (1 << idx);
    return children[idx];
  }

  bool hasChild(uint idx) const {
    return (this.chmask & (1 << idx)) != 0;
  }

  Node[] children;
  float[3] coeffs = 0.0f;
  ubyte chmask;
}


struct WaveletRaster {

  this(uint depth) {
    this.depth = depth;
  }

  void insertEdge(FPoint[2] pts) {
    assert(pointsAreClipped(pts));
    this.rootConst += crossProduct(pts[0], pts[1]) / 2;
    root.insertEdge(pts, depth);
  }

  void insertEdge(FPoint[3] pts) {
    assert(pointsAreClipped(pts));
    this.rootConst += (1.f / 6.f) * (
        2 * (crossProduct(pts[0], pts[1]) + crossProduct(pts[1], pts[2]))
        + crossProduct(pts[0], pts[2]));
    root.insertEdge(pts, depth);
  }

  void insertEdge(FPoint[4] pts) {
    assert(pointsAreClipped(pts));
    this.rootConst += (1.f / 20.f) * (
        6 * crossProduct(pts[0], pts[1]) + 3 * crossProduct(pts[1], pts[2])
        + 6 * crossProduct(pts[2], pts[3]) + 3 * crossProduct(pts[0], pts[2])
        + 3 * crossProduct(pts[1], pts[3]) + 1 * crossProduct(pts[0], pts[3])
    );
    root.insertEdge(pts, depth);
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
  if (n.hasChild(0))
    writeNodeToGrid(n.children[0], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val - n.coeffs[0] + n.coeffs[1] - n.coeffs[2];
  offset.x += locRes2;
  if (n.hasChild(1))
    writeNodeToGrid(n.children[1], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val + n.coeffs[0] - n.coeffs[1] - n.coeffs[2];
  offset.x -= locRes2;
  offset.y += locRes2;
  if (n.hasChild(2))
    writeNodeToGrid(n.children[2], cval, offset, grid, locRes2, globRes);
  else
    writeGridValue(cval, offset, grid, locRes2, globRes);

  cval = val - n.coeffs[0] - n.coeffs[1] + n.coeffs[2];
  offset.x += locRes2;
  if (n.hasChild(3))
    writeNodeToGrid(n.children[3], cval, offset, grid, locRes2, globRes);
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
  enum Depth = 12;
  enum Resolution = 1 << Depth;
  auto bmp = Bitmap();
  bmp.setConfig(Bitmap.Config.A8, Resolution, Resolution);
  bmp.getBuffer!ubyte()[] = 127;
  void runInsert() {
    WaveletRaster wr = WaveletRaster(Depth-1);
    wr.insertEdge([FPoint(0, 0), FPoint(1.f/3.f, 1.f/3.f), FPoint(0.75, 0.75), FPoint(1., 1.)]);
    wr.insertEdge([FPoint(1., 1.), FPoint(0., 1.)]);
    wr.insertEdge([FPoint(0., 1.), FPoint(0., 0.)]);

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