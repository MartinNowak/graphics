module graphics.svg.filter;

import std.algorithm, std.ascii, std.conv, std.math, std.range, std.string;
import guip;
import graphics.core.pmcolor : PMColor;
import graphics.svg.parser : Document;

// SVG 1.1 §15: the filter model (a parsed <filter> plus its primitives) and
// the pixel operations over the working-image format. The renderer-side half
// - offscreen pass, region maths, per-primitive attribute resolution - lives
// in graphics.svg.render.
//
// Working images are premultiplied RGBA floats. The spec lets intermediates
// leave [0,1] (arithmetic k-terms, convolve's negative lobes), so the floats
// stay raw and clamping happens only when a result is encoded back to bytes
// (§15.2: nothing is clamped between primitives).

private bool ieq(string a, string b)
{
    if (a.length != b.length)
        return false;
    foreach (i, ch; a)
        if (std.ascii.toLower(ch) != std.ascii.toLower(b[i]))
            return false;
    return true;
}

// ---------------------------------------------------------------------------
// Transfer functions. gamut ships none, and SVG 1.1 §15.2 makes linearRGB
// the initial color-interpolation-filters value - the suite never overrides
// it, so the linear working space is baked into every reference PNG. Encode
// inverts decode at 8-bit granularity exactly, keeping the linearRGB detour
// byte-identical for pixels that pass through unchanged.
// ---------------------------------------------------------------------------

// Piecewise sRGB decode (IEC 61966-2-1; the table of SVG 1.1 F.2).
float[256] srgbDecodeLUT()
{
    float[256] t;
    foreach (i; 0 .. 256)
    {
        immutable c = i / 255.0f;
        t[i] = c <= 0.04045f ? c / 12.92f : pow((c + 0.055f) / 1.055f, 2.4f);
    }
    return t;
}

// The encode side of the same curve: linear float -> sRGB byte, clamped.
ubyte srgbEncode(float v)
{
    immutable c = clamp(v, 0.0f, 1.0f);
    immutable s = c <= 0.0031308f ? 12.92f * c : 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
    return cast(ubyte)(s * 255.0f + 0.5f);
}

unittest
{
    // Byte-exact round-trip: the property that makes a linearRGB detour
    // invisible for unchanged pixels.
    immutable lut = srgbDecodeLUT();
    foreach (i; 0 .. 256)
        assert(srgbEncode(lut[i]) == i, to!string(i));
}

// ---------------------------------------------------------------------------
// Working image.
// ---------------------------------------------------------------------------

/// Device-space box, half-open like the raster it clips.
struct IBox4
{
    int x0, y0, x1, y1;
    bool empty() const { return x0 >= x1 || y0 >= y1; }
}

IBox4 intersect(in IBox4 a, in IBox4 b)
{
    return IBox4(max(a.x0, b.x0), max(a.y0, b.y0), min(a.x1, b.x1), min(a.y1, b.y1));
}

/// objectBoundingBox <length>: a plain number is a fraction of the box,
/// a percentage maps one-to-one ("120%" -> 1.2). False on garbage - the
/// caller substitutes the attribute default.
bool bbFraction(string v, out float r)
{
    v = strip(v);
    if (v.empty)
        return false;
    immutable pct = v[$ - 1] == '%';
    try
        r = to!float(pct ? v[0 .. $ - 1] : v) / (pct ? 100.0f : 1.0f);
    catch (ConvException)
        return false;
    return true;
}

/// One filter working image: premultiplied RGBA floats, row-major.
struct Raster
{
    int w, h;
    float[] px; // 4 per pixel

    this(int w, int h)
    {
        this.w = w;
        this.h = h;
        px.length = w * h * 4;
        px[] = 0.0f; // transparent black, per §15.3's buffer init
        // (.length= alone can hand back recycled GC memory uncleaned)
    }

    Raster dup() const
    {
        auto r = Raster(w, h);
        r.px[] = px[];
        return r;
    }

    /// Zero everything outside the box: the filter effects region bounds
    /// every intermediate (§15.5: offscreens are "the intersection ...
    /// with the filter region").
    void clipTo(in IBox4 b)
    {
        foreach (y; 0 .. h)
            foreach (x; 0 .. w)
                if (x < b.x0 || x >= b.x1 || y < b.y0 || y >= b.y1)
                {
                    immutable i = (cast(size_t) y * w + x) * 4;
                    px[i .. i + 4] = 0.0f;
                }
    }

    /// The painted-coverage box in raster coordinates - the
    /// objectBoundingBox units basis. False when nothing was painted: a
    /// degenerate bbox makes every objectBoundingBox computation meaningless.
    bool coverageBox(out IBox4 b) const
    {
        b = IBox4(w, h, 0, 0);
        foreach (y; 0 .. h)
            foreach (x; 0 .. w)
                if (px[(cast(size_t) y * w + x) * 4 + 3] > 0.0f)
                {
                    if (x < b.x0) b.x0 = x;
                    if (x + 1 > b.x1) b.x1 = x + 1;
                    if (y < b.y0) b.y0 = y;
                    if (y + 1 > b.y1) b.y1 = y + 1;
                }
        return b.x0 < b.x1;
    }
}

unittest
{
    auto r = Raster(4, 3);
    r.px[(cast(size_t) 1 * 4 + 2) * 4 + 3] = 1.0f; // one pixel at (2,1)
    IBox4 b;
    assert(r.coverageBox(b));
    assert(b == IBox4(2, 1, 3, 2), to!string([b.x0, b.y0, b.x1, b.y1]));
    r.px[] = 0.0f;
    assert(!r.coverageBox(b));

    r = Raster(2, 2);
    r.px[] = 1.0f;
    r.clipTo(IBox4(1, 0, 2, 2));
    assert(r.px[0 .. 4] == [0.0f, 0.0f, 0.0f, 0.0f]);
    assert(r.px[4 .. 8] == [1.0f, 1.0f, 1.0f, 1.0f]);
}

// The guip buffer already holds premultiplied bytes (the engine's own
// convention - the sprite blit wanting straight ARGB is exactly why
// maskedPaint blends by hand), so these conversions never call gamut's
// premultiply()/unpremultiply(): that would premultiply a second time.
// Both conversions pass through the unpremultiplied domain, which is also
// where the transfer curve applies - alpha is linear by definition and gets
// none.

/// The un-premultiplied byte of channel c. Recovering the *byte* (not just
/// any ratio) is what makes rasterFrom/bitmapFrom round-trip exactly.
private ubyte straightByte(in PMColor p, int c)
{
    if (p.a == 0)
        return 0;
    immutable v = c == 0 ? p.r : c == 1 ? p.g : p.b;
    return cast(ubyte) min((cast(int) v * 255 + p.a / 2) / p.a, 255);
}

/// Bitmap bytes -> working floats, in the filter's working space.
Raster rasterFrom(in Bitmap src, bool linearRGB)
{
    auto r = Raster(cast(int) src.width, cast(int) src.height);
    immutable lut = srgbDecodeLUT();
    foreach (y; 0 .. r.h)
    {
        auto row = src.getLine!PMColor(y);
        foreach (x, p; row)
        {
            immutable i = (cast(size_t) y * r.w + x) * 4;
            r.px[i + 3] = p.a / 255.0f;
            if (p.a == 0)
                continue; // transparent black: the PM channels are 0 already
            foreach (c; 0 .. 3)
            {
                immutable sb = straightByte(p, c);
                // straight byte -> working space, then back to premultiplied:
                // the working-image invariant every §15.4 formula relies on.
                r.px[i + c] = r.px[i + 3] * (linearRGB ? lut[sb] : sb / 255.0f);
            }
        }
    }
    return r;
}

/// Working floats -> bitmap bytes: clamp to [0,1], un-premultiply into the
/// straight domain, encode the curve, then hand the straight color to the
/// engine's own PMColor constructor to re-premultiply.
Bitmap bitmapFrom(in Raster r, bool linearRGB)
{
    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, to!uint(r.w), to!uint(r.h));
    bmp.eraseColor(Color(0));
    foreach (y; 0 .. r.h)
    {
        auto row = bmp.getLine!PMColor(y);
        foreach (x, ref p; row)
        {
            immutable i = (cast(size_t) y * r.w + x) * 4;
            immutable a = clamp(r.px[i + 3], 0.0f, 1.0f);
            Color c;
            c.a = cast(ubyte)(a * 255.0f + 0.5f);
            if (c.a)
                foreach (ch; 0 .. 3)
                {
                    immutable straight = clamp(r.px[i + ch] / a, 0.0f, 1.0f);
                    immutable v = linearRGB ? srgbEncode(straight)
                                            : cast(ubyte)(straight * 255.0f + 0.5f);
                    if (ch == 0) c.r = v;
                    else if (ch == 1) c.g = v;
                    else c.b = v;
                }
            p = PMColor(c);
        }
    }
    return bmp;
}

