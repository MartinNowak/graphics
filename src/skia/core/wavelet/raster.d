module skia.core.wavelet.raster;

import std.algorithm, std.array, std.bitmanip, std.math, std.random, std.typecons, std.conv : to;
import std.datetime : benchmark, StopWatch;
import skia.math.clamp, skia.math.rounding, skia.util.format, skia.bezier.chop,
  skia.core.edge_detail.algo, skia.core.path, skia.core.blitter,
  skia.core.matrix, skia.math.fixed_ary, skia.bezier.cartesian;
import guip.bitmap, guip.point, guip.rect, guip.size;

// version=DebugNoise;

struct Node {
  @property string toString() const {
    auto str = fmtString("Node coeffs:%s", coeffs);
    foreach(i; 0 .. 4)
      if (hasChild(i))
        str ~= fmtString("\n%d:%s", i, children[i].toString());
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

      if (bottom) {
        if (right) {
          // (1, 1)
          pos.x -= half;
          pos.y -= half;
          foreach(i; 0 .. K) {
            pts[i].x -= half;
            pts[i].y -= half;
          }
          node.calcCoeffsQ!"11"(pts, half);
        } else {
          // (0, 1)
          pos.y -= half;
          foreach(i; 0 .. K)
            pts[i].y -= half;
          node.calcCoeffsQ!"01"(pts, half);
        }
      } else {
        if (right) {
          // (1, 0)
          pos.x -= half;
          foreach(i; 0 .. K)
            pts[i].x -= half;
          node.calcCoeffsQ!"10"(pts, half);
        } else {
          // (0, 0)
          node.calcCoeffsQ!"00"(pts, half);
        }
      }

      if (depth == 0)
        break;
      const qidx = bottom << 1 | right;
      node = &node.getChild(depth, qidx);
    }
  }

  void calcCoeffsQ(string quad, size_t K)(ref const FPoint[K] pts, uint scale) {
    const rscale = 1.0 / scale;

    const Kx = (1.f / 4.f) * (pts[$-1].y - pts[0].y) * rscale;
    const Ky = (1.f / 4.f) * (pts[0].x - pts[$-1].x) * rscale;

    static if (K == 2) {
      const Lx = (1.f / 2.f) * Kx * (pts[0].x + pts[1].x) * rscale;
      const Ly = (1.f / 2.f) * Ky * (pts[0].y + pts[1].y) * rscale;
    } else static if (K == 3) {
        const Lcommon = (1.f / 24.f) * (
            2 * (determinant(pts[0], pts[1]) + determinant(pts[1], pts[2]))
            + determinant(pts[0], pts[2])
        ) * rscale * rscale;
        const Ldiff = (3.f / 24.f) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y)  * rscale * rscale;
        const Lx = Lcommon + Ldiff;
        const Ly = Lcommon - Ldiff;
    } else static if (K == 4) {
        const Lcommon = (1.f / 80.f) * (
            3 * (
                2 * (determinant(pts[2], pts[3]) + determinant(pts[0], pts[1]))
                + determinant(pts[1], pts[2])
                + determinant(pts[1], pts[3])
                + determinant(pts[0], pts[2])
            )
            + determinant(pts[0], pts[3])
        ) * rscale * rscale;
        const Ldiff = (10.f / 80.f) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y)  * rscale * rscale;
        const Lx = Lcommon + Ldiff;
        const Ly = Lcommon - Ldiff;
    } else
      static assert(0);

    static if (quad == "00") {
        this.coeffs[0] += Lx;
        this.coeffs[1] += Ly;
        this.coeffs[2] += Lx;
    } else static if (quad == "10") {
        this.coeffs[0] += Kx - Lx;
        this.coeffs[1] += Ly;
        this.coeffs[2] += Kx - Lx;
    } else static if (quad == "01") {
        this.coeffs[0] += Lx;
        this.coeffs[1] += Ky - Ly;
        this.coeffs[2] += -Lx;
    } else static if (quad == "11") {
        this.coeffs[0] += Kx - Lx;
        this.coeffs[1] += Ky - Ly;
        this.coeffs[2] += -Kx + Lx;
    } else
      static assert(0);
  }

  ref Node getChild(uint depth, uint idx) {
    assert(depth > 0);
    assert(children.length == 0 || children.length == 4 || children.length == 20);

    if (children.length == 0) {
      if (depth > 1) {
        children.length = 20;
        foreach(i; 0 .. 4)
          children[i].children = children[4 * i + 4 .. 4 * i + 8];
      } else
        children.length = 4;
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

bool benchCalcCoeffs(Node node, FPoint[2][100] ptss, Quadrant q, uint shift) {
  uint scale = (1 << (shift & 0xF));
  foreach(ref pts; ptss)
    node.calcCoeffs(pts, q, scale);
  return true;
}

struct WaveletRaster {

  this(IRect clipRect) {
    this.depth = to!uint(ceil(log2(max(clipRect.width, clipRect.height))));
    assert(this.depth);
    this.clipRect = clipRect;
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 2) {
    this.rootConst += (1.f / (1 << this.depth) ^^ 2) * determinant(slice[0], slice[1]) / 2;
    this.root.insertEdge(pos, slice, this.depth);
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 3) {
    this.rootConst += (1.f / (6.f * (1 << this.depth) ^^ 2)) * (
        2 * (determinant(slice[0], slice[1]) + determinant(slice[1], slice[2]))
        + determinant(slice[0], slice[2]));
    root.insertEdge(pos, slice, depth);
  }

  void insertSlice(size_t K)(IPoint pos, ref FPoint[K] slice) if (K == 4) {
    this.rootConst += (1.f / (20.f * (1 << this.depth) ^^ 2)) * (
        6 * determinant(slice[0], slice[1]) + 3 * determinant(slice[1], slice[2])
        + 6 * determinant(slice[2], slice[3]) + 3 * determinant(slice[0], slice[2])
        + 3 * determinant(slice[1], slice[3]) + 1 * determinant(slice[0], slice[3])
    );
    root.insertEdge(pos, slice, this.depth);
  };

  void insertEdge(FPoint[2] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    auto insertDg = &this.insertSlice!2;
    cartesianBezierWalker!(insertDg)(pts, FRect(fRect(this.clipRect).size), FSize(1, 1));
  }

  void insertEdge(FPoint[3] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    auto insertDg = &this.insertSlice!3;
    cartesianBezierWalker!(insertDg)(pts, FRect(fRect(this.clipRect).size), FSize(1, 1));
  }

  void insertEdge(FPoint[4] pts) {
    //    assert(pointsAreClipped(pts), to!string(pts));
    foreach(ref pt; pts)
      pt -= fPoint(this.clipRect.pos);
    auto insertDg = &this.insertSlice!4;
    cartesianBezierWalker!(insertDg)(pts, FRect(fRect(this.clipRect).size), FSize(1, 1));
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

WaveletRaster pathToWavelet(in Path path, IRect clip) {
  auto ir = path.ibounds;
  if (!ir.intersect(clip))
    return WaveletRaster.init;
  WaveletRaster wr = WaveletRaster(ir);

  path.forEach((Path.Verb verb, in FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move, Path.Verb.Close:
        break;
      case Path.Verb.Line:
        wr.insertEdge(fixedAry!2(pts));
        break;
      case Path.Verb.Quad:
        wr.insertEdge(fixedAry!3(pts));
        break;
      case Path.Verb.Cubic:
        wr.insertEdge(fixedAry!4(pts));
        break;
      }
    });
  return wr;
}

alias void delegate(int y, int xstart, int xend, ubyte val) BmpBlitDg;

BmpBlitDg bmpBlit(Bitmap bitmap) {
  auto grid = bitmap.getBuffer!ubyte();
  void blitBlack(int y, int xstart, int xend, ubyte alpha) {
    auto off = y * bitmap.width + xstart;
    grid[off .. off + xend - xstart] = cast(ubyte)(255 - alpha);
  }
  return &blitBlack;
}
