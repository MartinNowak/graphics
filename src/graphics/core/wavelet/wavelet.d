module graphics.core.wavelet.wavelet;

import std.algorithm, std.array, std.bitmanip, std.conv, std.math, std.random,
    std.string, std.typecons, std.c.string, core.bitop;
import graphics.bezier.cartesian, graphics.bezier.chop, graphics.bezier.clip, graphics.bezier.curve;
import graphics.math.clamp, graphics.math.poly;
import graphics.core.wavelet.calc_coeffs;
import guip.bitmap, guip.point, guip.rect, guip.size;

// version=DebugNoise;

/// Wavelet coefficients for a 2x2 square, number of pixels depends on depth layer
alias Coeffs = float[3];

/// Convert x/y coordinates to linear quadtree coordinate by spreading
/// x to even and y to odd bits.
uint posToLinQuad(T)(Point!T p)
{
    return posToLinQuad(to!ushort(p.x), to!ushort(p.y));
}

uint posToLinQuad(ushort x, ushort y)
{
    uint ex = x, ey = y;
    // 8
    ex = ex & 0x000000FF | (ex & 0x0000FF00) << 8;
    ey = ey & 0x000000FF | (ey & 0x0000FF00) << 8;
    // 4
    ex = ex & 0x000F000F | (ex & 0x00F000F0) << 4;
    ey = ey & 0x000F000F | (ey & 0x00F000F0) << 4;
    // 2
    ex = ex & 0x03030303 | (ex & 0x0C0C0C0C) << 2;
    ey = ey & 0x03030303 | (ey & 0x0C0C0C0C) << 2;
    // 1
    ex = ex & 0x11111111 | (ex & 0x22222222) << 1;
    ey = ey & 0x11111111 | (ey & 0x22222222) << 1;

    return ex | ey << 1;
}

unittest
{
    assert(posToLinQuad(0, 0) == 0);
    assert(posToLinQuad(1, 1) == 3);
    assert(posToLinQuad(5, 1) == 19);
    assert(posToLinQuad(2, 6) == 44);
    assert(posToLinQuad(6, 2) == 28);
    assert(posToLinQuad(7, 7) == 63);
    assert(posToLinQuad(15, 15) == 255);
    assert(posToLinQuad(ushort.max, ushort.max) == uint.max);
}

Point!ushort linQuadToPos(uint linquad)
{
    uint ex = linquad & 0x55555555, ey = (linquad & 0xAAAAAAAA) >> 1;

    ex = ex & 0x11111111 | (ex & 0x44444444) >> 1;
    ey = ey & 0x11111111 | (ey & 0x44444444) >> 1;

    ex = ex & 0x03030303 | (ex & 0x30303030) >> 2;
    ey = ey & 0x03030303 | (ey & 0x30303030) >> 2;

    ex = ex & 0x000F000F | (ex & 0x0F000F00) >> 4;
    ey = ey & 0x000F000F | (ey & 0x0F000F00) >> 4;

    ex = ex & 0x000000FF | (ex & 0x00FF0000) >> 8;
    ey = ey & 0x000000FF | (ey & 0x00FF0000) >> 8;

    return Point!ushort(ex & 0xFFFF, ey & 0xFFFF);
}

unittest
{
    alias P = Point!ushort;
    assert(linQuadToPos(0) == P(0, 0));
    assert(linQuadToPos(3) == P(1, 1));
    assert(linQuadToPos(19) == P(5, 1));
    assert(linQuadToPos(44) == P(2, 6));
    assert(linQuadToPos(28) == P(6, 2));
    assert(linQuadToPos(63) == P(7, 7));
    assert(linQuadToPos(255) == P(15, 15));
    assert(linQuadToPos(uint.max) == P(ushort.max, ushort.max));
}

// recurrence g(n+1) = 4 * g(n) + 1 has solution
// g(n) = (16 * 4 ^ n - 1) / 12
// (https://www.wolframalpha.com/input/?i=g%28n%2B1%29+%3D+4+*+g%28n%29+%2B+1)
// which is (2 ^ (2 * (n+1)) - 1) / 3
size_t totalNumCoeffs(size_t depth)
{
    return ((1UL << 2 * (depth + 1)) - 1) / 3;
}

unittest
{
    assert(totalNumCoeffs(0) == 1);
    assert(totalNumCoeffs(1) == 5);
    assert(totalNumCoeffs(2) == 21);
    assert(totalNumCoeffs(3) == 85);
}

struct WaveletRaster
{
    import core.stdc.stdlib : calloc, malloc, free;

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
        import std.exception : enforce;
        enforce(_depth <= MAX_DEPTH, "Wavelet size is too big.");
        _clipRect = clipRect;