unittest
{
    // rasterFrom/bitmapFrom round-trip must be byte-identical for engine
    // pixels: unpremultiply and re-premultiply use the same byte domain the
    // engine's own premultiplied buffer lives in.
    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, 2, 1);
    auto row = bmp.getLine!PMColor(0);
    row[0] = PMColor(Color(0xC0_80_40_64)); // straight purple, PM-rebuilt by the engine
    row[1] = PMColor(Color(0));
    foreach (linear; [false, true])
    {
        auto back = bitmapFrom(rasterFrom(bmp, linear), linear);
        assert(back.getLine!PMColor(0)[] == bmp.getLine!PMColor(0)[],
            to!string(linear));
    }
}

// ---------------------------------------------------------------------------
// Primitive operations, batched over the premultiplied float slices.
// ---------------------------------------------------------------------------

/// Porter-Duff "over": exactly how feMerge composites its nodes (§15.3).
void mergeOver(ref Raster dst, in Raster src)
{
    foreach (i; 0 .. cast(int) (dst.px.length / 4))
    {
        immutable p = cast(size_t) i * 4;
        immutable sa = src.px[p + 3];
        if (sa <= 0.0f)
            continue;
        if (sa >= 1.0f)
        {
            dst.px[p .. p + 4] = src.px[p .. p + 4];
            continue;
        }
        immutable ia = 1.0f - sa;
        foreach (c; 0 .. 4)
            dst.px[p + c] = src.px[p + c] + dst.px[p + c] * ia;
    }
}

unittest
{
    auto a = Raster(1, 1), b = Raster(1, 1);
    a.px[] = [1.0f, 0.0f, 0.0f, 0.5f]; // red PM, half cover
    b.px[] = [0.0f, 0.0f, 1.0f, 0.5f];
    mergeOver(a, b);
    // blue over red: b adds, red keeps (1-0.5)
    assert(a.px[] == [0.5f, 0.0f, 1.0f, 0.75f], to!string(a.px[]));
}

/// feOffset: shift the whole image by device-pixel amounts.
void offsetShift(ref Raster dst, in Raster src, int dx, int dy)
{
    dst = Raster(src.w, src.h);
    foreach (y; 0 .. src.h)
    {
        immutable ty = y + dy;
        if (ty < 0 || ty >= src.h)
            continue;
        foreach (x; 0 .. src.w)
        {
            immutable tx = x + dx;
            if (tx < 0 || tx >= src.w)
                continue;
            immutable s = (cast(size_t) y * src.w + x) * 4;
            immutable d = (cast(size_t) ty * src.w + tx) * 4;
            dst.px[d .. d + 4] = src.px[s .. s + 4];
        }
    }
}

unittest
{
    auto s = Raster(2, 1);
    s.px[0 .. 4] = [1.0f, 0.0f, 0.0f, 1.0f];
    Raster d;
    offsetShift(d, s, 1, 0);
    assert(d.px[0 .. 4] == [0.0f, 0.0f, 0.0f, 0.0f], to!string(d.px[]));
    assert(d.px[4 .. 8] == [1.0f, 0.0f, 0.0f, 1.0f], to!string(d.px[]));
}

/// feFlood: paint [x0,x1)×[y0,y1) with one flat color, given premultiplied
/// and already converted into the filter's working space.
void flood(ref Raster dst, in IBox4 box, in float[4] colorPM)
{
    foreach (y; max(0, box.y0) .. min(dst.h, box.y1))
        foreach (x; max(0, box.x0) .. min(dst.w, box.x1))
        {
            immutable d = (cast(size_t) y * dst.w + x) * 4;
            dst.px[d .. d + 4] = colorPM;
        }
}

enum CompOp { over, inOp, outOp, atop, xorOp, arithmetic }

/// feComposite, §15.6.23's operator table evaluated on premultiplied
/// inputs; the arithmetic k-terms write raw (possibly out-of-[0,1]) floats.
void composite(ref Raster dst, in Raster a, in Raster b, CompOp op, in float[4] k)
{
    foreach (i; 0 .. cast(int) (dst.px.length / 4))
    {
        immutable p = cast(size_t) i * 4;
        if (op != CompOp.arithmetic)
        {
            immutable sa = a.px[p + 3], da = b.px[p + 3];
            float ma, mb; // channel multipliers for a (source) and b (dest)
            final switch (op)
            {
            case CompOp.over:    ma = 1.0f;      mb = 1.0f - sa; break;
            case CompOp.inOp:    ma = da;        mb = 0.0f;      break;
            case CompOp.outOp:   ma = 1.0f - da; mb = 0.0f;      break;
            case CompOp.atop:    ma = da;        mb = 1.0f - sa; break;
            case CompOp.xorOp:   ma = 1.0f - da; mb = 1.0f - sa; break;
            case CompOp.arithmetic: assert(false, "handled above");
            }
            foreach (c; 0 .. 4)
                dst.px[p + c] = a.px[p + c] * ma + b.px[p + c] * mb;
        }
        else
            // co = k1·cs·cd + k2·cs + k3·cd + k4, per channel (alpha included)
            foreach (c; 0 .. 4)
                dst.px[p + c] = k[0] * a.px[p + c] * b.px[p + c]
                              + k[1] * a.px[p + c] + k[2] * b.px[p + c] + k[3];
    }
}

unittest
{
    // Two half-coverage sources that never overlap.
    auto a = Raster(2, 1), b = Raster(2, 1), d = Raster(2, 1);
    a.px[0 .. 4] = [1.0f, 0.0f, 0.0f, 0.5f];
    b.px[4 .. 8] = [0.0f, 0.0f, 1.0f, 0.5f];

    composite(d, a, b, CompOp.over, [0.0f, 0.0f, 0.0f, 0.0f]);
    assert(d.px[0 .. 4] == [1.0f, 0.0f, 0.0f, 0.5f]);
    assert(d.px[4 .. 8] == [0.0f, 0.0f, 1.0f, 0.5f], to!string(d.px[4 .. 8]));

    d = Raster(2, 1);
    composite(d, a, b, CompOp.inOp, [0.0f, 0.0f, 0.0f, 0.0f]); // a IN b: empty
    bool touched = false;
    foreach (v; d.px)
        touched |= v != 0.0f;
    assert(!touched);

    d = Raster(2, 1);
    composite(d, a, a, CompOp.atop, [0.0f, 0.0f, 0.0f, 0.0f]); // atop itself
    assert(d.px[0 .. 4] == [1.0f, 0.0f, 0.0f, 0.5f]);

    // k2=2 doubling: out-of-range output is legal mid-chain.
    d = Raster(2, 1);
    composite(d, a, b, CompOp.arithmetic, [0.0f, 2.0f, 0.0f, 0.0f]);
    assert(d.px[0] == 2.0f && d.px[3] == 1.0f);
}

enum BlendMode { normal, multiply, screen, darken, lighten }

/// feBlend, §15.4/§15.6.1: source-over compositing where the blend term
/// runs on the unpremultiplied channels. multiply/screen reduce to
/// PM-channel arithmetic (homogeneity: B·αs·αd == the PM product form);
/// darken/lighten compare straight values but still yield a PM term.
void blend(ref Raster dst, in Raster above, in Raster below, BlendMode m)
{
    foreach (i; 0 .. cast(int) (dst.px.length / 4))
    {
        immutable p = cast(size_t) i * 4;
        immutable aa = above.px[p + 3], ab = below.px[p + 3];
        dst.px[p + 3] = aa + ab - aa * ab;
        foreach (c; 0 .. 3)
        {
            immutable A = above.px[p + c], B = below.px[p + c];
            float bt; // the blend term, already premultiplied
            final switch (m)
            {
            case BlendMode.normal:
                bt = ab * A; // then the line below collapses to source-over
                break;
            case BlendMode.multiply:
                bt = A * B;
                break;
            case BlendMode.screen:
                // B(cb,cs) = cs + cb - cs*cb; straight values ride the
                // premultiplied ones, so cs picks up `ab`, cb picks up `aa`.
                bt = ab * A + aa * B - A * B;
                break;
            case BlendMode.darken:
            case BlendMode.lighten:
                // The straight comparison needs both alphas up; a fully
                // transparent image contributes no blend term either way.
                bt = aa > 0.0f && ab > 0.0f
                   ? (m == BlendMode.darken ? min(A / aa, B / ab) : max(A / aa, B / ab)) * aa * ab
                   : 0.0f;
                break;
            }
            dst.px[p + c] = A * (1.0f - ab) + B * (1.0f - aa) + bt;
        }
    }
}

