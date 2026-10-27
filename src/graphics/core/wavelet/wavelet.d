module graphics.core.wavelet.wavelet;

import std.algorithm, std.array, std.bitmanip, std.conv, std.math, std.random,
    std.string, std.typecons, core.bitop;
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

        // Row-major 8-bit alpha scratchpad, handed to the blitter as an
        // A8 mask after `blit()` populates it.
        scratch.setConfig(Bitmap.Config.A8, clipRect.width, clipRect.height,
                          new ubyte[](clipRect.width * clipRect.height));

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
        _interimStack[] = Interim(0, 0, 0, 0);

        immutable center = FPoint(0.5 * _clipRect.width, 0.5 * _clipRect.height);
        auto cartesian = cartesianBezierWalker!(float, K)(curve, center);
        auto g0 = cartesian.pos;

        auto t0 = 0.0f;
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

            // A vertex sitting exactly on a grid intersection makes
            // cartesian() emit the crossing twice: same parameter, next
            // cell. Skip the empty slice rather than slicing to t1 <= t0.
            if (t1 > t0)
                updateNodes(curve, g0, t0, t1, nup);

            // shift grid position
            t0 = t1;
            g0 = g1;
        }

        // Finish off the remaining non-grid part
        if (t0 < 1.0f)
        {
            updateNodes(curve, g0, t0, 1.0f, _depth);
        }
    }

    private void updateNodes(size_t K)
        (in ref FPoint[K] curve, in ref IPoint pos, float t0, float t1, size_t depth)
    {
        auto cidx = posToLinQuad(pos);

        // 1. Slice and integrate ONLY at the leaf level (d = 0, scale = 1)
        FPoint[K] tmp = void;
        sliceBezier(curve, t0, t1, tmp);

        immutable float xo = pos.x;
        immutable float yo = pos.y;
        foreach (i; SIota!(0, K))
        {
            tmp[i].x -= xo;
            tmp[i].y -= yo;
        }

        Interim imp = calcInterim!K(1.0f, tmp);

        // 2. Propagate Interim up to `depth` levels
        for (size_t d = 0; d < depth; ++d)
        {
            immutable q = cast(Quad)(cidx % 4);
            cidx /= 4;

            if (!bts(_coeffMarks[d], cidx))
                _coeffs[d][cidx][] = 0.0f;

            addInterim(q, imp, _coeffs[d][cidx]);

            if (d + 1 < _depth)
            {
                addParentInterim(q, imp, _interimStack[d + 1]);
                if (d + 1 < depth)
                {
                    imp = _interimStack[d + 1];
                    _interimStack[d + 1] = Interim(0, 0, 0, 0);
                }
            }
        }
    }

    void insertEdge(size_t K)(ref FPoint[K] pts)
    {
        immutable off = fPoint(_clipRect.pos);
        foreach(i; SIota!(0, K))
            pts[i] -= off;
        clippedMonotonic!(float, K)(pts, FRect(0, 0, _clipRect.width, _clipRect.height), &insertSlice, &insertSlice);
    }

    /// Reconstruct the wavelet into the A8 scratch bitmap: pixel
    /// `(x, y)` in the clip lands in scratch row `y - clipRect.top`,
    /// column `x - clipRect.left`. Decouples the quadtree's Z-order
    /// traversal from the framebuffer's linear scanline layout: the
    /// traversal only touches one byte per pixel here, and the blitter
    /// consumes the scratch line by line.
    void blit()
    {
        if (_clipRect.empty)
            return;

        void blitRow(int y, int xstart, int xend, ubyte alpha)
        {
            // Traversal contract: y in [top, bottom), xstart/xend in
            // [left, right] (both ends inclusive).
            debug
            {
                assert(fitsIntoRange!("[)")(y, _clipRect.top, _clipRect.bottom));
                assert(fitsIntoRange!("[]")(xstart, _clipRect.left, _clipRect.right));
                assert(fitsIntoRange!("[]")(xend, _clipRect.left, _clipRect.right));
            }
            auto row = scratch.getRange!ubyte(xstart - _clipRect.left, xend - _clipRect.left,
                                             y - _clipRect.top);
            row[] = alpha;
        }

        // Can happen with only the root node on very small paths (1x1 pixels)
        if (_depth == 0)
            writeGridValue!blitRow(quantizeVal(_rootConst), _clipRect.pos, 1, 1);
        else
        {
            // Root square is 2^_depth; the grid is anchored at the clip
            // origin, so only east/south border contact is possible.
            auto sq = 1u << _depth;
            auto edge = Edge.inside;
            if (_clipRect.pos.x + sq > _clipRect.right)
                edge = cast(Edge)(edge | Edge.east);
            if (_clipRect.pos.y + sq > _clipRect.bottom)
                edge = cast(Edge)(edge | Edge.south);
            writeToGrid!blitRow(
                _coeffMarks[], _coeffs[], 0, _rootConst, _clipRect.pos, _depth - 1,
                edge, _clipRect);
        }
    }

    float _rootConst = 0.0f;
    uint _depth;
    IRect _clipRect;
    Bitmap scratch;

    enum MAX_DEPTH = 15; // limited by ushort for linearQuadtreeCoord
    Interim[MAX_DEPTH] _interimStack;
    Coeffs[][MAX_DEPTH] _coeffs;
    size_t*[MAX_DEPTH] _coeffMarks;
}

