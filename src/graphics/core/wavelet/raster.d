module graphics.core.wavelet.raster;

import std.algorithm, std.array, std.bitmanip, std.conv, std.math, std.metastrings,
    std.random, std.string, std.typecons, std.c.string, core.bitop;
import std.allocators.region;
import graphics.math.clamp, graphics.bezier.chop,
    graphics.core.path, graphics.core.blitter, graphics.core.matrix, graphics.bezier.cartesian, graphics.bezier.clip;
import guip.bitmap, guip.point, guip.rect, guip.size;

// version=DebugNoise;
// version=StackStats;
// version=calcCoeffs_C;

version (calcCoeffs_C)
{
    extern(C)
    {
        void calcCoeffs_2(IPoint pos, uint half, FPoint* pts, float* coeffs);
        void calcCoeffs_3(IPoint pos, uint half, FPoint* pts, float* coeffs);
        void calcCoeffs_4(IPoint pos, uint half, FPoint* pts, float* coeffs);
    }
}
else
{
    import graphics.core.wavelet.calc_coeffs;
    alias calcCoeffs!2 calcCoeffs_2;
    alias calcCoeffs!3 calcCoeffs_3;
    alias calcCoeffs!4 calcCoeffs_4;
}

struct Node
{
    @property string toString() const
    {
        auto str = std.string.format("Node coeffs:%s", coeffs);
        foreach(i; 0 .. 4)
            if (hasChild(i))
                str ~= std.string.format("\n%d:%s", i, children[i].toString());
        return str;
    }

    ref Node getChild(uint idx, ref RegionAllocator alloc)
    {
        if (_children is null)
            _children = allocNodes(alloc);;
        this.chmask |= (1 << idx);
        return children[idx];
    }

    bool hasChild(uint idx) const
    {
        return (this.chmask & (1 << idx)) != 0;
    }

    static Node[4]* allocNodes(ref RegionAllocator alloc)
    {
        auto res = cast(Node[4]*)alloc.allocate(4 * Node.sizeof);
        foreach(i; 0 .. 4)
            res[i] = Node.init;
        return res;
    }

    ref Node[4] children() { return *_children; }
    ref const(Node[4]) children() const { return *_children; }

    Node[4]* _children;
    float[3] coeffs = 0.0f;
    ubyte chmask;
}


struct WaveletRaster
{
    this(IRect clipRect)
    in
    {
        assert(!clipRect.empty);
    }
    body
    {
        immutable msz = max(clipRect.width, clipRect.height);
        _depth = bsr(msz);
        if (msz & (1 << _depth) - 1) // round up
            ++_depth;
        _clipRect = clipRect;
        _ralloc = newRegionAllocator();
        _tStack = _ralloc.newArray!(float[])(_depth);
        _nodeStack = _ralloc.newArray!(Node*[])(_depth);
        _nodeStack[0] = _ralloc.create!Node();
    }