        foreach (d; 0 .. _depth)
        {
            // TODO: combine allocations
            immutable ncoeffs = (1UL << (_depth - d - 1)) ^^ 2; // -1 because of 2x2 tiles
            _coeffs[d] = (cast(Coeffs*)malloc(ncoeffs * Coeffs.sizeof))[0 .. ncoeffs];
            enum nbits = 8 * size_t.sizeof;
            _coeffMarks[d] = cast(size_t*)calloc((ncoeffs + nbits - 1) / nbits, size_t.sizeof);
        }
    }

    ~this()
    {
        foreach (c; _coeffs)
            free(c.ptr);
        foreach (p; _coeffMarks)
            free(p);
    }

    @disable this(this);

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
        }

        // Finish off the remaining non-grid part
        if (_tStack[0] < 1.0f)
        {
            updateNodes(curve, g0, 1.0f, _depth);
        }
    }

    private void updateNodes(size_t K)
        (ref const FPoint[K] curve, ref const IPoint pos, float t1, size_t depth)
    {
        auto cidx = posToLinQuad(pos);

        for (size_t d = 0; d < depth; ++d)
        {
            FPoint[K] tmp = void;
            immutable t0 = _tStack[d];
            sliceBezier(curve, t0, t1, tmp);

            immutable q = cast(Quad)(cidx % 4);
            cidx /= 4;
            // Update wavelet coefficient for this node/level.
            if (!bts(_coeffMarks[d], cidx))
                _coeffs[d][cidx][] = 0.0f;

            immutable half = 1 << d;
            calcCoeffs!K(pos, half, q, tmp, _coeffs[d][cidx]);
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

        // Can happen with only the root node on very small paths (1x1 pixels)
        if (_depth == 0)
            writeGridValue!blitRow(_rootConst, _clipRect.pos, 1);
        else
            writeToGrid!blitRow(
                _coeffMarks[], _coeffs[], 0, _rootConst, _clipRect.pos, _depth - 1);
    }

    float _rootConst = 0.0f;
    uint _depth;
    IRect _clipRect;

    enum MAX_DEPTH = 15; // limited by ushort for linearQuadtreeCoord
    float[MAX_DEPTH] _tStack;
    Coeffs[][MAX_DEPTH] _coeffs;
    size_t*[MAX_DEPTH] _coeffMarks;
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

void writeToGrid(alias blit, alias timeout=false)
    (in size_t*[] coeffMarks, Coeffs[][] coeffs, uint cidx, float val, IPoint offset, uint depth)
in
{
    assert(depth >= 0);
    assert(coeffMarks.length > depth);
    assert(coeffs.length > depth);
    assert(coeffs.length == coeffMarks.length);
}
body
{
    bool blitLowRes = timeout;

    auto coeff = coeffs[depth][cidx];
    cidx *= 4; // linquad index for next level

    uint locRes = 1U << depth;
    // NW
    auto cval = val + coeff[0] + coeff[1] + coeff[2];
    if (!blitLowRes && depth && bt(coeffMarks[depth-1], cidx + 0b00))
        writeToGrid!blit(coeffMarks, coeffs, cidx + 0b00, cval, offset, depth - 1);
    else
        writeGridValue!blit(cval, offset, locRes);

    // NE
    cval = val - coeff[0] + coeff[1] - coeff[2];
    offset.x += locRes;
    if (!blitLowRes && depth && bt(coeffMarks[depth - 1], cidx + 0b01))
        writeToGrid!blit(coeffMarks, coeffs, cidx + 0b01, cval, offset, depth - 1);
    else
        writeGridValue!blit(cval, offset, locRes);

    // SW
    cval = val + coeff[0] - coeff[1] - coeff[2];
    offset.x -= locRes;
    offset.y += locRes;
    if (!blitLowRes && depth && bt(coeffMarks[depth - 1], cidx + 0b10))
        writeToGrid!blit(coeffMarks, coeffs, cidx + 0b10, cval, offset, depth - 1);
    else
        writeGridValue!blit(cval, offset, locRes);

    // SE
    cval = val - coeff[0] - coeff[1] + coeff[2];
    offset.x += locRes;
    if (!blitLowRes && depth && bt(coeffMarks[depth - 1], cidx + 0b11))
        writeToGrid!blit(coeffMarks, coeffs, cidx + 0b11, cval, offset, depth - 1);
    else
        writeGridValue!blit(cval, offset, locRes);
}

unittest
{
    auto wr = WaveletRaster(IRect(0, 0, 2, 2));
    FPoint[2] line = [FPoint(0, 0), FPoint(2, 2)];
    wr.insertEdge(line);
    wr.blit((y, x, xe, ub) {});
}
