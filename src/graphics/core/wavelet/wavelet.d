module graphics.core.wavelet.wavelet;

import std.algorithm, std.array, std.bitmanip, std.conv, std.math, std.metastrings,
    std.random, std.string, std.typecons, std.c.string, core.bitop;
import std.allocators.region;
import graphics.bezier.cartesian, graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import graphics.math.clamp, graphics.math.poly;
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
            _children = allocNodes(alloc);
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
        _nodeStack[$-1] = _ralloc.create!Node();
    }

    void insertSlice(ref const FPoint[2] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.0f / (1 << _depth) ^^ 2) * determinant(slice[0], slice[1]) / 2;
    }

    void insertSlice(ref const FPoint[3] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.0f / (6.0f * (1 << _depth) ^^ 2)) * (
            2 * (determinant(slice[0], slice[1]) + determinant(slice[1], slice[2]))
            + determinant(slice[0], slice[2]));
    }

    void insertSlice(ref const FPoint[4] slice)
    {
        if (_depth)
            updateCoeffs(slice);

        _rootConst += (1.0f / (20.0f * (1 << _depth) ^^ 2)) * (
            6 * determinant(slice[0], slice[1]) + 3 * determinant(slice[1], slice[2])
            + 6 * determinant(slice[2], slice[3]) + 3 * determinant(slice[0], slice[2])
            + 3 * determinant(slice[1], slice[3]) + 1 * determinant(slice[0], slice[3])
        );
    }

    void updateCoeffs(size_t K)(ref const FPoint[K] curve)
    {
        _tStack[] = 0;

        immutable center = FPoint(0.5 * _clipRect.width, 0.5 * _clipRect.height);
        auto cartesian = cartesianBezierWalker!(float, K)(curve, center);
        auto g0 = cartesian.pos;
        getNodes(_depth - 1, g0);

        // Iterate of all crossings of a bezier curve with
        // cartesian coordinates. At each crossing we need to
        // create a slice of the curve and update the wavelet
        // coefficients. Higher levels are updated every 2^N
        // crossings.
        foreach(t1, g1; cartesian)
        {
            assert(g0 != g1);

            // number of log2 levels to update determined by number of bits
            // changed in grid coordinates
            immutable nup = 1 + bsr(g0.x ^ g1.x | g0.y ^ g1.y);
            assert(nup <= _depth);

            updateNodes(curve, g0, t1, nup);

            // shift grid position and update node stack
            _tStack[0 .. nup] = t1;
            g0 = g1;

            getNodes(nup, g1);
        }

        // Finish off the remaining non-grid part
        if (_tStack[0] < 1.0f)
        {
            updateNodes(curve, g0, 1.0f, _depth);
        }
    }

    private void getNodes(size_t depth, IPoint pos)
    {
        for (size_t d = min(depth, _depth - 1); d; --d)
        {
            immutable half = 1 << d;
            immutable qidx = !!(pos.y & half) << 1 | !!(pos.x & half);
            _nodeStack[d-1] = &_nodeStack[d].getChild(qidx, _ralloc);
        }
    }

    private void updateNodes(size_t K)
        (ref const FPoint[K] curve, ref const IPoint pos, float t1, size_t depth)
    {
        for (size_t d = 0; d < depth; ++d)
        {
            FPoint[K] tmp = void;
            immutable t0 = _tStack[d];
            sliceBezier(curve, t0, t1, tmp);

            // Update wavelet coefficient for this node/level.
            immutable half = 1 << d;
            version (calcCoeffs_C)
                mixin(Format!(q{calcCoeffs_%s(pos, half, tmp.ptr, _nodeStack[d].coeffs.ptr);}, K));
            else
                calcCoeffs!K(pos, half, tmp, _nodeStack[d].coeffs);
        }
    }

    void insertEdge(size_t K)(ref FPoint[K] pts)
    {
        immutable off = fPoint(_clipRect.pos);
        foreach(i; SIota!(0, K))
            pts[i] -= off;
        clippedMonotonic!(float, K)(pts, FRect(0, 0, _clipRect.width, _clipRect.height), &insertSlice, &insertSlice);
    }

    alias void delegate(int y, int xstart, int xend, ubyte alpha) BlitDg;

    void blit(scope BlitDg dg)
    {
        if (_clipRect.empty)
            return;

        // TODO: avoid bound checks
        void blitRow(int y, int xstart, int xend, ubyte alpha)
        {
            if (fitsIntoRange!("[)")(y, _clipRect.top, _clipRect.bottom))
            {
                dg(y, clampToRange(xstart, _clipRect.left, _clipRect.right),
                   clampToRange(xend, _clipRect.left, _clipRect.right), alpha);
            }
        }

        writeNodeToGrid!(blitRow)(
            *_nodeStack[$-1], _rootConst, _clipRect.pos, 1 << _depth);
    }

    Node _root;
    float _rootConst = 0.0f;
    uint _depth;
    IRect _clipRect;

    RegionAllocator _ralloc;

    // temporary space allocated from _ralloc
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
