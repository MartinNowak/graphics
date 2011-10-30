module graphics.core.wavelet.raster;

import std.algorithm, std.array, std.bitmanip, std.conv, std.math, std.metastrings,
    std.random, std.string, std.typecons, std.c.string;
import std.allocators.region;
import graphics.math.clamp, graphics.math.rounding, graphics.bezier.chop,
    graphics.core.path, graphics.core.blitter, graphics.core.matrix, graphics.bezier.cartesian;
import guip.bitmap, guip.point, guip.rect, guip.size;

// version=DebugNoise;
// version=StackStats;
// version=calcCoeffs_C;

version (calcCoeffs_C) {
  extern(C) {
    void calcCoeffs_2(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
    void calcCoeffs_3(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
    void calcCoeffs_4(uint half, uint qidx, IPoint* pos, const FPoint* pts, float* coeffs);
  }
} else {
  import graphics.core.wavelet.calc_coeffs;
  alias calcCoeffs!2 calcCoeffs_2;
  alias calcCoeffs!3 calcCoeffs_3;
  alias calcCoeffs!4 calcCoeffs_4;
}

struct Node {
  @property string toString() const {
    auto str = std.string.format("Node coeffs:%s", coeffs);
    foreach(i; 0 .. 4)
      if (hasChild(i))
        str ~= std.string.format("\n%d:%s", i, children[i].toString());
    return str;
  }

  void insertEdge(size_t K)(IPoint pos, FPoint[K] pts, uint depth)
  in {
    fitsIntoRange!("[)")(pos.x, 0, 1 << depth);
    fitsIntoRange!("[)")(pos.y, 0, 1 << depth);
  } body {

    auto node = &this;
    for(;;) {

      debug {
        foreach(pt; pts)
          assert(fitsIntoRange!("[]")(pt.x, -1e-1, (1<<depth+1)+1e-1)
                 && fitsIntoRange!("[]")(pt.y, -1e-1, (1<<depth+1)+1e-1),
                 to!string(pts) ~ "|" ~ to!string(depth));
      }

      const half = 1 << --depth;
      const right = pos.x >= half;
      const bottom = pos.y >= half;
      const qidx = bottom << 1 | right;

      version (calcCoeffs_C)
        mixin(Format!(q{calcCoeffs_%s(half, qidx, &pos, pts.ptr, node.coeffs.ptr);}, K));
      else
        calcCoeffs!K(half, qidx, pos, pts, node.coeffs);

      if (depth == 0)
        break;
      node = &node.getChild(qidx);
    }
  }

  ref Node getChild(uint idx) {
    assert(children.length == 0 || children.length == 4 || children.length == 20);

    if (_children is null)
      _children = allocNodes();;
    this.chmask |= (1 << idx);
    return children[idx];
  }

  bool hasChild(uint idx) const {
    return (this.chmask & (1 << idx)) != 0;
  }

  static Node[4]* allocNodes() {
    auto res = cast(Node[4]*)ralloc.allocate(4 * Node.sizeof);
    foreach(i; 0 .. 4)
        res[i] = Node.init;
    return res;
  }

  static RegionAllocator ralloc;

  static void initAllocator() {
    ralloc = newRegionAllocator();
  }

  static void freeAllocator() {
    ralloc = RegionAllocator.init;
  }

  ref Node[4] children() { return *_children; }
  ref const(Node[4]) children() const { return *_children; }

  Node[4]* _children;
  float[3] coeffs = 0.0f;
  ubyte chmask;
}


struct WaveletRaster {
  this(IRect clipRect) {
    this.depth = to!uint(ceil(log2(max(clipRect.width, clipRect.height))));
    this.clipRect = clipRect;
    Node.initAllocator();
  }

  ~this() {
    Node.freeAllocator();
  }

    void insertSlice2(IPoint pos, ref FPoint[2] slice) {
    this.rootConst += (1.f / (1 << this.depth) ^^ 2) * determinant(slice[0], slice[1]) / 2;
    if (this.depth)
      this.root.insertEdge(pos, slice, this.depth);
  }

  void insertSlice3(IPoint pos, ref FPoint[3] slice) {
    this.rootConst += (1.f / (6.f * (1 << this.depth) ^^ 2)) * (
        2 * (determinant(slice[0], slice[1]) + determinant(slice[1], slice[2]))
        + determinant(slice[0], slice[2]));
    if (this.depth)
      root.insertEdge(pos, slice, depth);
  }

  void insertSlice4(IPoint pos, ref FPoint[4] slice) {
    this.rootConst += (1.f / (20.f * (1 << this.depth) ^^ 2)) * (
        6 * determinant(slice[0], slice[1]) + 3 * determinant(slice[1], slice[2])
        + 6 * determinant(slice[2], slice[3]) + 3 * determinant(slice[0], slice[2])
        + 3 * determinant(slice[1], slice[3]) + 1 * determinant(slice[0], slice[3])
    );
    if (this.depth)
      root.insertEdge(pos, slice, this.depth);
  };

  void insertEdge(FPoint[2] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice2, &this.insertSlice2);
  }

  void insertEdge(FPoint[3] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice3, &this.insertSlice2);
  }

  void insertEdge(FPoint[4] pts) {
    //    assert(pointsAreClipped(pts), to!string(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    cartesianBezierWalker(pts, FRect(fRect(this.clipRect).size), FSize(1, 1), &this.insertSlice4, &this.insertSlice2);
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
  IRect clipRect;
}

void writeGridValue(alias blit)(float val, IPoint off, uint locRes) {
  assert(locRes > 0);
  version(DebugNoise) {
    enum noise = 55;
    auto ubval = clampTo!ubyte(abs(val * (255-noise)) + uniform(0, noise));
  } else {
    auto ubval = clampTo!ubyte(abs(val * 255));
  }
  if (ubval == 0)
    return;

  auto left = off.x;
  auto right = off.x + locRes;
  foreach(y; off.y .. off.y + locRes) {
    blit(y, left, right, ubval);
  }
}

void writeNodeToGrid(alias blit, alias timeout=false)
(in Node n, float val, IPoint offset, uint locRes)
{
  // Can happen with only the root node on very small paths
  if (locRes == 1) {
    writeGridValue!blit(val, offset, locRes);
    return;
  }
  assert(locRes > 1);
  uint locRes2 = locRes / 2;
  bool blitLowRes = timeout;

  auto cval = val + n.coeffs[0]  + n.coeffs[1] + n.coeffs[2];
  if (!blitLowRes && n.hasChild(0))
    writeNodeToGrid!blit(n.children[0], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val - n.coeffs[0] + n.coeffs[1] - n.coeffs[2];
  offset.x += locRes2;
  if (!blitLowRes && n.hasChild(1))
    writeNodeToGrid!blit(n.children[1], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val + n.coeffs[0] - n.coeffs[1] - n.coeffs[2];
  offset.x -= locRes2;
  offset.y += locRes2;
  if (!blitLowRes && n.hasChild(2))
    writeNodeToGrid!blit(n.children[2], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);

  cval = val - n.coeffs[0] - n.coeffs[1] + n.coeffs[2];
  offset.x += locRes2;
  if (!blitLowRes && n.hasChild(3))
    writeNodeToGrid!blit(n.children[3], cval, offset, locRes2);
  else
    writeGridValue!blit(cval, offset, locRes2);
}

void blitEdges(in Path path, IRect clip, Blitter blitter, int ystart, int yend) {
  auto wr = pathToWavelet(path, clip);
  auto topLeft = wr.clipRect.pos;
  void blitRow(int y, int xstart, int xend, ubyte alpha) {
    if (fitsIntoRange!("[)")(y, max(ystart, clip.top), min(yend, clip.bottom))) {
      blitter.blitAlphaH(y, clampToRange(xstart, clip.left, clip.right), clampToRange(xend, clip.left, clip.right), alpha);
    }
  }
  writeNodeToGrid!(blitRow)(
      wr.root, wr.rootConst, topLeft, 1<< wr.depth);
}

WaveletRaster pathToWavelet(in Path path, IRect clip)
{
    auto ir = path.ibounds;
    if (!ir.intersect(clip))
        return WaveletRaster.init;
    WaveletRaster wr = WaveletRaster(ir);

    path.forEach((Path.Verb verb, in FPoint[] pts)
    {
        final switch(verb)
        {
        case Path.Verb.Move:
        case Path.Verb.Close:
            break;

        case Path.Verb.Line:
            FPoint[2] fpts = void;
            memcpy(fpts.ptr, pts.ptr, 2 * FPoint.sizeof);
            wr.insertEdge(fpts);
            break;
        case Path.Verb.Quad:
            FPoint[3] fpts = void;
            memcpy(fpts.ptr, pts.ptr, 3 * FPoint.sizeof);
            wr.insertEdge(fpts);
            break;
        case Path.Verb.Cubic:
            FPoint[4] fpts = void;
            memcpy(fpts.ptr, pts.ptr, 4 * FPoint.sizeof);
            wr.insertEdge(fpts);
            break;
        }
    });
    return wr;
}