unittest
{
    // Opaque blue below, half-cover red above - premultiplied, so the
    // red's straight 1.0 rides on alpha 0.5 as PM 0.5.
    auto above = Raster(1, 1), below = Raster(1, 1), d = Raster(1, 1);
    above.px[] = [0.5f, 0.0f, 0.0f, 0.5f];
    below.px[] = [0.0f, 0.0f, 1.0f, 1.0f];

    blend(d, above, below, BlendMode.normal);
    // plain source-over: the blue keeps only the uncovered half (1·(1-0.5)),
    // the red contributes its PM 0.5.
    assert(d.px[] == [0.5f, 0.0f, 0.5f, 1.0f], to!string(d.px[]));

    blend(d, above, below, BlendMode.multiply);
    // multiply: the red straightens to 1.0 but its blend term against the
    // blue's zero red is zero; the blue still gets composited over, losing
    // half its coverage to the red: PM blue lands at 0.5.
    assert(d.px[0] == 0.0f && d.px[2] == 0.5f, to!string(d.px[]));

    blend(d, above, below, BlendMode.lighten);
    assert(d.px[0] == 0.5f, to!string(d.px[])); // lighten keeps the red

    // Half-alpha green below, half-alpha blue above - the classic
    // flood+blend case: the PM blend term must carry the other
    // image's alpha (spec: alpha-above x alpha-below x B(straight)).
    above.px[] = [0.0f, 0.0f, 0.5f, 0.5f];
    below.px[] = [0.0f, 0.5f, 0.0f, 0.5f];

    blend(d, above, below, BlendMode.normal);
    // Source-over exactly: PM green = 0.5*(1-0.5), PM blue = 0.5 + 0.
    assert(d.px[] == [0.0f, 0.25f, 0.5f, 0.75f], to!string(d.px[]));

    blend(d, above, below, BlendMode.multiply);
    // Multiply of orthogonal colours zeroes the blend term; the
    // compositing terms survive: green 0.5*(1-0.5), blue 0.5*(1-0.5).
    assert(d.px[] == [0.0f, 0.25f, 0.25f, 0.75f], to!string(d.px[]));

    blend(d, above, below, BlendMode.screen);
    // Screen: PM term = 0.5*0 + 0.5*0.5 - 0 = 0.25 per lit channel;
    // green: 0 + 0.25 + 0.25, blue: 0.25 + 0 + 0.25.
    assert(d.px[] == [0.0f, 0.5f, 0.5f, 0.75f], to!string(d.px[]));
}

/// feColorMatrix §15.6.4/15.6.5: build the row-major 5x4 matrix named by
/// `type` from its `values` shortcut. Unknown types, short value lists and
/// non-matrix types with values present behave as the identity.
float[20] cmMatrix(in string type, const float[] v)
{
    float[20] m = 0.0f;
    m[0] = m[6] = m[12] = m[18] = 1.0f; // identity; the alpha row stays
    switch (type)
    {
    case "saturate":
    {
        immutable s = v.length ? v[0] : 1.0f;
        m[0 .. 3] = [0.213f + 0.787f * s, 0.715f - 0.715f * s, 0.072f - 0.072f * s];
        m[5 .. 8] = [0.213f - 0.213f * s, 0.715f + 0.285f * s, 0.072f - 0.072f * s];
        m[10 .. 13] = [0.213f - 0.213f * s, 0.715f - 0.715f * s, 0.072f + 0.928f * s];
        break;
    }

    case "hueRotate":
    {
        immutable deg = v.length ? v[0] : 0.0f;
        immutable c = cos(deg * PI / 180.0f), s = sin(deg * PI / 180.0f);
        m[0 .. 3] = [0.213f + 0.787f * c - 0.213f * s, 0.715f - 0.715f * c - 0.715f * s,
                     0.072f - 0.072f * c + 0.928f * s];
        m[5 .. 8] = [0.213f - 0.213f * c + 0.143f * s, 0.715f + 0.285f * c + 0.140f * s,
                     0.072f - 0.072f * c - 0.283f * s];
        m[10 .. 13] = [0.213f - 0.213f * c - 0.787f * s, 0.715f - 0.715f * c + 0.715f * s,
                       0.072f + 0.928f * c + 0.072f * s];
        break;
    }

    case "luminanceToAlpha":
        m[] = 0.0f;
        m[15 .. 18] = [0.2125f, 0.7154f, 0.0721f];
        break;

    default: // matrix
        if (v.length == 20)
            m[] = v[0 .. 20];
        break;
    }
    return m;
}

/// The matrix runs on straight (non-premultiplied) channels, [R G B A 1]
/// per §15.6.4; only the resulting alpha is clamped, colours stay raw.
void colorMatrix(ref Raster dst, in Raster src, in float[20] m)
{
    dst = Raster(src.w, src.h);
    foreach (i; 0 .. cast(int) (src.px.length / 4))
    {
        immutable p = cast(size_t) i * 4;
        immutable a = src.px[p + 3];
        float[4] s;
        foreach (c; 0 .. 3)
            s[c] = a > 0.0f ? src.px[p + c] / a : 0.0f;
        s[3] = a;
        immutable na = clamp(m[15] * s[0] + m[16] * s[1] + m[17] * s[2]
            + m[18] * s[3] + m[19], 0.0f, 1.0f);
        foreach (c; 0 .. 3)
            dst.px[p + c] = na > 0.0f
                ? (m[c * 5] * s[0] + m[c * 5 + 1] * s[1] + m[c * 5 + 2] * s[2]
                   + m[c * 5 + 3] * s[3] + m[c * 5 + 4]) * na
                : 0.0f;
        dst.px[p + 3] = na;
    }
}

unittest
{
    auto src = Raster(1, 1);
    Raster d;

    // saturate 0 flattens red onto the spec's 0.213 luminance row.
    src.px[] = [1.0f, 0.0f, 0.0f, 1.0f];
    colorMatrix(d, src, cmMatrix("saturate", [0.0f]));
    assert(isClose(d.px[0], 0.213f, 1e-4f) && d.px[1] == d.px[0] && d.px[2] == d.px[0]
        && d.px[3] == 1.0f, to!string(d.px[]));

    // hueRotate 180: the spec matrix puts red at (-0.574, 0.426, 0.426)
    // - raw floats, negative lobes untouched until encoding.
    colorMatrix(d, src, cmMatrix("hueRotate", [180.0f]));
    assert(isClose(d.px[0], -0.574f, 1e-3f) && isClose(d.px[1], 0.426f, 1e-3f)
        && isClose(d.px[2], 0.426f, 1e-3f), to!string(d.px[]));

    // luminanceToAlpha empties the colours and moves luminance to A.
    colorMatrix(d, src, cmMatrix("luminanceToAlpha", null));
    assert(d.px[0] == 0.0f && d.px[1] == 0.0f && d.px[2] == 0.0f
        && isClose(d.px[3], 0.2125f, 1e-4f), to!string(d.px[]));

    // Half-alpha straight red through an invert-and-offset matrix: the
    // straightening must round-trip, so cyan lands at PM 0.5, not 0.25.
    src.px[] = [0.5f, 0.0f, 0.0f, 0.5f];
    colorMatrix(d, src, cmMatrix("matrix",
        [-1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, -1.0f, 0.0f, 0.0f, 1.0f,
         0.0f, 0.0f, -1.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f]));
    assert(d.px[] == [0.0f, 0.5f, 0.5f, 0.5f], to!string(d.px[]));
}

/// feComponentTransfer §15.11: a channel transfer function. Absent or
/// empty feFunc elements stay identity.
struct TransferFunc
{
    enum Kind { identity, table, linear, gamma, discrete }
    Kind kind = Kind.identity;
    float[] table; // tableValues: n+1 values (table) or n steps (discrete)
    float slope = 1.0f, intercept = 0.0f;
    float amplitude = 1.0f, exponent = 1.0f, offset = 0.0f;

    float op(float c) const
    {
        switch (kind)
        {
        case Kind.linear:
            return slope * c + intercept;

        case Kind.gamma:
            return amplitude * pow(max(c, 0.0f), exponent) + offset;

        case Kind.table:
            if (table.length < 2)
                return c; // an empty list is identity
            {
                immutable cl = clamp(c, 0.0f, 1.0f), nf = cast(float) (table.length - 1);
                if (cl >= 1.0f)
                    return table[$ - 1];
                immutable k = min(cast(int) (cl * nf), cast(int) table.length - 2);
                immutable kf = cast(float) k;
                return table[k] + (cl - kf / nf) * nf * (table[k + 1] - table[k]);
            }

        case Kind.discrete:
            if (table.empty)
                return c;
            {
                immutable cl = clamp(c, 0.0f, 1.0f), nf = cast(float) table.length;
                if (cl >= 1.0f)
                    return table[$ - 1];
                return table[min(cast(int) (cl * nf), cast(int) table.length - 1)];
            }

        default: // identity
            return c;
        }
    }
}