// Border contact of a node square: the grid is anchored at the clip
// origin, so only the east/south borders can ever be touched.
enum Edge : ubyte
{
    inside = 0,
    east   = 1 << 0,
    south  = 1 << 1
}

// Quantize a wavelet value to the 8-bit alpha the blit delegate expects.
// (Done per pixel that is actually written, so the DebugNoise random
// stream is only consumed for painted pixels.)
ubyte quantizeVal(float val)
{
    version(DebugNoise) {
        enum noise = 55;
        return clampTo!ubyte(abs(val * (255-noise)) + uniform(0, noise));
    } else {
        return clampTo!ubyte(abs(val * 255));
    }
}

void writeGridValue(alias blit)(ubyte ubval, IPoint off, uint w, uint h) {
  assert(w > 0);
  assert(h > 0);
  if (ubval == 0)
    return;

  auto left = off.x;
  auto right = off.x + w;
  foreach(y; off.y .. off.y + h) {
    blit(y, left, right, ubval);
  }
}

// Flat block write. Interior blocks are written at full size with no
// bounds arithmetic. Border blocks are culled when fully outside, then
// clamped: cull + edge flag together guarantee the width/height fall in
// [1, locRes], so a single subtract is exact at every level.
void writeBlock(alias blit)(float cval, IPoint off, uint locRes, Edge edge,
                           in IRect clip)
{
    if (edge == Edge.inside)
    {
        auto ubval = quantizeVal(cval);
        if (!ubval)
            return;
        writeGridValue!blit(ubval, off, locRes, locRes);
        return;
    }

    if (off.x >= clip.right || off.y >= clip.bottom)
        return;
    auto w = edge & Edge.east ? uint(clip.right) - off.x : locRes;
    auto h = edge & Edge.south ? uint(clip.bottom) - off.y : locRes;
    auto ubval = quantizeVal(cval);
    if (!ubval)
        return;
    writeGridValue!blit(ubval, off, w, h);
}

// Leaf level: the 2x2 pixel quad at `off`. Values come from the 2D Haar
// butterfly (8 float ops). Written as row-major runs, coalescing
// horizontal neighbours that quantize to the same alpha — the merge
// only reduces call count, never coverage.
void writeQuadDepth0(alias blit)(float val, in Coeffs coeff, IPoint off,
                                Edge edge, in IRect clip)
{
    uint w, h;
    if (edge == Edge.inside)
    {
        w = 2u;
        h = 2u;
    }
    else
    {
        // Fully outside: cull (no mark can be set on such a cell).
        if (off.x >= clip.right || off.y >= clip.bottom)
            return;
        // At this level the overhang is at most one pixel per axis and
        // the cull guarantees positivity, so the clamp is one subtract.
        w = edge & Edge.east ? uint(clip.right) - off.x : 2u;
        h = edge & Edge.south ? uint(clip.bottom) - off.y : 2u;
    }

    // A row of the quad: `a` at `off.x`, `b` at `off.x + 1` when
    // `w == 2`, coalesced into a single run when the quantized values
    // are equal.
    void row(float a, float b, int y)
    {
        auto qa = quantizeVal(a);
        if (w == 2)
        {
            auto qb = quantizeVal(b);
            if (qa == qb)
                writeGridValue!blit(qa, IPoint(off.x, y), 2, 1);
            else
            {
                writeGridValue!blit(qa, IPoint(off.x, y), 1, 1);
                writeGridValue!blit(qb, IPoint(off.x + 1, y), 1, 1);
            }
        }
        else
            writeGridValue!blit(qa, IPoint(off.x, y), 1, 1);
    }

    // 2D Haar butterfly
    auto s0 = val + coeff[1];
    auto s1 = val - coeff[1];
    auto d0 = coeff[0] + coeff[2];
    auto d1 = coeff[0] - coeff[2];

    row(s0 + d0, s0 - d0, off.y);
    if (h == 2)
        row(s1 + d1, s1 - d1, off.y + 1);
}

