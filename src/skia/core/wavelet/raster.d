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

  void insertEdge(size_t K)(IPoint pos, ref FPoint[K] pts, uint depth)
  in {
    fitsIntoRange!("[]")(pos.x >> depth, 0, 1);
    fitsIntoRange!("[]")(pos.y >> depth, 0, 1);
  } body {
    Quadrant q;
    q.right = pos.x >= 1 << depth;
    q.bottom = pos.y >= 1 << depth;

    debug {
      foreach(pt; pts)
        assert(fitsIntoRange!("[]")(pt.x, -1e-2, (1<<depth+1)+1e-2)
               && fitsIntoRange!("[]")(pt.y, -1e-2, (1<<depth+1)+1e-2),
               to!string(pts) ~ "|" ~ to!string(q)~ "|" ~ to!string(depth));
    }

    auto shift = IPoint(q.right, q.bottom) * (1 << depth);
    auto fshift = fPoint(shift);
    foreach(ref pt; pts) {
      pt -= fshift;
      pt.x = clampToRange(pt.x, 0, (1<<depth));
      pt.y = clampToRange(pt.y, 0, (1<<depth));
    }
    //    std.stdio.writefln("\t dpth:%s pos:%s sh:%s pts:%s", depth, pos, fshift, pts);
    calcCoeffs(pts, q, (1 << depth));
    if (depth > 0) {
      pos -= shift;
      getChild(q.idx).insertEdge(pos, pts, depth-1);
    }
  }

  void calcCoeffs(size_t K)(ref const FPoint[K] pts, Quadrant q, uint scale)
  {
    auto Kx = (1.f / (scale * 4.f)) * (pts[$-1].y - pts[0].y);
    auto Ky = (1.f / (scale * 4.f)) * (pts[0].x - pts[$-1].x);
    static if (K == 2) {
      // auto Lcommon = (1.f / 8.f) * crossProduct(pts[0], pts[1]);
      // auto Ldiff = (1.f / 8.f) * (pts[1].x * pts[1].y - pts[0].x * pts[0].y);

      auto Lx = (1.f / (scale * 2.f)) * Kx * (pts[0].x + pts[1].x);
      auto Ly = (1.f / (scale * 2.f)) * Ky * (pts[0].y + pts[1].y);
    } else static if (K == 3) {
        auto Lcommon = (1.f / (scale * scale * 24.f)) * (
            2 * (crossProduct(pts[0], pts[1]) + crossProduct(pts[1], pts[2]))
            + crossProduct(pts[0], pts[2])
        );
        auto Ldiff = (3.f / (scale * scale * 24.f)) * (pts[2].x*pts[2].y - pts[0].x * pts[0].y);
        auto Lx = Lcommon + Ldiff;
        auto Ly = Lcommon - Ldiff;
      } else static if (K == 4) {
        auto Lcommon = (1.f / (scale * scale * 80.f)) * (
            3 * (
                2 * (crossProduct(pts[2], pts[3]) + crossProduct(pts[0], pts[1]))
                + crossProduct(pts[1], pts[2])
                + crossProduct(pts[1], pts[3])
                + crossProduct(pts[0], pts[2])
            )
            + crossProduct(pts[0], pts[3])
        );
        auto Ldiff = (10.f / (scale * scale * 80.f)) * (pts[3].x * pts[3].y - pts[0].x * pts[0].y);
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
    if (children.length != 4) {
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

  this(IRect clipRect) {
    this.depth = to!uint(ceil(log2(max(clipRect.width, clipRect.height)))) - 1;
    this.clipRect = fRect(clipRect);
  }

  void insertEdge(FPoint[2] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= this.clipRect.pos;
    auto insertDg = (IPoint pos, FPoint[2] slice) {
      this.rootConst += (1.f / (1 << depth + 1) ^^ 2) * crossProduct(slice[0], slice[1]) / 2;
      root.insertEdge(pos, slice, depth);
    };
    cartesianBezierWalker!(insertDg)(pts, FRect(this.clipRect.size), FSize(1, 1));
  }

  void insertEdge(FPoint[3] pts) {
    //    assert(pointsAreClipped(pts));
    foreach(ref pt; pts)
      pt -= this.clipRect.pos;
    auto insertDg = (IPoint pos, FPoint[3] slice) {
      this.rootConst += (1.f / (6.f * (1 << depth + 1) ^^ 2)) * (
          2 * (crossProduct(slice[0], slice[1]) + crossProduct(slice[1], slice[2]))
          + crossProduct(slice[0], slice[2]));
      root.insertEdge(pos, slice, depth);
    };
    cartesianBezierWalker!(insertDg)(pts, FRect(this.clipRect.size), FSize(1, 1));
  }

  void insertEdge(FPoint[4] pts) {
    //    assert(pointsAreClipped(pts), to!string(pts));
    foreach(ref pt; pts)
      pt -= this.clipRect.pos;
    auto insertDg = (IPoint pos, FPoint[4] slice) {
      this.rootConst += (1.f / (20.f * (1 << depth + 1) ^^ 2)) * (
          6 * crossProduct(slice[0], slice[1]) + 3 * crossProduct(slice[1], slice[2])
          + 6 * crossProduct(slice[2], slice[3]) + 3 * crossProduct(slice[0], slice[2])
          + 3 * crossProduct(slice[1], slice[3]) + 1 * crossProduct(slice[0], slice[3])
      );
      root.insertEdge(pos, slice, depth);
    };
    cartesianBezierWalker!(insertDg)(pts, FRect(this.clipRect.size), FSize(1, 1));
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
  FRect clipRect;
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

void blitEdges(in Path path, IRect clip, Blitter blitter, int ystart, int yend) {
  auto wr = pathToWavelet(path);
  auto ir = path.ibounds;
  void blitRow(int y, int xstart, int xend, ubyte alpha) {
    if (fitsIntoRange!("[]")(y + ir.top, ystart, yend)) {
      blitter.blitAlphaH(y + ir.top, ir.left + xstart, ir.left + xend, alpha);
    }
  }
  writeNodeToGrid!(blitRow)(
      wr.root, wr.rootConst, IPoint(0, 0), 1<<(wr.depth + 1));
}

WaveletRaster pathToWavelet(in Path path) {
  auto ir = path.ibounds;
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