/// The functions run on straight channels; feFuncA acts on alpha, and
/// only that result is clamped before the re-premultiply.
void componentTransfer(ref Raster dst, in Raster src, const TransferFunc[4] fn)
{
    dst = Raster(src.w, src.h);
    foreach (i; 0 .. cast(int) (src.px.length / 4))
    {
        immutable p = cast(size_t) i * 4;
        immutable a = src.px[p + 3];
        float[4] s;
        foreach (c; 0 .. 3)
            s[c] = a > 0.0f ? src.px[p + c] / a : 0.0f;
        s[3] = a;
        immutable na = clamp(fn[3].op(s[3]), 0.0f, 1.0f);
        foreach (c; 0 .. 3)
            dst.px[p + c] = na > 0.0f ? fn[c].op(s[c]) * na : 0.0f;
        dst.px[p + 3] = na;
    }
}

unittest
{
    auto src = Raster(1, 1);
    Raster d;
    src.px[] = [0.5f, 0.25f, 0.0f, 0.5f]; // straight (1, 0.5, 0) at A 0.5

    // table "0 0 1 1" at C=1: n=3, k=2 segment endpoint -> 1.
    TransferFunc[4] fn;
    fn[0].kind = TransferFunc.Kind.table;
    fn[0].table = [0.0f, 0.0f, 1.0f, 1.0f];
    componentTransfer(d, src, fn);
    assert(isClose(d.px[0], 1.0f * 0.5f, 1e-5f), to!string(d.px[])); // straight 1
    assert(isClose(d.px[1], 0.5f * 0.5f, 1e-5f) && isClose(d.px[3], 0.5f, 1e-5f));

    // discrete "0 0.5 1": straight green C=0.5 lands on the middle step,
    // straight red C=1 on the last one.
    fn[0].kind = TransferFunc.Kind.discrete;
    fn[1].kind = TransferFunc.Kind.discrete;
    fn[0].table = [0.0f, 0.5f, 1.0f];
    fn[1].table = fn[0].table;
    componentTransfer(d, src, fn);
    assert(isClose(d.px[0], 1.0f * 0.5f, 1e-5f) && isClose(d.px[1], 0.5f * 0.5f, 1e-5f),
        to!string(d.px[]));

    // gamma squares: straight 1 -> 1; linear halves red with intercept.
    fn[0].kind = TransferFunc.Kind.gamma;
    fn[0].exponent = 2.0f;
    componentTransfer(d, src, fn);
    assert(isClose(d.px[0], 0.5f, 1e-5f));
    fn[0].kind = TransferFunc.Kind.linear;
    fn[0].slope = 0.5f;
    componentTransfer(d, src, fn);
    assert(isClose(d.px[0], 0.5f * 0.5f, 1e-5f));

    // feFuncA maps A through the function too, and the colours follow
    // the re-premultiply.
    fn[] = TransferFunc.init;
    fn[3].kind = TransferFunc.Kind.linear;
    fn[3].slope = 0.5f;
    componentTransfer(d, src, fn);
    assert(isClose(d.px[3], 0.25f, 1e-5f) && isClose(d.px[0], 0.25f, 1e-5f),
        to!string(d.px[]));
}

/// feConvolveMatrix §15.13: convolution runs on premultiplied working
/// values; the kernel is applied rotated 180° (coefficient for source
/// offset (J-targetX, I-targetY) is k[orderY-I-1][orderX-J-1], per the
/// spec formula). Bias enters alpha raw and colours at bias·ALPHA_X,Y;
/// preserveAlpha unpremultiplies the colours, runs the kernel on those,
/// and re-premultiplies against the untouched source alpha.
enum ConvEdge { duplicate, wrap, none }

void convolve(ref Raster dst, in Raster src, in float[] k, int ox, int oy,
    int tx, int ty, float divisor, float bias, ConvEdge edge, bool preserveAlpha)
{
    dst = Raster(src.w, src.h);

    float samp(in Raster r, int sx, int sy, int c)
    {
        switch (edge)
        {
        case ConvEdge.duplicate:
            return r.px[(min(max(sy, 0), r.h - 1) * r.w + min(max(sx, 0), r.w - 1)) * 4 + c];
        case ConvEdge.wrap:
            {
                immutable wx = ((sx % r.w) + r.w) % r.w, wy = ((sy % r.h) + r.h) % r.h;
                return r.px[(wy * r.w + wx) * 4 + c];
            }
        default: // none: zero (including alpha) outside
            return sx >= 0 && sx < r.w && sy >= 0 && sy < r.h ? r.px[(sy * r.w + sx) * 4 + c] : 0.0f;
        }
    }

    // straight form of one colour sample (alpha of that sample itself).
    float sampS(int sx, int sy, int c)
    {
        immutable a = samp(src, sx, sy, 3);
        return a > 0.0f ? samp(src, sx, sy, c) / a : 0.0f;
    }

    foreach (y; 0 .. src.h)
        foreach (x; 0 .. src.w)
        {
            immutable p = cast(size_t) (y * src.w + x) * 4;
            float[4] acc = 0.0f;
            foreach (I; 0 .. oy)
                foreach (J; 0 .. ox)
                {
                    immutable coef = k[(oy - 1 - I) * ox + (ox - 1 - J)];
                    immutable sx = x - tx + J, sy = y - ty + I;
                    if (preserveAlpha)
                        foreach (c; 0 .. 3)
                            acc[c] += sampS(sx, sy, c) * coef;
                    else
                        foreach (c, ref ac; acc)
                            ac += samp(src, sx, sy, cast(int) c) * coef;
                }

            if (preserveAlpha)
            {
                dst.px[p + 3] = src.px[p + 3]; // ALPHA_X,Y = SOURCE_X,Y
                foreach (c; 0 .. 3)
                    dst.px[p + c] = (acc[c] / divisor + bias * dst.px[p + 3]) * dst.px[p + 3];
            }
            else
            {
                dst.px[p + 3] = acc[3] / divisor + bias;
                foreach (c; 0 .. 3)
                    dst.px[p + c] = acc[c] / divisor + bias * dst.px[p + 3];
            }
        }
}

unittest
{
    // The spec's identity kernel: rotated 180° it is its own inverse.
    auto src = Raster(2, 1);
    Raster d;
    src.px[] = [1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f];
    convolve(d, src, [0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f],
        3, 3, 1, 1, 1.0f, 0.0f, ConvEdge.none, false);
    assert(d.px[] == src.px[], to!string(d.px[]));

    // order="1 2" with an asymmetric kernel pins the 180° rotation:
    // targetY = floor(2/2) = 1, so k[1] multiplies the row above the
    // target and k[0] the target's own row - red above blue at y=0 is
    // the k[0] tap alone, and 2*red + blue at y=1.
    src = Raster(1, 2);
    src.px[] = [1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f]; // red above blue
    convolve(d, src, [1.0f, 2.0f], 1, 2, 0, 1, 3.0f, 0.0f, ConvEdge.none, false);
    assert(isClose(d.px[0], 1.0f / 3, 1e-5f) && d.px[1] == 0.0f
        && isClose(d.px[3], 1.0f / 3, 1e-5f), to!string(d.px[0 .. 4]));
    assert(isClose(d.px[4], 2.0f / 3, 1e-5f) && isClose(d.px[6], 1.0f / 3, 1e-5f)
        && isClose(d.px[7], 1.0f, 1e-5f), to!string(d.px[4 .. 8]));

    // Edge modes on a single red pixel with a 1/9 box kernel: "none"
    // keeps just the centre tap; duplicate (and wrap, on a 1x1) fill it.
    src = Raster(1, 1);
    src.px[] = [1.0f, 0.0f, 0.0f, 1.0f];
    auto box = repeat(1.0f, 9).array;
    convolve(d, src, box, 3, 3, 1, 1, 9.0f, 0.0f, ConvEdge.none, false);
    assert(isClose(d.px[0], 1.0f / 9, 1e-5f) && isClose(d.px[3], 1.0f / 9, 1e-5f));
    convolve(d, src, box, 3, 3, 1, 1, 9.0f, 0.0f, ConvEdge.duplicate, false);
    assert(d.px[] == [1.0f, 0.0f, 0.0f, 1.0f], to!string(d.px[]));

    // preserveAlpha keeps alpha and runs the kernel on straight colours;
    // the raw form convolves alpha too and lets bias ride the result.
    src.px[] = [0.5f, 0.0f, 0.0f, 0.5f]; // half-alpha straight red
    convolve(d, src, [0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f],
        3, 3, 1, 1, 1.0f, 0.0f, ConvEdge.none, true);
    assert(d.px[] == [0.5f, 0.0f, 0.0f, 0.5f], to!string(d.px[]));
    convolve(d, src, [0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f],
        3, 3, 1, 1, 1.0f, 0.5f, ConvEdge.none, false);
    // alpha: 0.5 + 0.5 = 1; PM red: 0.5 + 0.5*1; and bias lands on
    // every component, so the black channels lift to 0.5 - the
    // "0.5 gray is the zero response" trick §15.13 spells out.
    assert(d.px[] == [1.0f, 0.5f, 0.5f, 1.0f], to!string(d.px[]));
}