// Quadtree traversal. `edge` tracks which clip border the node square
// touches. NW never touches east/south, and an interior node has a fully
// interior subtree, so interior subtrees carry no bounds checks at all.
void writeToGrid(alias blit)
    (in size_t*[] coeffMarks, Coeffs[][] coeffs, uint cidx, float val,
     IPoint offset, uint depth, Edge edge, in IRect clip)
in
{
    assert(depth >= 0);
    assert(coeffMarks.length > depth);
    assert(coeffs.length > depth);
    assert(coeffs.length == coeffMarks.length);
    assert(!clip.empty);
    // grid is anchored at the clip origin
    assert(offset.x >= clip.left && offset.y >= clip.top);
}
body
{
    auto coeff = coeffs[depth][cidx];

    if (depth == 0)
    {
        writeQuadDepth0!blit(val, coeff, offset, edge, clip);
        return;
    }

    // 2D Haar butterfly: the four child values in 8 float ops
    auto s0 = val + coeff[1];
    auto s1 = val - coeff[1];
    auto d0 = coeff[0] + coeff[2];
    auto d1 = coeff[0] - coeff[2];

    uint locRes = 1U << depth;
    cidx *= 4; // linquad index for next level

    // All four child marks are contiguous in one word: cidx is quad-
    // aligned and 4 divides the word bit count.
    enum BITS_PER_WORD = 8 * size_t.sizeof;
    auto mask = cast(uint)((coeffMarks[depth - 1][cidx / BITS_PER_WORD]
                           >> (cidx % BITS_PER_WORD)) & 0b1111u);

    // Border contact of the children. The east edges of the NE/SE
    // children and the south edges of the SW/SE children coincide with
    // the parent's square, so those flags inherit exactly. The east
    // contact of NW/SW and the south contact of NW/NE depend on where
    // the border falls inside the parent square, so those are
    // re-checked only when the parent has the flag (border nodes are
    // the rare case; interior subtrees pay nothing).
    auto edgeE = cast(Edge)(edge & Edge.east);
    auto edgeS = cast(Edge)(edge & Edge.south);
    auto innerE = edgeE == Edge.east && offset.x + locRes > clip.right;
    auto innerS = edgeS == Edge.south && offset.y + locRes > clip.bottom;

    Edge edges(bool east, bool south)
    {
        Edge e = Edge.inside;
        if (east)
            e = cast(Edge)(e | Edge.east);
        if (south)
            e = cast(Edge)(e | Edge.south);
        return e;
    }

    // NW
    Edge edgeNW = edges(innerE, innerS);
    auto cval = s0 + d0;
    if (mask & 0b0001u)
        writeToGrid!blit(coeffMarks, coeffs, cidx, cval, offset, depth - 1,
                         edgeNW, clip);
    else
        writeBlock!blit(cval, offset, locRes, edgeNW, clip);

    // NE: east inherited exactly, south re-checked
    cval = s0 - d0;
    auto offNE = IPoint(offset.x + locRes, offset.y);
    auto edgeNE = edges(edgeE == Edge.east, innerS);
    if (mask & 0b0010u)
        writeToGrid!blit(coeffMarks, coeffs, cidx + 1, cval, offNE, depth - 1,
                         edgeNE, clip);
    else
        writeBlock!blit(cval, offNE, locRes, edgeNE, clip);

    // SW: east re-checked, south inherited exactly
    cval = s1 + d1;
    auto offSW = IPoint(offset.x, offset.y + locRes);
    auto edgeSW = edges(innerE, edgeS == Edge.south);
    if (mask & 0b0100u)
        writeToGrid!blit(coeffMarks, coeffs, cidx + 2, cval, offSW, depth - 1,
                         edgeSW, clip);
    else
        writeBlock!blit(cval, offSW, locRes, edgeSW, clip);

    // SE: both inherited exactly
    cval = s1 - d1;
    auto offSE = IPoint(offset.x + locRes, offset.y + locRes);
    if (mask & 0b1000u)
        writeToGrid!blit(coeffMarks, coeffs, cidx + 3, cval, offSE, depth - 1,
                         edge, clip);
    else
        writeBlock!blit(cval, offSE, locRes, edge, clip);
}

unittest
{
    auto wr = WaveletRaster(IRect(0, 0, 2, 2));
    FPoint[2] line = [FPoint(0, 0), FPoint(2, 2)];
    wr.insertEdge(line);
    wr.blit();
}