    void insertSlice2(ref const FPoint[2] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.f / (1 << _depth) ^^ 2) * determinant(slice[0], slice[1]) / 2;
    }

    void insertSlice3(ref const FPoint[3] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.f / (6.f * (1 << _depth) ^^ 2)) * (
            2 * (determinant(slice[0], slice[1]) + determinant(slice[1], slice[2]))
            + determinant(slice[0], slice[2]));
    }

    void insertSlice4(ref const FPoint[4] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.f / (20.f * (1 << _depth) ^^ 2)) * (
            6 * determinant(slice[0], slice[1]) + 3 * determinant(slice[1], slice[2])
            + 6 * determinant(slice[2], slice[3]) + 3 * determinant(slice[0], slice[2])
            + 3 * determinant(slice[1], slice[3]) + 1 * determinant(slice[0], slice[3])
        );
    }

    void updateCoeffs(size_t K)(ref const FPoint[K] curve)
    {
        auto center = FPoint(0.5 * _clipRect.width, 0.5 * _clipRect.height);
        auto cartesian = cartesianBezierWalker(curve, center);
        auto pos = cartesian.pos;

        _tStack[] = 0.0f;
        for (size_t d = 0; d < _depth - 1; ++d)
        {
            immutable half = 1 << _depth - d - 1;
            immutable qidx = !!(pos.y & half) << 1 | !!(pos.x & half);
            _nodeStack[d + 1] = &_nodeStack[d].getChild(qidx, _ralloc);
        }

        for (bool cont=true; cont;)
        {
            double nt = void;
            size_t nup = void;
            IPoint npos = void;
            if (cartesian.empty)
            {
                cont = false;
                nt = 1.0;
                nup = _depth - 1;
            }
            else
            {
                nt = cartesian.front;
                cartesian.popFront;
                npos = cartesian.pos;
                assert(npos != pos);
                nup = bsr(npos.x ^ pos.x | npos.y ^ pos.y);
                assert(nup < _depth, std.string.format("%s %s %s", nt, pos, npos));
            }

            do
            {
                FPoint[K] tmp = void;
                sliceBezier(curve, _tStack[$-nup-1], nt, tmp);
                _tStack[$-nup-1] = nt;
                immutable half = 1 << nup;
                version (calcCoeffs_C)
                    mixin(Format!(q{calcCoeffs_%s(pos, half, tmp.ptr, _nodeStack[$-nup-1].coeffs.ptr);}, K));
                else
                    calcCoeffs!K(pos, half, tmp, _nodeStack[$-nup-1].coeffs);

                if (cont && nup + 1 < _depth) // update node stack, but not the root node
                {
                    immutable qidx = !!(npos.y & 2 * half) << 1 | !!(npos.x & 2 * half);
                    _nodeStack[$-nup-1] = &_nodeStack[$-nup-2].getChild(qidx, _ralloc);
                }
            } while (nup--);

            if (cont)
                pos = npos;
        }
    }

    void insertEdge(FPoint[2] pts)
    {
        foreach(ref pt; pts)
            pt -= fPoint(_clipRect.pos);
        clippedMonotonic(pts, FRect(0, 0, _clipRect.width, _clipRect.height), &insertSlice2, &insertSlice2);
    }

    void insertEdge(FPoint[3] pts)
    {
        foreach(ref pt; pts)
            pt -= fPoint(_clipRect.pos);
        clippedMonotonic(pts, FRect(0, 0, _clipRect.width, _clipRect.height), &insertSlice3, &insertSlice2);
    }

    void insertEdge(FPoint[4] pts)
    {
        foreach(ref pt; pts)
            pt -= fPoint(_clipRect.pos);
        clippedMonotonic(pts, FRect(0, 0, _clipRect.width, _clipRect.height), &insertSlice4, &insertSlice2);
    }

    Node _root;
    float _rootConst = 0.0f;
    uint _depth;
    IRect _clipRect;
    RegionAllocator _ralloc;
    float[] _tStack;
    Node*[] _nodeStack;
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
  auto topLeft = wr._clipRect.pos;
  void blitRow(int y, int xstart, int xend, ubyte alpha) {
    if (fitsIntoRange!("[)")(y, max(ystart, clip.top), min(yend, clip.bottom))) {
      blitter.blitAlphaH(y, clampToRange(xstart, clip.left, clip.right), clampToRange(xend, clip.left, clip.right), alpha);
    }
  }
  writeNodeToGrid!(blitRow)(
      *wr._nodeStack[0], wr._rootConst, topLeft, 1 << wr._depth);
}

WaveletRaster pathToWavelet(in Path path, IRect clip)
{
    auto ir = path.ibounds;
    if (!ir.intersect(clip))
        return WaveletRaster.init;
    WaveletRaster wr = WaveletRaster(ir);

    foreach(verb, pts; path)
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
    };
    return wr;
}