/// feGaussianBlur, §15.16.1: for s >= 2 three box blurs stand in for the
/// Gaussian - d = floor(s·3·sqrt(2π)/4 + 0.5); odd d takes three boxes of
/// size d centred on the output pixel, even d two boxes of size d half a
/// pixel apart plus one box of size d+1. Below 2 the exact separable
/// Gaussian kernel (truncated at 3σ) convolves instead. Zero padding: the
/// offscreen outside the raster is transparent black (§15.3).
void gaussianBlur(ref Raster dst, in Raster src, float sx, float sy)
{
    dst = src.dup();
    if (sx > 0.0f)
        blurAxis(dst, true, sx);
    if (sy > 0.0f)
        blurAxis(dst, false, sy);
}

private void blurAxis(ref Raster r, bool axisX, float s)
{
    // A stage is a uniform box (weights empty) or one weighted pass.
    struct Stage { int width, left; float[] weights; }
    Stage[] stages;
    if (s < 2.0f)
    {
        immutable rad = cast(int) ceil(3.0f * s);
        Stage st;
        st.width = 2 * rad + 1;
        st.left = -rad;
        st.weights.length = st.width;
        float sum = 0.0f;
        foreach (off; 0 .. st.width)
        {
            immutable float kf = cast(float)(off - rad);
            immutable e = exp(-kf * kf / (2.0f * s * s));
            st.weights[off] = e;
            sum += e;
        }
        foreach (ref w; st.weights)
            w /= sum;
        stages = [st];
    }
    else
    {
        immutable d = cast(int) floor(s * 3.0f * sqrt(2.0f * PI) / 4.0f + 0.5f);
        if (d % 2)
            stages = [Stage(d, -(d - 1) / 2, null), Stage(d, -(d - 1) / 2, null),
                      Stage(d, -(d - 1) / 2, null)];
        else
            stages = [Stage(d, -d / 2, null), Stage(d, -d / 2 + 1, null),
                      Stage(d + 1, -d / 2, null)];
    }

    immutable n = axisX ? r.w : r.h; // the axis run
    immutable m = axisX ? r.h : r.w; // the lines perpendicular to it
    float[] tmp;
    tmp.length = cast(size_t) r.w * r.h * 4;

    foreach (st; stages)
    {
        immutable uniform = st.weights.empty;
        foreach (line; 0 .. m)
            foreach (i; 0 .. n)
            {
                float[4] acc = [0.0f, 0.0f, 0.0f, 0.0f];
                foreach (off; 0 .. st.width)
                {
                    immutable j = i + st.left + off;
                    if (j < 0 || j >= n)
                        continue; // zero padding
                    immutable px = axisX ? j : line, py = axisX ? line : j;
                    immutable p = (cast(size_t) py * r.w + px) * 4;
                    immutable wgt = uniform ? 1.0f / st.width : st.weights[off];
                    foreach (c; 0 .. 4)
                        acc[c] += r.px[p + c] * wgt;
                }
                immutable qx = axisX ? i : line, qy = axisX ? line : i;
                immutable q = (cast(size_t) qy * r.w + qx) * 4;
                tmp[q .. q + 4] = [acc[0], acc[1], acc[2], acc[3]];
            }
        r.px[] = tmp[];
    }
}

unittest
{
    // A single opaque pixel blurs into a normalized, alpha-preserving cloud:
    // mass conservation is the invariant that catches indexing errors. The
    // raster must be roomier than the widest cumulative reach: s=5 takes
    // three boxes of half-width 4, so ±12 per axis plus the source pixel.
    auto src = Raster(27, 27), d = Raster(0, 0);
    immutable at = (13 * 27 + 13) * 4;
    src.px[at .. at + 4] = [1, 1, 1, 1];
    assert(src.px[at + 3] == 1.0f && src.px[0] == 0.0f, "src: " ~ to!string(src.px[0 .. 8]));
    foreach (s; [0.5f, 2.0f, 5.0f])
    {
        gaussianBlur(d, src, s, s);
        float mass = 0.0f;
        foreach (i; 0 .. d.px.length / 4)
            mass += d.px[i * 4 + 3];
        assert(isClose(mass, 1.0f, 1e-4f), to!string([s, mass]));
    }
    // Blur with an out-of-range float: >1 alpha must average, not clip.
    src.px[] = 0.0f;
    src.px[at .. at + 4] = [3, 3, 3, 3]; // raw, legal
    gaussianBlur(d, src, 2.0f, 2.0f);
    float mass = 0.0f;
    foreach (i; 0 .. d.px.length / 4)
        mass += d.px[i * 4 + 3];
    assert(isClose(mass, 3.0f, 1e-3f), to!string(mass));
}

/// feTile §15.23: the input replicates through the whole output; the
/// top/left corner of tile (i,j) sits at (ax + i·tw, ay + j·th), where
/// (ax,ay,tw,th) is the INPUT image's filter primitive subregion - in
/// the same absolute device coordinates the rasters are indexed in,
/// so tile (0,0) coincides with the source's own position and content
/// is sampled verbatim. A tile position falling outside the source
/// image (its raster was cropped smaller than the subregion) stays
/// transparent black.
void tileRaster(ref Raster dst, in Raster src, int ax, int ay, int tw, int th)
{
    dst = Raster(src.w, src.h);
    if (tw <= 0 || th <= 0)
        return;

    foreach (int y; 0 .. dst.h)
    {
        immutable my = ((y - ay) % th + th) % th;
        immutable sy = ay + my;
        if (sy < 0 || sy >= src.h)
            continue;
        foreach (int x; 0 .. dst.w)
        {
            immutable mx = ((x - ax) % tw + tw) % tw;
            immutable sx = ax + mx;
            if (sx < 0 || sx >= src.w)
                continue;
            immutable d = (cast(size_t) y * dst.w + x) * 4, s = (cast(size_t) sy * src.w + sx) * 4;
            dst.px[d .. d + 4] = src.px[s .. s + 4];
        }
    }
}

unittest
{
    // A 2x1 red/green pair living at absolute columns 1-2, tiled from
    // anchor (1,0) with stride 2x1 across a 6x3 canvas: every column
    // and row carries the wrapped pattern green,red,green,red,...
    Raster src = Raster(6, 3), d = Raster(0, 0);
    src.px[(0 * 6 + 1) * 4 + 0] = 1.0f; src.px[(0 * 6 + 1) * 4 + 3] = 1.0f; // red @ row 0 col 1
    src.px[(0 * 6 + 2) * 4 + 1] = 1.0f; src.px[(0 * 6 + 2) * 4 + 3] = 1.0f; // green @ row 0 col 2
    tileRaster(d, src, 1, 0, 2, 1);
    string sig;
    foreach (int y; 0 .. d.h)
        foreach (int x; 0 .. d.w)
        {
            immutable p = (cast(size_t) y * d.w + x) * 4;
            sig ~= (d.px[p + 0] > 0 ? "R" : d.px[p + 1] > 0 ? "G" : ".");
        }
    assert(sig == "GRGRGRGRGRGRGRGRGR", sig);
    // A zero-size tile dimension disables the pattern.
    tileRaster(d, src, 1, 0, 0, 1);
    auto zero = d.dup;
    zero.px[] = 0.0f;
    assert(d.px == zero.px, to!string(d.px[0 .. 8]));
}

/// feImage §15.18: resample the working-space image into the device
/// placement rect. (sx,sy,tx,ty) is the viewFit matrix mapping natural
/// image pixels into the rect's viewport - uniform for meet/slice,
/// per-axis for "none". Sampling uses the <image> path's half-texel
/// registration (pixel centres at integer+0.5, bilinear on PM channels,
/// clamp at the border), so 1:1 placement is pixel exact.
void placeImage(ref Raster dst, in Raster img, float rx, float ry,
    float sx, float sy, float tx, float ty)
{
    dst = Raster(dst.w, dst.h);
    if (sx <= 0.0f || sy <= 0.0f || img.w < 1 || img.h < 1)
        return;

    immutable iw = img.w - 1, ih = img.h - 1;
    foreach (int y; 0 .. dst.h)
    {
        immutable v = (y + 0.5f - ry - ty) / sy - 0.5f;
        if (v < -0.5f || v > img.h - 0.5f)
            continue;
        immutable j0 = cast(int) floor(v), fv = v - j0;
        immutable jc = min(max(j0, 0), ih), j1 = min(j0 + 1, ih);
        foreach (int x; 0 .. dst.w)
        {
            immutable u = (x + 0.5f - rx - tx) / sx - 0.5f;
            if (u < -0.5f || u > img.w - 0.5f)
                continue;
            immutable i0 = cast(int) floor(u), fu = u - i0;
            immutable ic = min(max(i0, 0), iw), i1 = min(i0 + 1, iw);
            immutable top = (cast(size_t) jc * img.w) * 4, bot = (cast(size_t) j1 * img.w) * 4;
            immutable lc = cast(size_t) ic * 4, rc = cast(size_t) i1 * 4;
            immutable p = (cast(size_t) y * dst.w + x) * 4;
            foreach (c; 0 .. 4)
                dst.px[p + c] = (img.px[top + lc + c] * (1 - fu) + img.px[top + rc + c] * fu) * (1 - fv)
                    + (img.px[bot + lc + c] * (1 - fu) + img.px[bot + rc + c] * fu) * fv;
        }
    }
}

