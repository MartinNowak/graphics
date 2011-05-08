module skia.core.wavelet.raster;

import std.algorithm, std.array, std.bitmanip, std.math, std.random, std.typecons, std.conv : to;
import std.datetime : benchmark, StopWatch;
import skia.math.clamp, skia.math.rounding, skia.util.format,
  skia.core.edge_detail.algo, skia.core.path, skia.core.blitter,
  skia.core.matrix, skia.math.fixed_ary;
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

  void insertEdge(size_t K)(FPoint[K] pts, uint depth) {
    auto q0 = Quadrant(pts[0]);
    if (approxEqual(pts[0].x, 0.5))
      q0.right = side(pts[1].x);
    if (approxEqual(pts[0].y, 0.5))
      q0.bottom = side(pts[1].y);

    bool mayNeedHSplit, mayNeedVSplit;
    foreach(pt; pts) {
      if (side(pt.x) != q0.right)
        mayNeedHSplit = true;
      if (side(pt.y) != q0.bottom)
        mayNeedVSplit = true;
    }

    bool insertSplitV(FPoint[K] ypts, Quadrant qv) {
      if (!mayNeedVSplit) {
        insertInto(qv, ypts, depth);
        return qv.bottom;
      }

      double[K-1] yts;
      auto ysplits = findRoots!("y")(ypts, 0.5, yts[0 .. K-1]);
      if (ysplits.empty) {
        insertInto(qv, ypts, depth);
        // if pts[$-1].y ~ 0.5 this may be a hidden vertical transition, so reevaluate
      } else {
        auto ptss = splitBezier(ypts, ysplits.front);
        auto lastT = ysplits.front; ysplits.popFront;
        insertInto(qv, ptss[0], depth); qv.bottom = !qv.bottom;
        while (!ysplits.empty) {
          ptss = splitBezier(ptss[1], (ysplits.front - lastT) / (1.0 - lastT));
          lastT = ysplits.front; ysplits.popFront;
          insertInto(qv, ptss[0], depth); qv.bottom = !qv.bottom;
        }
        insertInto(qv, ptss[1], depth);
      }
      return qv.bottom;
    }

    void insertSplitH(FPoint[K] xpts) {
      if (!mayNeedHSplit) {
        q0.bottom = insertSplitV(xpts, q0);
        return;
      }

      double[K-1] xts;
      auto xsplits = findRoots!("x")(xpts, 0.5, xts[0 .. K-1]);
      if (xsplits.empty)
        insertSplitV(xpts, q0);
      else {
        auto ptss = splitBezier(pts, xsplits.front);
        auto lastT = xsplits.front; xsplits.popFront;
        q0.bottom = insertSplitV(ptss[0], q0); q0.right = !q0.right;
        while (!xsplits.empty) {
          ptss = splitBezier(ptss[1], (xsplits.front - lastT) / (1.0 - lastT));
          lastT = xsplits.front; xsplits.popFront;
          q0.bottom = insertSplitV(ptss[0], q0); q0.right = !q0.right;
        }
        q0.bottom = insertSplitV(ptss[1], q0);
      }
    }

    if (mayNeedHSplit && mayNeedVSplit) {
      double[K-1] xts;
      double[K-1] yts;
      auto xsplits = findRoots!("x")(pts, 0.5, xts[0 .. K-1]);
      auto ysplits = findRoots!("y")(pts, 0.5, yts[0 .. K-1]);
      bool hasSplits() {
        return !xsplits.empty || !ysplits.empty;
      }
      Tuple!(double, int) getSplit() {
        assert(hasSplits());
        if (xsplits.empty) {
          auto t = ysplits.front; ysplits.popFront;
          return tuple(t, 0x2);
        } else if (ysplits.empty) {
          auto t = xsplits.front; xsplits.popFront;
          return tuple(t, 0x1);
        } else if (approxEqual(xsplits.front, ysplits.front)) {
          auto t = 0.5 * (xsplits.front + ysplits.front);
          xsplits.popFront; ysplits.popFront;
          return tuple(t, 0x3);
        } else if (xsplits.front < ysplits.front) {
          auto t = xsplits.front; xsplits.popFront;
          return tuple(t, 0x1);
        } else {
          assert(!ysplits.empty);
          auto t = ysplits.front; ysplits.popFront;
          return tuple(t, 0x2);
        }
      }
      if (hasSplits()) {
        auto sp = getSplit();
        auto ptss = splitBezier(pts, sp[0]);
        auto lastT = sp[0];
        insertInto(q0, ptss[0], depth); q0.idx ^= sp[1];
        while (hasSplits()) {
          sp = getSplit();
          ptss = splitBezier(ptss[1], (sp[0] - lastT) / (1.0 - lastT));
          lastT = sp[0];
          insertInto(q0, ptss[0], depth); q0.idx ^= sp[1];
        }
        insertInto(q0, ptss[1], depth);
      }
    } else if (mayNeedHSplit) {
      double[K-1] xts;
      auto xsplits = findRoots!("x")(pts, 0.5, xts[0 .. K-1]);
      if (!xsplits.empty) {
        auto ptss = splitBezier(pts, xsplits.front);
        auto lastT = xsplits.front; xsplits.popFront;
        insertInto(q0, ptss[0], depth); q0.right = !q0.right;
        while (!xsplits.empty) {
          ptss = splitBezier(ptss[1], (xsplits.front - lastT) / (1.0 - lastT));
          lastT = xsplits.front; xsplits.popFront;
          insertInto(q0, ptss[0], depth); q0.right = !q0.right;
        }
        insertInto(q0, ptss[1], depth);
      }
    } else if (mayNeedVSplit) {
      double[K-1] yts;
      auto ysplits = findRoots!("y")(pts, 0.5, yts[0 .. K-1]);
      if (!ysplits.empty) {
        auto ptss = splitBezier(pts, ysplits.front);
        auto lastT = ysplits.front; ysplits.popFront;
        insertInto(q0, ptss[0], depth); q0.bottom = !q0.bottom;
        while (!ysplits.empty) {
          ptss = splitBezier(ptss[1], (ysplits.front - lastT) / (1.0 - lastT));
          lastT = ysplits.front; ysplits.popFront;
          insertInto(q0, ptss[0], depth); q0.bottom = !q0.bottom;
        }
        insertInto(q0, ptss[1], depth);
      }
    } else {
      insertInto(q0, pts, depth);
    }
  }

  void insertInto(size_t K)(Quadrant q, FPoint[K] pts, uint depth) {
    foreach(pt; pts)
      assert(fitsIntoRange!("[]")(pts[0].x, -1e-5, 1.0+1e-5)
             && fitsIntoRange!("[]")(pts[0].y, -1e-5, 1.0+1e-5), to!string(pts) ~ "|" ~ to!string(q));
    foreach(ref pt; pts) {
      pt.x = clampToRange(pt.x * 2 - q.right, 0.0, 1.0);
      pt.y = clampToRange(pt.y * 2 - q.bottom, 0.0, 1.0);
      //      pt = pt*2 - qpt;
    }
    calcCoeffs(pts, q);
    if (depth > 0)
      getChild(q.idx).insertEdge(pts, --depth);
  }

  void calcCoeffs(size_t K)(FPoint[K] pts, Quadrant q)
  {
    auto Kx = (1.f / 4.f) * (pts[$-1].y - pts[0].y);
    auto Ky = (1.f / 4.f) * (pts[0].x - pts[$-1].x);
    static if (K == 2) {
      // auto Lcommon = (1.f / 8.f) * crossProduct(pts[0], pts[1]);
      // auto Ldiff = (1.f / 8.f) * (pts[1].x * pts[1].y - pts[0].x * pts[0].y);

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

/++
double[] findRoots(string xy, size_t K)(FPoint[K] pts, double val, double[] ts) if(K==2) {
  const v0 = mixin(Format!(q{pts[0].%s}, xy));
  const v1 = mixin(Format!(q{pts[1].%s}, xy));
  if ((v0 < val) != (v1 < val)) {
    auto root = (val - v0) / (v1 - v0);
    if (fitsIntoRange!("()")(root, 0.0, 1.0)) {
      ts[0] = root;
      return ts[0 .. 1];
    }
  }
  return ts[0 .. 0];
}

double[] findRoots(string xy, size_t K)(FPoint[K] pts, double val, double[] ts) if(K==3) {
  const v0 = mixin(Format!(q{pts[0].%s}, xy));
  const v1 = mixin(Format!(q{pts[1].%s}, xy));
  const v2 = mixin(Format!(q{pts[2].%s}, xy));
  if ((v0 < val) != (v2 < val)) {
    // one root
    const a = v0 + v2 - 2 * v1;
    const b = 2 * (v1 - v0);
    const c = v0 - val;
    assert(approxEqual(b*b - 4*a*c, 0.0), to!string(b*b - 4*a*c));
    ts[0] = -b / (2 * a);
    return ts[0 .. 1];
  } else if ((v0 < val) != (v1 < val)) {
    // two roots
    const a = v0 + v2 - 2 * v1;
    const b = 2 * (v1 - v0);
    const c = v0 - val;
    const disc = b*b - 4*a*c;
    assert(disc > 0);
    const r = sqrt(disc);
    ts[0] = (-b + r) / (2 * a);
    ts[1] = (-b + r) / (2 * a);
    if (ts[0] > ts[1])
      swap(ts[0], ts[1]);
    return ts[0 .. 2];
  } else {
    // no root
    return ts[0 .. 0];
  }
}
+/

double[] findRoots(string xy, size_t K)(FPoint[K] pts, double val, double[] ts) if(K>1) {
  double vs[K];
  foreach(i, ref v; vs)
    v = mixin(Format!(q{pts[i].%s}, xy)) - val;

  static if (K==2) {
    double evalT(double t) {
      auto oneMt = 1.0 - t;
      return oneMt*vs[0] + t*vs[1];
    }
  } else static if (K==3) {
    double evalT(double t) {
      auto oneMt = 1.0 - t;
      return oneMt*oneMt*vs[0] + 2*oneMt*t*vs[1] + t*t*vs[2];
    }
  } else static if (K==4) {
    double evalT(double t) {
      auto oneMt = 1.0 - t;
      return oneMt*oneMt*oneMt*vs[0] + 3*oneMt*oneMt*t*vs[1] + 3*oneMt*t*t*vs[2] + t*t*t*vs[3];
    }
  }

  //  std.stdio.writef("findRoots vs:%s val:%f.7", vs, val);
  size_t rootcnt;
  foreach(i; 0 .. K-1) {
    auto a = i * cast(double)1. / (K-1);
    auto b = (i + 1) * cast(double)1. / (K-1);
    auto fa = evalT(a);
    auto fb = evalT(b);
    if (signbit(fa) != signbit(fb)) {
      auto r = std.numeric.findRoot(&evalT, a, b, fa, fb, (double lo, double hi) { return false; });
      auto root = fabs(r[2]) !> fabs(r[3]) ? r[0] : r[1];
      if (fitsIntoRange!("()")(root, 0.0, 1.0))
        ts[rootcnt++] = root;
    }
  }
  //  std.stdio.writeln("\t", ts[0 .. rootcnt]);
  return ts[0 .. rootcnt];
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
    assert(pointsAreClipped(pts), to!string(pts));
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
  const depth = to!uint(ceil(log2(max(ir.width, ir.height))));
  WaveletRaster wr = WaveletRaster(depth - 1);
  const res = 1 << depth;

  Matrix m;
  m.reset();
  m.setTranslate(-ir.pos.x, -ir.pos.y);
  m.preScale(1.0f / res, 1.0f / res);
  auto transformed = Path(path);
  transformed.transform(m);

  transformed.forEach((Path.Verb verb, in FPoint[] pts) {
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