unittest
{
    // Two-pixel PM row (opaque red, half-alpha green) placed at 2x into
    // a 4x2 rect: the left column sits inside the replicated half-texel
    // border and takes the red verbatim, the next column the 3:1 PM
    // blend (pixel centre a quarter of the way to the green texel).
    Raster img = Raster(2, 1), d = Raster(4, 2);
    img.px[0] = 1.0f; img.px[3] = 1.0f;                 // red
    img.px[5] = 0.25f; img.px[7] = 0.5f;                // 0.5-alpha straight green, PM
    placeImage(d, img, 0, 0, 2.0f, 2.0f, 0.0f, 0.0f);
    assert(isClose(d.px[0], 1.0f) && isClose(d.px[3], 1.0f), to!string(d.px[0 .. 4]));
    auto mid = d.px[4 .. 8];
    assert(mid[0].isClose(0.75f) && mid[1].isClose(0.0625f) && mid[2] == 0.0f
        && mid[3].isClose(0.875f), to!string(mid));
    // Row 1 sits inside the half-texel border of the 1-tall source.
    assert(isClose(d.px[3 + 16], 1.0f), to!string(d.px[16 .. 20]));
    // 1:1 placement is pixel exact.
    placeImage(d, img, 1, 0, 1.0f, 1.0f, 0.0f, 0.0f);
    assert(d.px[4 .. 8] == img.px[0 .. 4] && d.px[8 .. 12] == img.px[4 .. 8],
        to!string(d.px[4 .. 12]));
}

// ---------------------------------------------------------------------------
// feTurbulence (§15.19/§15.24). The spec prints the exact algorithm -
// Park–Miller PRNG feeding a Perlin lattice - so the port below follows it
// verbatim: matching the suite's references is a matter of reproducing the
// PRNG sequence and the lattice indirection bit-for-bit, and every
// simplification here is a fusion the math can absorb (the four channels
// share one selector walk; doubling vec per octave is exact in binary FP).
// ---------------------------------------------------------------------------

private enum RandM = 2_147_483_647L; // 2**31 - 1
private enum RandA = 16_807L; // 7**5, primitive root of m
private enum RandQ = 127_773L; // m / a
private enum RandR = 2_836L; // m % a

/// §15.24 setup_seed: fold any seed into [1, m-1]. D's % matches C99's
/// (sign of the dividend), so negative seeds behave as written.
long turbSetupSeed(long s)
{
    if (s <= 0)
        s = -(s % (RandM - 1)) + 1;
    if (s > RandM - 1)
        s = RandM - 1;
    return s;
}

/// §15.24 random: Schrage-split Park–Miller step.
long turbRandom(long s)
{
    immutable r = RandA * (s % RandQ) - RandR * (s / RandQ);
    return r <= 0 ? r + RandM : r;
}

unittest
{
    // The spec's own self-test: seed 1 must yield 1043618065 as the
    // 10,000th generated number.
    auto s = 1L;
    foreach (i; 0 .. 10_000)
        s = turbRandom(s);
    assert(s == 1_043_618_065L);

    // setup_seed mappings the suite leans on (filters-turb-02-f): 0 and
    // every negative seed fold up into the positive sequence.
    assert(turbSetupSeed(0) == 1);
    assert(turbSetupSeed(-1) == 2);
    assert(turbSetupSeed(-2) == 3);
    assert(turbSetupSeed(2_147_483_648L) == 2_147_483_646L);
}

/// One turbulence instance: §15.24 init's shuffled lattice selector and
/// per-channel gradient tables. The mirror range [BSize, 2·BSize] exists so
/// the b00-style lookups (permutation value + lattice index, up to 510)
/// never fall off the end.
struct Turbulence
{
    enum BSize = 0x100;
    enum BM = 0xff;
    enum PerlinN = 0x1000;

    int[BSize + BSize + 2] sel;
    // D's type syntax reads inside-out: this is c × index × xy, like C's
    // fGradient[4][BSize + BSize + 2][2].
    double[2][BSize + BSize + 2][4] grad;

    this(long seed)
    {
        auto ls = turbSetupSeed(seed);
        foreach (c; 0 .. 4)
            foreach (n; 0 .. BSize)
            {
                sel[n] = n;
                foreach (m; 0 .. 2)
                    grad[c][n][m] = (cast(double) cast(int)
                        ((ls = turbRandom(ls)) % (BSize + BSize)) - BSize) / BSize;
                immutable s = sqrt(grad[c][n][0] ^^ 2 + grad[c][n][1] ^^ 2);
                grad[c][n][0] /= s;
                grad[c][n][1] /= s;
            }
        // C's `while (--i)` resumes from the init loop at i == BSize and
        // exits at 0: slot 0 is never a loop slot (though it can still
        // trade values as a swap partner).
        for (int i = BSize; --i;)
        {
            immutable k = sel[i];
            immutable j = cast(int) ((ls = turbRandom(ls)) % BSize);
            sel[i] = sel[j];
            sel[j] = k;
        }
        foreach (n; 0 .. BSize + 2)
        {
            sel[BSize + n] = sel[n];
            foreach (c; 0 .. 4)
                foreach (m; 0 .. 2)
                    grad[c][BSize + n][m] = grad[c][n][m];
        }
    }
}

unittest
{
    auto t = Turbulence(1);
    // the init shuffle only swaps through slots 255..1, but slot 0 can
    // still be a swap partner: all that survives is that sel is a
    // permutation over 0..255 with the mirror copies beyond.
    int sum = 0;
    foreach (n; 0 .. Turbulence.BSize)
        sum += t.sel[n];
    assert(sum == (Turbulence.BSize * (Turbulence.BSize - 1)) / 2);
    assert(t.sel[Turbulence.BSize] == t.sel[0]);
    foreach (c; 0 .. 4)
        foreach (n; 0 .. Turbulence.BSize)
        {
            immutable len = sqrt(t.grad[c][n][0] ^^ 2 + t.grad[c][n][1] ^^ 2);
            assert(len > 0.99 && len < 1.01); // gradients are unit vectors
        }
}

/// Stitching state for one octave (§15.24 StitchInfo).
struct TurbStitch
{
    int nWidth, nHeight; // lattice cells to subtract to wrap
    int nWrapX, nWrapY;  // first lattice index that wraps
}

private double turbSCurve(double t)
{
    return t * t * (3.0 - 2.0 * t);
}

/// §15.24 noise2 evaluated for all four channels at once: the lattice walk
/// (indices, raw offsets, smoothstep weights) is channel-independent, so
/// one walk + four dot products is the same arithmetic as four noise2
/// calls. A null stitch pointer means noStitch.
double[4] turbNoise4(ref const Turbulence t, double vx, double vy,
    const(TurbStitch)* stitch)
{
    auto tx = vx + Turbulence.PerlinN;
    auto bx0 = cast(int) tx;
    auto bx1 = bx0 + 1;
    immutable rx0 = tx - cast(int) tx;
    immutable rx1 = rx0 - 1.0;
    auto ty = vy + Turbulence.PerlinN;
    auto by0 = cast(int) ty;
    auto by1 = by0 + 1;
    immutable ry0 = ty - cast(int) ty;
    immutable ry1 = ry0 - 1.0;
    if (stitch !is null)
    {
        if (bx0 >= stitch.nWrapX)
            bx0 -= stitch.nWidth;
        if (bx1 >= stitch.nWrapX)
            bx1 -= stitch.nWidth;
        if (by0 >= stitch.nWrapY)
            by0 -= stitch.nHeight;
        if (by1 >= stitch.nWrapY)
            by1 -= stitch.nHeight;
    }
    bx0 &= Turbulence.BM;
    bx1 &= Turbulence.BM;
    by0 &= Turbulence.BM;
    by1 &= Turbulence.BM;
    immutable i = t.sel[bx0], j = t.sel[bx1];
    immutable b00 = t.sel[i + by0], b10 = t.sel[j + by0];
    immutable b01 = t.sel[i + by1], b11 = t.sel[j + by1];
    immutable sx = turbSCurve(rx0), sy = turbSCurve(ry0);

    double[4] acc;
    foreach (c; 0 .. 4)
    {
        auto u = rx0 * t.grad[c][b00][0] + ry0 * t.grad[c][b00][1];
        auto v = rx1 * t.grad[c][b10][0] + ry0 * t.grad[c][b10][1];
        immutable a = u + sx * (v - u);
        u = rx0 * t.grad[c][b01][0] + ry1 * t.grad[c][b01][1];
        v = rx1 * t.grad[c][b11][0] + ry1 * t.grad[c][b11][1];
        immutable b = u + sx * (v - u);
        acc[c] = a + sy * (b - a);
    }
    return acc;
}

/// Generate turbulence into the box (a canvas-sized raster; only `box`
/// is written). Frequencies arrive as lattice cycles per raster pixel in
/// the same space the raster indexes: a pixel at index x samples the
/// lattice at (x + x0)·fx. §15.24 turbulence(): each octave doubles vec
/// and ratio; fractalNoise sums signed samples / ratio, turbulence sums
/// |sample| / ratio. Color conversion follows the section's two formulas
/// ((v·255 + 255)/2 for fractalNoise, v·255 for turbulence, each clamped
/// to 0..255); the generated channels are straight values, premultiplied
/// on the way into the working-image format.
void turbulenceFill(ref Raster dst, in IBox4 box, long seed,
    double fx, double fy, int octaves, bool fractal, bool stitchTiles,
    double x0, double y0)
{
    auto t = Turbulence(seed);
    if (octaves > 12)
        octaves = 12; // keep a silly octave count from stalling the frame

    // §15.24: stitchTiles snaps the first-octave frequency to an integral
    // lattice count across the subregion, whichever side moves it less
    // relatively, then sets the wrap thresholds. The products below are
    // dimensionless lattice counts, so pixel-space inputs are as correct
    // as the reference's user-space ones.
    TurbStitch[16] oct;
    if (stitchTiles)
    {
        immutable tw = cast(double) (box.x1 - box.x0);
        immutable th = cast(double) (box.y1 - box.y0);
        if (tw > 0 && fx != 0.0)
        {
            immutable lo = floor(tw * fx) / tw, hi = ceil(tw * fx) / tw;
            fx = fx / lo < hi / fx ? lo : hi;
        }
        if (th > 0 && fy != 0.0)
        {
            immutable lo = floor(th * fy) / th, hi = ceil(th * fy) / th;
            fy = fy / lo < hi / fy ? lo : hi;
        }
        oct[0].nWidth = cast(int) (tw * fx + 0.5);
        oct[0].nWrapX = cast(int) ((box.x0 + x0) * fx + Turbulence.PerlinN + oct[0].nWidth);
        oct[0].nHeight = cast(int) (th * fy + 0.5);
        oct[0].nWrapY = cast(int) ((box.y0 + y0) * fy + Turbulence.PerlinN + oct[0].nHeight);
    }
    foreach (k; 1 .. octaves)
    {
        // Reference octave update: nWidth *= 2; nWrap = 2·nWrap - PerlinN.
        oct[k].nWidth = oct[k - 1].nWidth * 2;
        oct[k].nWrapX = oct[k - 1].nWrapX * 2 - Turbulence.PerlinN;
        oct[k].nHeight = oct[k - 1].nHeight * 2;
        oct[k].nWrapY = oct[k - 1].nWrapY * 2 - Turbulence.PerlinN;
    }

    foreach (y; max(0, box.y0) .. min(dst.h, box.y1))
        foreach (x; max(0, box.x0) .. min(dst.w, box.x1))
        {
            auto vecx = (x + x0) * fx;
            auto vecy = (y + y0) * fy;
            auto ratio = 1.0;
            double[4] sum = [0.0, 0.0, 0.0, 0.0];
            foreach (k; 0 .. octaves)
            {
                immutable n = turbNoise4(t, vecx, vecy, stitchTiles ? &oct[k] : null);
                foreach (c; 0 .. 4)
                    sum[c] += (fractal ? n[c] : fabs(n[c])) / ratio;
                vecx *= 2;
                vecy *= 2;
                ratio *= 2; // doubling a power-of-two-scaled sum: exact
            }

            immutable i = (cast(size_t) y * dst.w + x) * 4;
            double[4] v;
            foreach (c; 0 .. 4)
                v[c] = clamp(fractal ? (sum[c] * 255.0 + 255.0) / 2.0 : sum[c] * 255.0,
                    0.0, 255.0) / 255.0;
            // Straight -> premultiplied, the working-image convention.
            dst.px[i .. i + 4] = [to!float(v[0] * v[3]), to!float(v[1] * v[3]),
                to!float(v[2] * v[3]), to!float(v[3])];
        }
}

unittest
{
    Raster r = Raster(16, 16);
    IBox4 box = IBox4(0, 0, 16, 16);

    // Same seed, same image; different seeds, different image.
    turbulenceFill(r, box, 7, 0.05, 0.05, 2, false, false, 0, 0);
    Raster r2 = Raster(16, 16);
    turbulenceFill(r2, box, 7, 0.05, 0.05, 2, false, false, 0, 0);
    assert(r.px == r2.px);
    turbulenceFill(r2, box, 8, 0.05, 0.05, 2, false, false, 0, 0);
    assert(r.px != r2.px);

    // In range, premultiplied (color <= alpha), and the box outside is
    // left alone.
    foreach (i; 0 .. r.px.length / 4)
    {
        immutable o = i * 4;
        foreach (c; 0 .. 4)
            assert(r.px[o + c] >= 0.0f && r.px[o + c] <= 1.0f);
        foreach (c; 0 .. 3)
            assert(r.px[o + c] <= r.px[o + 3] + 1e-5f);
    }
    Raster r3 = Raster(16, 16);
    turbulenceFill(r3, IBox4(4, 4, 8, 8), 7, 0.05, 0.05, 1, false, false, 0, 0);
    assert(r3.px[0 .. 16 * 4].all!(v => v == 0.0f)); // untouched rows

    // Absolute anchoring: sampling at offset pixels equals sampling the
    // same coordinates in a full raster.
    Raster full = Raster(16, 16);
    turbulenceFill(full, box, 7, 0.05, 0.05, 1, false, false, 0, 0);
    assert(r3.px[(cast(size_t) 5 * 16 + 5) * 4] == full.px[(cast(size_t) 5 * 16 + 5) * 4]);

    // fractalNoise centers near mid gray; turbulence type keeps the
    // |value| distribution below it.
    Raster fr = Raster(16, 16);
    turbulenceFill(fr, box, 3, 0.1, 0.1, 1, true, false, 0, 0);
    float mean = 0.0f;
    foreach (i; 0 .. fr.px.length / 4)
        mean += fr.px[i * 4]; // premultiplied red skews low, so just a sanity bound
    assert(mean >= 0.0f);
}

// ---------------------------------------------------------------------------
// feDisplacementMap (§15.15): P'(x,y) ← P(x + scale·(XC − 0.5),
// y + scale·(YC − 0.5)). The driving channels come off in2 unpremultiplied
// (the section says so explicitly); `in` stays premultiplied throughout and
// gets sampled bilinearly. Pixel centers sit at integer indices, so an
// integer shift is an exact copy, and input pushed off the raster's extent
// is simply gone.
// ---------------------------------------------------------------------------

void displaceMap(ref Raster dst, in Raster src, in Raster map,
    double scaleX, double scaleY, int xc, int yc)
{
    dst = Raster(src.w, src.h);
    if (scaleX == 0.0 && scaleY == 0.0)
    {
        dst.px[] = src.px[]; // scale 0: "no effect on the source image"
        return;
    }
    foreach (y; 0 .. dst.h)
        foreach (x; 0 .. dst.w)
        {
            immutable mp = (cast(size_t) y * map.w + x) * 4;
            immutable ma = map.px[mp + 3];
            immutable cx = xc == 3 ? ma : (ma > 0.0f ? map.px[mp + xc] / ma : 0.0);
            immutable cy = yc == 3 ? ma : (ma > 0.0f ? map.px[mp + yc] / ma : 0.0);
            immutable u = x + scaleX * (cx - 0.5);
            immutable v = y + scaleY * (cy - 0.5);
            immutable i0 = cast(int) floor(u), j0 = cast(int) floor(v);
            if (i0 < -1 || i0 >= src.w || j0 < -1 || j0 >= src.h)
                continue; // wholly off the input: transparent
            immutable fu = u - i0, fv = v - j0;

            immutable o = (cast(size_t) y * dst.w + x) * 4;
            float[4] outv = [0.0f, 0.0f, 0.0f, 0.0f];
            foreach (dy; 0 .. 2)
            {
                immutable iy = j0 + dy;
                if (iy < 0 || iy >= src.h)
                    continue; // transparent sample: contributes nothing
                foreach (dx; 0 .. 2)
                {
                    immutable ix = i0 + dx;
                    if (ix < 0 || ix >= src.w)
                        continue;
                    immutable wt = (dx ? fu : 1.0f - fu) * (dy ? fv : 1.0f - fv);
                    if (wt == 0.0f)
                        continue;
                    immutable sp = (cast(size_t) iy * src.w + ix) * 4;
                    foreach (c; 0 .. 4)
                        outv[c] += cast(float) wt * src.px[sp + c];
                }
            }
            dst.px[o .. o + 4] = outv;
        }
}

unittest
{
    Raster src = Raster(8, 8);
    immutable dot = (cast(size_t) 5 * 8 + 5) * 4;
    src.px[dot .. dot + 4] = [1.0f, 0.0f, 0.0f, 1.0f]; // red dot

    // scale 0 copies verbatim (§15.15).
    Raster d0 = Raster(0, 0);
    displaceMap(d0, src, Raster(8, 8), 0.0, 0.0, 0, 1);
    assert(d0.px == src.px);

    // A map of constant R = 1 shifts source lookups by scale·0.5 in +x,
    // so scale 4 makes the dot appear 2 px left of where it was.
    Raster map = Raster(8, 8);
    foreach (i; 0 .. map.px.length / 4)
        map.px[i * 4 .. i * 4 + 4] = [1.0f, 0.0f, 0.0f, 1.0f]; // R straight = 1
    Raster d1 = Raster(0, 0);
    displaceMap(d1, src, map, 4.0, 0.0, 0, 3);
    assert(d1.px[(cast(size_t) 5 * 8 + 3) * 4] == 1.0f);
    assert(d1.px[(cast(size_t) 5 * 8 + 5) * 4] == 0.0f);

    // Half-pixel shift bilinearly splits between neighbors.
    Raster d2 = Raster(0, 0);
    displaceMap(d2, src, map, 1.0, 0.0, 0, 3); // shift left by 0.5
    assert(d1.px != d2.px);
    immutable got = d2.px[(cast(size_t) 5 * 8 + 5) * 4];
    assert(got > 0.45f && got < 0.55f);

    // Straightening: alpha 0.5, PM red 0.5 => straight R = 1, same shift
    // as the opaque map; a map pixel with zero alpha reads as channel 0.
    Raster map2 = Raster(8, 8);
    foreach (i; 0 .. map2.px.length / 4)
        map2.px[i * 4 .. i * 4 + 4] = [0.5f, 0.0f, 0.0f, 0.5f];
    Raster d3 = Raster(0, 0);
    displaceMap(d3, src, map2, 4.0, 0.0, 0, 3);
    assert(d3.px[(cast(size_t) 5 * 8 + 3) * 4] == 1.0f);
}

// ---------------------------------------------------------------------------
// feMorphology (§15.20): component-wise max (dilate) or min (erode) over a
// rectangular kernel - width 2·rx, height 2·ry, so integer offsets [-r, r).
// The section stresses that the operation runs on premultiplied values;
// samples beyond the input extent are transparent black, which dilate
// shrugs off and erode chokes on, eating the edges inward.
// ---------------------------------------------------------------------------

void morphology(ref Raster dst, in Raster src, int rx, int ry, bool dilate)
{
    dst = Raster(src.w, src.h);
    if (rx <= 0 || ry <= 0)
        return; // radius 0: "the result is a transparent black image"

    foreach (y; 0 .. dst.h)
        foreach (x; 0 .. dst.w)
        {
            float[4] best;
            foreach (c; 0 .. 4)
                best[c] = dilate ? -float.max : float.max;
            foreach (dy; -ry .. ry)
                foreach (dx; -rx .. rx)
                {
                    immutable iy = y + dy, ix = x + dx;
                    float[4] pv = [0.0f, 0.0f, 0.0f, 0.0f];
                    if (ix >= 0 && ix < src.w && iy >= 0 && iy < src.h)
                    {
                        immutable sp = (cast(size_t) iy * src.w + ix) * 4;
                        pv[] = src.px[sp .. sp + 4];
                    }
                    foreach (c; 0 .. 4)
                        best[c] = dilate ? max(best[c], pv[c]) : min(best[c], pv[c]);
                }
            immutable o = (cast(size_t) y * dst.w + x) * 4;
            dst.px[o .. o + 4] = best;
        }
}

unittest
{
    Raster src = Raster(8, 8);
    // Solid 3x3 red block at (3,3)..(5,5), alpha 1.
    foreach (y; 3 .. 6)
        foreach (x; 3 .. 6)
        {
            immutable b = (cast(size_t) y * 8 + x) * 4;
            src.px[b .. b + 4] = [1.0f, 0.0f, 0.0f, 1.0f];
        }

    // erode r=1: the 2x2 window in [-1,0) x [-1,0) leaves the block's
    // upper-right survivors at (4,4)..(5,5) - thin features vanish.
    Raster e1 = Raster(0, 0);
    morphology(e1, src, 1, 1, false);
    assert(e1.px[(cast(size_t) 4 * 8 + 4) * 4] == 1.0f);
    assert(e1.px[(cast(size_t) 5 * 8 + 5) * 4] == 1.0f);
    assert(e1.px[(cast(size_t) 3 * 8 + 3) * 4] == 0.0f);
    assert(e1.px[(cast(size_t) 6 * 8 + 6) * 4] == 0.0f);

    // dilate r=1: the same window fattens the block rightward/downward.
    Raster d1 = Raster(0, 0);
    morphology(d1, src, 1, 1, true);
    assert(d1.px[(cast(size_t) 3 * 8 + 3) * 4] == 1.0f);
    assert(d1.px[(cast(size_t) 6 * 8 + 6) * 4] == 1.0f);
    assert(d1.px[(cast(size_t) 2 * 8 + 2) * 4] == 0.0f);

    // radius 0 disables: transparent black.
    Raster e0 = Raster(0, 0);
    morphology(e0, src, 0, 0, false);
    assert(e0.px.all!(v => v == 0.0f));

    // erode eats against the raster edge: a solid field erodes away from
    // the boundary.
    Raster full = Raster(8, 8);
    full.px[] = 1.0f;
    Raster e2 = Raster(0, 0);
    morphology(e2, full, 1, 1, false);
    assert(e2.px[0] == 0.0f);
    assert(e2.px[(cast(size_t) 1 * 8 + 1) * 4] == 1.0f);
}

// ---------------------------------------------------------------------------
// The filter model: <filter> + primitives, read straight off the arena.
// ---------------------------------------------------------------------------

/// A <filter> resolved through its xlink:href inheritance chain (§15.1): a
/// filter without primitives inherits the referenced filter's children, and
/// undefined attributes fall back along the chain. Dangling or cyclic hrefs
/// simply end the walk.
struct FilterSpec
{
    // The filter effects region (§15.5). Defaults -10%/-10%/120%/120%; in
    // objectBoundingBox units (the default) numbers are fractions of the
    // source bbox, so "120%" and 1.2 mean the same width. Kept as raw
    // strings: <length> resolution needs the renderer's LengthCtx and CTM.
    string x = "-10%", y = "-10%", width = "120%", height = "120%";
    bool objBB = true;     // filterUnits; objectBoundingBox is the default
    bool primsObjBB;       // primitiveUnits (§15.3); default userSpaceOnUse
    bool linearRGB = true; // color-interpolation-filters; §15.2 initial value
    size_t[] prims;        // arena indices, document order
}

FilterSpec makeFilter(ref const Document doc, size_t target)
{
    FilterSpec f;

    size_t[] chain = [target];
    for (size_t cur = target; ; )
    {
        immutable href = doc.nodes[cur].attrs.get("href",
            doc.nodes[cur].attrs.get("xlink:href", ""));
        if (href.length < 2 || href[0] != '#')
            break;
        immutable nxt = doc.byId(href[1 .. $]);
        if (nxt == Document.unknown || nxt == target || chain.canFind(nxt))
            break; // dangling or cyclic: the chain just ends here
        chain ~= nxt;
        cur = nxt;
    }

    // The first filter in the chain with primitive children wins (§15.1).
    foreach (fi; chain)
    {
        foreach (ch; doc.nodes[fi].children)
            if (!doc.nodes[ch].name.empty)
                f.prims ~= ch;
        if (f.prims.length)
            break;
    }

    // Attribute lookup falls back along the same chain.
    string attr(string name)
    {
        foreach (fi; chain)
            if (auto p = name in doc.nodes[fi].attrs)
                return *p;
        return null;
    }

    immutable fu = attr("filterUnits");
    if (fu !is null && ieq(fu, "userSpaceOnUse"))
        f.objBB = false; // invalid values: the objectBoundingBox default stands
    immutable pu = attr("primitiveUnits");
    if (pu !is null)
        f.primsObjBB = ieq(pu, "objectBoundingBox"); // invalid: userSpaceOnUse
    immutable cif = attr("color-interpolation-filters");
    if (cif !is null && ieq(cif, "sRGB"))
        f.linearRGB = false; // inherit / auto / invalid: §15.2 initial value stands

    immutable xs = attr("x"), ys = attr("y"), ws = attr("width"), hs = attr("height");
    if (xs !is null && xs.length) f.x = xs;
    if (ys !is null && ys.length) f.y = ys;
    if (ws !is null && ws.length) f.width = ws;
    if (hs !is null && hs.length) f.height = hs;

    return f;
}

