module graphics.svg.gradient;

import std.algorithm, std.conv, std.exception, std.math, std.range, std.string;
import graphics.core.pmcolor;
import graphics.core.shader;
import graphics.svg.color;
import graphics.svg.parser;
import graphics.svg.pserver;
import guip.point, guip.rect;

// SVG 1.1 §13.2 gradients: linear/radial paint servers built from the
// document's <linearGradient>/<radialGradient> elements. The shaders sample
// in *user space* - Blitter.Choose hands a MappingShader the CTM inverse,
// so mapPt(device) lands in the coordinate system the gradient geometry was
// authored in (gradientUnits="userSpaceOnUse"); objectBoundingBox units -
// the default - are resolved against the shape's bbox at build time.

enum Spread { pad, reflect, repeat }

struct GradientStop
{
    float offset;
    PMColor color; // premultiplied, with stop-opacity folded in
}

// Premultiplied interpolation (SVG 1.1 §13.2.3 requires premultiplied
// space). The weight pair {255-w, w} sums to 255, so this is the library's
// shift-8-exact form, mirroring GradientShader.colorAt.
private PMColor lerp(in PMColor a, in PMColor b, float u)
{
    immutable w = cast(ubyte) clamp(round(u * 255), 0.0f, 255.0f);
    // The additions stay in the library's Color+Color form (as in
    // GradientShader.colorAt) and land in a PMColor via alias-this.
    PMColor res;
    res = alphaMul(a, alphaScale(255 - w)) + alphaMul(b, alphaScale(w));
    return res;
}

// spreadMethod maps t into the [0,1] stop ramp (§13.2.4), then the stop
// list - sorted-at-build, offsets already forced monotonic - is sampled.
private PMColor sampleStops(const GradientStop[] stops, Spread spread, float t)
{
    assert(!stops.empty);

    final switch (spread)
    {
    case Spread.pad:
        break; // edge clamping below handles it
    case Spread.repeat:
        t -= floor(t);
        break;
    case Spread.reflect:
        immutable band = to!int(floor(t));
        t -= band;
        if (band & 1)
            t = 1 - t;
        break;
    }

    if (t <= stops[0].offset)
        return stops[0].color;
    if (t >= stops[$ - 1].offset)
        return stops[$ - 1].color;

    foreach (i; 0 .. stops.length - 1)
        if (t <= stops[i + 1].offset)
        {
            immutable span = stops[i + 1].offset - stops[i].offset;
            if (span <= 0) // zero-width ramp: the last stop listed wins
                return stops[i + 1].color;
            return lerp(stops[i].color, stops[i + 1].color,
                (t - stops[i].offset) / span);
        }
    return stops[$ - 1].color; // unreachable
}

// <linearGradient> (§13.2.2): the ramp runs along p0 -> p1 and is
// perpendicular-invariant. A zero-length vector paints the last stop
// solid (§13.2.2), handled in colourAt.
class LinearGradientShader : MappingShader
{
    this(FPoint p0, FPoint p1, GradientStop[] stops, Spread spread)
    {
        this.p0 = p0;
        this.p1 = p1;
        this.stops = stops;
        this.spread = spread;
        immutable dx = p1.x - p0.x, dy = p1.y - p0.y;
        this.denom = dx * dx + dy * dy;
    }

    override @property bool opaque() const
    {
        foreach (ref s; stops)
            if (!s.color.opaque)
                return false;
        return true;
    }

    override void getRange(float x, float y, PMColor[] data)
    {
        return mapLine!colorAt(this, x, y, data);
    }

    static PMColor colorAt(LinearGradientShader pthis, in FPoint pt)
    {
        if (pthis.denom == 0) // §13.2.2: a degenerate vector paints the
            return pthis.stops[$ - 1].color; // last stop's color solid
        immutable vx = pthis.p1.x - pthis.p0.x, vy = pthis.p1.y - pthis.p0.y;
        immutable t = ((pt.x - pthis.p0.x) * vx + (pt.y - pthis.p0.y) * vy)
            / pthis.denom;
        return sampleStops(pthis.stops, pthis.spread, t);
    }

    FPoint p0, p1;
    GradientStop[] stops;
    Spread spread;
    private float denom;
}

// <radialGradient> (§13.2.1/§13.2.4): the ramp runs over the family of
// circles with centre f + t*(c - f) and radius r*t (t=0 collapses at the
// focus f). Solving |pt - centre(t)| = r*t is the spec's suggested t-finder.
class RadialGradientShader : MappingShader
{
    this(FPoint c, float r, FPoint f, GradientStop[] stops, Spread spread)
    {
        this.c = c;
        this.r = r;
        // §13.2.3: a focal point outside the end circle snaps to the
        // intersection of the (c -> f) ray with that circle.
        immutable Lx = f.x - c.x, Ly = f.y - c.y;
        immutable d2 = Lx * Lx + Ly * Ly;
        if (r > 0 && d2 > r * r)
        {
            immutable k = r / sqrt(d2);
            f = FPoint(c.x + Lx * k, c.y + Ly * k);
        }
        this.f = f;
        this.stops = stops;
        this.spread = spread;
    }

    override @property bool opaque() const
    {
        foreach (ref s; stops)
            if (!s.color.opaque)
                return false;
        return true;
    }

    override void getRange(float x, float y, PMColor[] data)
    {
        return mapLine!colorAt(this, x, y, data);
    }

    static PMColor colorAt(RadialGradientShader pthis, in FPoint pt)
    {
        if (pthis.r <= 0) // §13.2.3: r=0 paints the last stop's colour solid
            return pthis.stops[$ - 1].color;

        immutable Lx = pthis.c.x - pthis.f.x, Ly = pthis.c.y - pthis.f.y;
        immutable Dx = pthis.f.x - pt.x, Dy = pthis.f.y - pt.y;

        if (Dx == 0 && Dy == 0) // at the focus: t = 0
            return sampleStops(pthis.stops, pthis.spread, 0);

        // The gradient lives on the circles centred f + t*(c - f) with
        // radius r*t; |pt - centre(t)| = r*t expands, with D = f - pt and
        // L = c - f, to (L.L - r^2) t^2 + 2 (D.L) t + D.D = 0.
        immutable a = Lx * Lx + Ly * Ly - pthis.r * pthis.r;
        immutable b = 2 * (Dx * Lx + Dy * Ly);
        immutable cq = Dx * Dx + Dy * Dy;

        float t;
        if (a == 0) // focus exactly on the end circle: linear equation
            t = b == 0 ? 0 : -cq / b;
        else
        {
            auto disc = b * b - 4 * a * cq;
            if (disc < 0) // no circle of the family reaches this point
                return sampleStops(pthis.stops, pthis.spread, 1);
            disc = sqrt(disc);
            immutable t1 = (-b + disc) / (2 * a);
            immutable t2 = (-b - disc) / (2 * a);
            // focus inside the end circle: both roots are >= 0 and the
            // larger is the paint; outside: the smaller touches first.
            immutable inside = Lx * Lx + Ly * Ly < pthis.r * pthis.r;
            t = inside ? max(t1, t2) : min(t1, t2);
            if (t < 0)
                t = 0;
        }
        return sampleStops(pthis.stops, pthis.spread, t);
    }

    FPoint c, f;
    float r;
    GradientStop[] stops;
    Spread spread;
}

/// Resolve `fill/stroke="url(#id)"` into a paint shader.
///
/// * `bbox` - the shape's user-space geometry bounds: objectBoundingBox
///   units (the default) are fractions of it.
/// * `vpW`/`vpH` - current viewport, the percentage basis for
///   gradientUnits="userSpaceOnUse".
/// * `paintAlpha` folds opacity x fill/stroke-opacity into the stop alphas.
///
/// Nothing about the referencing shape reaches the stops: `stop-color`,
/// `stop-opacity` and the currentColor base are inherited properties, and a
/// gradient takes them from its own place in the document tree (§13.2.4).
///
/// Returns null - caller paints as if the paint were none (or applies the
/// `url(...) paint` fallback) - when the server cannot paint: unknown id,
/// an xlink:href leading outside the gradient elements or cycling, no
/// stops anywhere in the chain, a flat bbox with objectBoundingBox units
/// (§7.11's supplemental mapping is degenerate), or a negative r. Per
/// §13.2 a zero-length linear vector and an r=0 radial are NOT errors:
/// they paint the last stop's colour solid.
Shader makeGradient(ref const(Document) doc, string id, in FRect bbox,
    float vpW, float vpH, float paintAlpha)
{
    immutable idx = doc.byId(id);
    if (idx == Document.unknown)
        return null;

    bool invalid;
    static const string[] gradientKinds = ["linearGradient", "radialGradient"];
    auto chain = hrefChain(doc, idx, invalid, gradientKinds);
    if (invalid || chain.empty)
        return null;

    immutable radial = chain[0].name == "radialGradient";
    if (chain[0].name != "linearGradient" && !radial)
        return null; // pattern & friends are separate servers (pattern lands next)

    // gradientUnits inherits along the href chain; anything but an
    // explicit userSpaceOnUse is the objectBoundingBox default.
    bool userSpace;
    foreach (ref e; chain)
        if (auto p = "gradientUnits" in e.attrs)
            if (auto v = lengthened(strip(*p)))
            {
                userSpace = toLower(v) == "userspaceonuse";
                break;
            }

    // §7.11: objectBoundingBox units insert a supplemental matrix mapping
    // (0,0)->(minx,miny), (1,1)->(maxx,maxy). A flat bbox makes that
    // matrix (and thus the reference) degenerate: server in error, paint
    // as if none - with the documented fallback if one was supplied
    // (pservers-grad-17-b is exactly this test). §7.11 aligns the bbox
    // with the referencing element's own user axes, so a rotated copy of
    // a flat line is still flat.
    if (!userSpace && (bbox.width <= 0 || bbox.height <= 0))
        return null;

    // percentage bases: fractions of the bbox, or viewport lengths.
    immutable pxScale = userSpace ? vpW : 1.0f;
    immutable pyScale = userSpace ? vpH : 1.0f;
    immutable prScale = userSpace ? sqrt((vpW * vpW + vpH * vpH) / 2.0f) : 1.0f;

    Spread spread = Spread.pad;
    foreach (ref e; chain)
        if (auto p = "spreadMethod" in e.attrs)
            if (auto v = lengthened(strip(*p)))
            {
                if (toLower(v) == "reflect")
                    spread = Spread.reflect;
                else if (toLower(v) == "repeat")
                    spread = Spread.repeat;
                break;
            }

    auto stops = stopsOf(doc, idx, chain, paintAlpha);
    if (stops.empty)
        return null; // no stops in the chain: gradient is an error state

    // cx/cy/r default to "50%" (§7.5: the r basis is the normalized
    // diagonal), fx/fy to cx/cy - all resolved per unit system already.
    immutable cx = attr(chain, "cx", pxScale * 0.5f, pxScale);
    immutable cy = attr(chain, "cy", pyScale * 0.5f, pyScale);
    immutable r = attr(chain, "r", prScale * 0.5f, prScale);
    immutable fx = attr(chain, "fx", cx, pxScale);
    immutable fy = attr(chain, "fy", cy, pyScale);

    // objectBoundingBox-resolved values are bbox fractions: map them into
    // the shape's user-space box (§13.2.1; a flat box bailed out above).
    auto bx = (float v) => userSpace ? v : bbox.left + v * bbox.width;
    auto by = (float v) => userSpace ? v : bbox.top + v * bbox.height;
    immutable brScale = userSpace
        ? 1.0f
        : sqrt((bbox.width * bbox.width + bbox.height * bbox.height) / 2.0f);

    if (radial)
    {
        immutable ur = userSpace ? r : r * brScale;
        if (ur < 0)
            return null; // negative r is a parse error (§13.2.3)
        return new RadialGradientShader(FPoint(bx(cx), by(cy)), ur,
            FPoint(bx(fx), by(fy)), stops, spread);
    }

    immutable x1 = attr(chain, "x1", 0.0f, pxScale);
    immutable y1 = attr(chain, "y1", 0.0f, pyScale);
    immutable x2 = attr(chain, "x2", pxScale, pxScale);
    immutable y2 = attr(chain, "y2", 0.0f, pyScale);
    // A zero-length vector is not an error: §13.2.2 paints the last stop
    // solid (the shader's colourAt handles it).
    return new LinearGradientShader(FPoint(bx(x1), by(y1)),
        FPoint(bx(x2), by(y2)), stops, spread);
}

private:

// The values a gradient's stops may reach for. `color` is an inherited
// property (§12.2), so it simply travels down the tree; `stop-color` and
// `stop-opacity` are not (§13.2.4's tables both say Inherited: no), so what
// travels is only the value a written `inherit` names: the nearest
// declaration above, or the initial value - black, 1 - if none was written.
private struct StopScope
{
    Color color;      // the currentColor base
    Color stopColor;
    float stopOpacity;
}

// The arena keeps children only, so a <defs> element's ancestors are
// recovered by walking down from the root: `path` ends up holding
// root..target, which is the order inheritance is applied in.
private bool descend(ref const(Document) doc, size_t idx, size_t target,
    ref size_t[] path)
{
    path ~= idx;
    if (idx == target)
        return true;
    foreach (ch; doc.nodes[idx].children)
        if (doc.nodes[ch].name.length && descend(doc, ch, target, path))
            return true;
    path.length -= 1; // back out: this branch does not hold the target
    return false;
}

// One ancestor's declarations, applied while descending toward the gradient.
// A declaration moves the value and everything else leaves it alone:
// `inherit` asks for precisely what the walk is already carrying, and a
// value the parser rejects is a declaration the cascade drops (CSS
// §6.5.1). currentColor binds the element's own color, which the `color`
// case above has just folded in (§11.2).
private void cascadeProps(ref StopScope sc, in Element e)
{
    if (auto p = "color" in e.attrs)
    {
        Color c;
        if (parsePaint(strip(*p), c))
            sc.color = c;
    }
    if (auto p = "stop-color" in e.attrs)
    {
        immutable v = toLower(strip(*p));
        if (v == "currentcolor")
            sc.stopColor = sc.color;
        else
        {
            Color c;
            if (parsePaint(v, c))
                sc.stopColor = c;
        }
    }
    if (auto p = "stop-opacity" in e.attrs)
    {
        immutable v = strip(*p);
        if (!v.empty && toLower(v) != "inherit")
            try
                sc.stopOpacity = clamp(to!float(v), 0.0f, 1.0f);
            catch (ConvException)
                {} // malformed number: the declaration is dropped
    }
}

// The values in effect at the gradient element `idx`: the ancestors'
// declarations top-down, then the element's own (§13.2.4).
private StopScope scopeFor(ref const(Document) doc, size_t idx)
{
    StopScope sc = StopScope(Color.Black, Color.Black, 1.0f);
    size_t[] path;
    if (!descend(doc, doc.root, idx, path))
        return sc; // the node is not in this document: initial values
    foreach (i; path)
        cascadeProps(sc, doc.nodes[i]);
    return sc;
}

// Chain links past the head are xlink:href targets, so each one carries an
// `id` and the registry maps it back to its own place in the tree; the head
// stands in when the link carries no usable `id`.
private size_t chainIndex(ref const(Document) doc, in Element e,
    size_t fallback)
{
    auto p = "id" in e.attrs;
    immutable idx = p ? doc.byId(strip(*p)) : Document.unknown;
    return idx == Document.unknown ? fallback : idx;
}

// A stop's own stop-color and stop-opacity. Leaving the property out is the
// property's *initial* value - black, 1 - and not the parent's, because
// §13.2.4's tables say both are Inherited: no; pservers-grad-18-b's
// lower-left rectangle spells the consequence, a stop that names nothing
// going to fully opaque black even though its gradient hangs off a
// `<g stop-color="#f48" stop-opacity="0.5">`. Writing `inherit` is what
// reaches up the tree instead, and currentColor binds `color`, which really
// is inherited (§12.2) - that is color-prop-01-b's green middle stop.
private struct StopValue
{
    Color color;
    float opacity;
}

private StopValue stopValue(in Element se, ref const(StopScope) sc)
{
    StopValue sv = StopValue(Color.Black, 1.0f);

    Color col = sc.color; // `color` travels in, a declaration here wins
    if (auto p = "color" in se.attrs)
    {
        Color c;
        if (parsePaint(strip(*p), c))
            col = c;
    }
    if (auto p = "stop-color" in se.attrs)
    {
        immutable v = toLower(strip(*p));
        if (v == "inherit")
            sv.color = sc.stopColor;
        else if (v == "currentcolor")
            sv.color = col;
        else
        {
            Color c;
            if (parsePaint(v, c))
                sv.color = c;
        }
    }
    if (auto p = "stop-opacity" in se.attrs)
    {
        immutable v = strip(*p);
        if (toLower(v) == "inherit")
            sv.opacity = sc.stopOpacity;
        else
            try
                sv.opacity = clamp(to!float(v), 0.0f, 1.0f);
            catch (ConvException)
                {} // malformed number: the initial value stands
    }
    return sv;
}

// The stops of the first gradient in the chain that defines any (§13.2.3:
// href-inherited stops come from the closest ancestor that has them).
// Offsets are clamped to [0,1] and forced monotonic in document order;
// stop-opacity and the paint's own alpha fold into the stop's Color
// before it is premultiplied. Nothing of the referencing shape reaches a
// stop: the definition's own place in the tree is the scope (§13.2.4).
GradientStop[] stopsOf(ref const(Document) doc, size_t head,
    const(Element)[] chain, float paintAlpha)
{
    immutable pa = clamp(paintAlpha, 0.0f, 1.0f);

    foreach (ci, ref e; chain)
    {
        GradientStop[] res;
        float prev;
        // §13.2.2: an href template's stops keep the template's ancestors.
        immutable owner = ci == 0 ? head : chainIndex(doc, e, head);
        immutable base = scopeFor(doc, owner);
        foreach (ch; e.children)
        {
            auto se = doc.nodes[ch];
            if (se.name != "stop")
                continue;

            immutable sv = stopValue(se, base);
            immutable cl = clamp(attr([se], "offset", 0.0f, 1.0f), 0.0f, 1.0f);
            immutable off = prev > cl ? prev : cl; // (max overload soup in GDC)
            prev = off;

            Color c = sv.color;
            c.a = to!ubyte(round(c.a * sv.opacity * pa));
            res ~= GradientStop(off, PMColor(c));
        }
        // §13.2.4: tied offsets - the later stop controls the overlap
        // point, exactly modelled by the spec's own nudge of the earlier
        // stop a hair below (sub-pixel for any real gradient).
        foreach (i; 1 .. res.length)
            if (res[i].offset == res[i - 1].offset)
                res[i - 1].offset = res[i].offset - 1e-6f;
        if (!res.empty)
            return res;
    }
    return null;
}

unittest
{
    // userSpaceOnUse linear ramp: exact edge stops, pad clamps beyond the
    // vector, midpoint is the premultiplied blend; getRange maps a device
    // span through the (identity) shader matrix into user space.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
            <stop offset="0" stop-color="#ff0000"/>
            <stop offset="1" stop-color="#0000ff"/>
        </linearGradient>
        </svg>`);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "g", FRect(0, 0, 10, 10), 10, 10, 1.0f);
    assert(sh !is null && sh.opaque && sh.needsMatrix);

    auto c = LinearGradientShader.colorAt(sh, FPoint(0, 5));
    assert(c.r == 255 && c.g == 0 && c.b == 0, "start stop");
    c = LinearGradientShader.colorAt(sh, FPoint(10, 5));
    assert(c.b == 255 && c.r == 0, "end stop");
    c = LinearGradientShader.colorAt(sh, FPoint(-3, 5)); // pad before
    assert(c.r == 255 && c.b == 0);
    c = LinearGradientShader.colorAt(sh, FPoint(20, 5)); // pad past
    assert(c.b == 255 && c.r == 0);
    c = LinearGradientShader.colorAt(sh, FPoint(5, 5));
    assert(c.r >= 124 && c.r <= 128 && c.b >= 124 && c.b <= 128, "midpoint blend ~50/50");

    PMColor[3] data;
    sh.getRange(0, 5, data[]); // identity shader matrix: device == user
    assert(data[0].r == 255);
    assert(data[1].b > data[0].b && data[2].b > data[1].b, "ramp across the span");
}

unittest
{
    // objectBoundingBox (the default) resolves fractions of the shape's
    // bbox - x1/x2 default to 0%/100%; spreadMethod reflect/repeat wrap
    // the ramp beyond the vector (§13.2.4).
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="g">
            <stop stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient>
        <linearGradient id="rl" spreadMethod="reflect">
            <stop stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient>
        <linearGradient id="rp" spreadMethod="repeat" x1="50%">
            <stop stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient>
        </svg>`);
    immutable bbox = FRect(10, 0, 20, 10); // shape spans x 10..20

    auto sh = cast(LinearGradientShader) makeGradient(doc, "g", bbox, 10, 10, 1.0f);
    auto c = LinearGradientShader.colorAt(sh, FPoint(10, 5));
    assert(c.r == 0, "bbox left edge is the ramp start");
    c = LinearGradientShader.colorAt(sh, FPoint(20, 5));
    assert(c.r > 250, "bbox right edge is the ramp end");

    sh = cast(LinearGradientShader) makeGradient(doc, "rl", bbox, 10, 10, 1.0f);
    auto mid = LinearGradientShader.colorAt(sh, FPoint(15, 5));
    auto mirrored = LinearGradientShader.colorAt(sh, FPoint(25, 5)); // t=1.5 folds to 0.5
    assert(mid.r == mirrored.r && mid.g == mirrored.g && mid.b == mirrored.b, "reflect folds back");
    immutable nearStart = LinearGradientShader.colorAt(sh, FPoint(11, 5)); // t=0.1: dark
    assert(nearStart.r < mid.r, "sanity: t=0.1 is darker than t=0.5");
    immutable folded = LinearGradientShader.colorAt(sh, FPoint(29, 5)); // t=1.9 folds to 0.1
    assert(folded.r == nearStart.r, "reflect mirror is symmetric");

    // x1="50%" of the bbox is user x=15: the vector (15,0)-(20,0) tiles left.
    sh = cast(LinearGradientShader) makeGradient(doc, "rp", bbox, 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(sh, FPoint(12.5, 5)); // t=-0.5 repeats to 0.5
    assert(c.r == mid.r && c.g == mid.g && c.b == mid.b, "repeat tiles the ramp");
    c = LinearGradientShader.colorAt(sh, FPoint(10, 5)); // t=-1 repeats to 0
    assert(c.r == 0, "repeat tile starts at stop[0]");
}

unittest
{
    // xlink:href inheritance: stops and unset geometry attributes come
    // from the chain; an href to a different gradient kind, an href
    // cycle, no stops anywhere, or an unknown id all paint nothing.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink">
        <linearGradient id="base" gradientUnits="userSpaceOnUse" x1="0" y1="3" x2="10">
            <stop offset="0" stop-color="lime"/>
            <stop offset="1" stop-color="red"/>
        </linearGradient>
        <linearGradient id="kid" xlink:href="#base" x2="5"/>
        <radialGradient id="wrong" xlink:href="#base"/>
        <linearGradient id="c1" xlink:href="#c2"/>
        <linearGradient id="c2" xlink:href="#c1"/>
        <linearGradient id="nostops" gradientUnits="userSpaceOnUse" x1="0" x2="1"/>
        <linearGradient id="pt" gradientUnits="userSpaceOnUse" x1="5" y1="5" x2="5" y2="5">
            <stop offset="1" stop-color="red"/>
        </linearGradient>
        </svg>`);
    immutable r10 = FRect(0, 0, 10, 10);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "kid", r10, 10, 10, 1.0f);
    assert(sh !is null, "inherited the base's stops");
    // gradientUnits + x1/y1 inherited, x2 redefined locally: vector (0,3)->(5,0)
    auto c = LinearGradientShader.colorAt(sh, FPoint(0, 3));
    assert(c.g == 255 && c.r == 0, "ramp starts at the inherited x1,y1");
    c = LinearGradientShader.colorAt(sh, FPoint(5, 0));
    assert(c.r == 255 && c.g == 0, "local x2 ends the ramp");

    assert(makeGradient(doc, "c1", r10, 10, 10, 1.0f) is null, "href cycle");
    assert(makeGradient(doc, "nostops", r10, 10, 10, 1.0f) is null, "no stops");
    assert(makeGradient(doc, "nope", r10, 10, 10, 1.0f) is null, "unknown id");

    // §13.2: an href may lead to either gradient kind - "wrong" is a
    // radialGradient inheriting the linear base's stops and units.
    auto xk = cast(RadialGradientShader) makeGradient(doc, "wrong", r10, 10, 10, 1.0f);
    assert(xk !is null, "cross-kind href inherits (§13.2.3)");
    auto xc = RadialGradientShader.colorAt(xk, FPoint(5, 5)); // radial defaults: cx=cy=50% of the userSpace viewport (10x10), r=50% of the normalised diagonal (5)
    assert(xc.g == 255 && xc.r == 0, "inherited stop[0] at the centre");
    xc = RadialGradientShader.colorAt(xk, FPoint(10, 5));
    assert(xc.r == 255 && xc.g == 0, "inherited stop[last] on the rim");

    // §13.2.2: zero-length vector is not an error - solid last stop.
    auto pt = cast(LinearGradientShader) makeGradient(doc, "pt", r10, 10, 10, 1.0f);
    assert(pt !is null, "zero-length vector paints");
    immutable pc = LinearGradientShader.colorAt(pt, FPoint(3, 7));
    assert(pc.r == 255 && pc.g == 0 && pc.b == 0, to!string([pc.r, pc.g, pc.b]));
}

unittest
{
    // Stops: offsets clamp to [0,1] then force monotonic in document
    // order; stop-opacity and the paint's alpha fold into the stop's
    // Color *before* premultiplication, and the gradient turns non-opaque.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="s" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
            <stop offset="0.8" stop-color="white" stop-opacity="0.5"/>
            <stop offset="0.3" stop-color="lime"/>
            <stop offset="1" stop-color="black"/>
        </linearGradient>
        </svg>`);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "s",
        FRect(0, 0, 10, 10), 10, 10, 0.5f);
    assert(sh !is null && !sh.opaque);

    // t=0 clamps to stops[0]: white x stop-opacity 0.5 x paint alpha 0.5
    // -> alpha 64, premultiplied channel ~64.
    auto c = LinearGradientShader.colorAt(sh, FPoint(0, 0));
    assert(c.a >= 60 && c.a <= 66 && c.r >= 60 && c.r <= 66, to!string([c.a, c.r]));
    // offsets forced to [0.8, 0.8, 1.0] - at t=0.9 (x=9) the ramp runs
    // from the (later-listed) lime toward black; both stops carry paint
    // alpha 0.5 (lime a=128, black a=128) so the premultiplied midpoint
    // keeps a=128 with green halved.
    c = LinearGradientShader.colorAt(sh, FPoint(9, 0));
    assert(c.a >= 126 && c.a <= 130 && c.g >= 62 && c.g <= 66 && c.r < 4,
        to!string([c.a, c.r, c.g]));

    // §13.2.4 tied stops: the latter stop controls the overlap point, so
    // the spec's white/red|blue/black example jumps red -> blue at t=0.2
    // and the black ramp runs from the blue.
    doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="tie" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
            <stop offset="0" stop-color="white"/>
            <stop offset=".2" stop-color="red"/>
            <stop offset=".2" stop-color="blue"/>
            <stop offset="1" stop-color="black"/>
        </linearGradient>
        </svg>`);
    auto ts = cast(LinearGradientShader) makeGradient(doc, "tie",
        FRect(0, 0, 10, 10), 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(ts, FPoint(2, 0)); // t = 0.2 exactly
    assert(c.b == 255 && c.r == 0, to!string([c.r, c.b]));
    c = LinearGradientShader.colorAt(ts, FPoint(1.9, 0)); // end of the white->red ramp
    assert(c.r > 240 && c.g < 40 && c.b < 40, to!string([c.r, c.g, c.b]));
    c = LinearGradientShader.colorAt(ts, FPoint(5, 0)); // blue->black ramp, u=0.375
    assert(c.b >= 155 && c.b <= 163 && c.r < 4 && c.g < 4, to!string([c.r, c.g, c.b]));
}

unittest
{
    // §13.2.4 scope: the stops read the gradient definition's place in the
    // tree, never the shape that references the server. pservers-grad-18-b
    // hangs four gradients off `<g stop-color="#f48" stop-opacity="0.5"
    // color="yellow">` while the four rects sit in groups that all say
    // something else, and the reference PNGs follow the gradients.
    // stop-color/stop-opacity are Inherited: no, so `inherit` names the
    // nearest declaration above while a property the stop leaves out stays
    // at its initial value.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <g stop-color="#f48" stop-opacity="0.5" color="yellow">
            <linearGradient id="inh" stop-color="inherit" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="green" stop-opacity="1"/>
                <stop offset="1" stop-color="inherit" stop-opacity="1"/>
            </linearGradient>
            <linearGradient id="op" stop-opacity="inherit" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="green" stop-opacity="1"/>
                <stop offset="1" stop-color="green" stop-opacity="inherit"/>
            </linearGradient>
            <linearGradient id="unnamed" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="green" stop-opacity="1"/>
                <stop offset="1"/>
            </linearGradient>
            <linearGradient id="cc" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
                <stop offset="0" stop-color="green"/>
                <stop offset="1" stop-color="currentColor" stop-opacity="1"/>
            </linearGradient>
        </g>
        <linearGradient id="own" color="#700" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
            <stop offset="1" stop-color="currentColor"/>
        </linearGradient>
        </svg>`);
    immutable r10 = FRect(0, 0, 10, 10);

    auto sh = cast(LinearGradientShader) makeGradient(doc, "inh", r10, 10, 10, 1.0f);
    auto c = LinearGradientShader.colorAt(sh, FPoint(10, 0));
    assert(c.a == 255 && c.r >= 250 && c.g >= 60 && c.g <= 76 && c.b >= 128
        && c.b <= 144, to!string([c.a, c.r, c.g, c.b])); // the group's pink
    c = LinearGradientShader.colorAt(sh, FPoint(0, 0));
    assert(c.a == 255 && c.g == 128 && c.r == 0, to!string([c.a, c.r, c.g])); // CSS green

    sh = cast(LinearGradientShader) makeGradient(doc, "op", r10, 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(sh, FPoint(10, 0)); // green at 0.5, premultiplied
    assert(c.a >= 126 && c.a <= 130 && c.g >= 62 && c.g <= 66 && c.r < 4,
        to!string([c.a, c.r, c.g]));

    // the lower-left rectangle: fully opaque black, not the group's pink
    sh = cast(LinearGradientShader) makeGradient(doc, "unnamed", r10, 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(sh, FPoint(10, 0));
    assert(c.a == 255 && c.r == 0 && c.g == 0 && c.b == 0, to!string([c.a, c.r, c.g, c.b]));

    // currentColor: the group's yellow, and `color` written on the gradient
    // itself (styling-inherit-01-b) beats the group's.
    sh = cast(LinearGradientShader) makeGradient(doc, "cc", r10, 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(sh, FPoint(10, 0));
    assert(c.a == 255 && c.r == 255 && c.g == 255 && c.b == 0, to!string([c.a, c.r, c.g, c.b]));

    sh = cast(LinearGradientShader) makeGradient(doc, "own", r10, 10, 10, 1.0f);
    c = LinearGradientShader.colorAt(sh, FPoint(10, 0)); // #700
    assert(c.a == 255 && c.r >= 115 && c.r <= 123 && c.g < 4 && c.b < 4,
        to!string([c.a, c.r, c.g, c.b]));
}

unittest
{
    // Radial: t is found on the family of circles centred f + t*(c-f)
    // with radius r*t; the focus paints stop[0], the rim stop[last];
    // objectBoundingBox r is the shape's normalized diagonal.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <radialGradient id="r" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="5">
            <stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/>
        </radialGradient>
        <radialGradient id="f" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="5" fx="2.5" fy="5">
            <stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/>
        </radialGradient>
        <radialGradient id="zero" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="0">
            <stop offset="1"/>
        </radialGradient>
        <radialGradient id="neg" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="-1">
            <stop offset="1"/>
        </radialGradient>
        <radialGradient id="oc" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="2" fx="20" fy="5">
            <stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/>
        </radialGradient>
        <radialGradient id="bb">
            <stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/>
        </radialGradient>
        </svg>`);
    immutable r10 = FRect(0, 0, 10, 10);
    auto sh = cast(RadialGradientShader) makeGradient(doc, "r", r10, 100, 100, 1.0f);
    assert(sh !is null && sh.opaque);
    auto c = RadialGradientShader.colorAt(sh, FPoint(5, 5));
    assert(c.r == 255, "centre (== focus) paints stop[0]");
    c = RadialGradientShader.colorAt(sh, FPoint(10, 5));
    assert(c.r == 0, "rim paints stop[last]");
    c = RadialGradientShader.colorAt(sh, FPoint(7.5, 5));
    assert(c.r >= 124 && c.r <= 128, "half radius is the blend midpoint");
    c = RadialGradientShader.colorAt(sh, FPoint(0, 5)); // t=1 on the opposite side
    assert(c.r == 0);
    c = RadialGradientShader.colorAt(sh, FPoint(15, 5)); // past the rim: pad
    assert(c.r == 0, "beyond the family pads at stop[last]");

    auto sf = cast(RadialGradientShader) makeGradient(doc, "f", r10, 100, 100, 1.0f);
    c = RadialGradientShader.colorAt(sf, FPoint(2.5, 5));
    assert(c.r == 255, "the focal point paints stop[0]");
    c = RadialGradientShader.colorAt(sf, FPoint(10, 5));
    assert(c.r == 0, "the far side of the end circle pads");

    assert(makeGradient(doc, "neg", r10, 100, 100, 1.0f) is null,
        "negative r is a parse error (§13.2.3)");

    // §13.2.3: r=0 paints the last stop solid rather than erroring out.
    auto sz = cast(RadialGradientShader) makeGradient(doc, "zero", r10, 100, 100, 1.0f);
    assert(sz !is null);
    immutable zc = RadialGradientShader.colorAt(sz, FPoint(50, 50));
    assert(zc.r == 0 && zc.g == 0 && zc.b == 0 && zc.a == 255, "default stop colour black");

    // §13.2.3: fx outside the circle snaps onto it.
    auto oc = cast(RadialGradientShader) makeGradient(doc, "oc", r10, 100, 100, 1.0f);
    assert(oc !is null);
    c = RadialGradientShader.colorAt(oc, FPoint(7, 5));
    assert(c.r == 255, "clamped focal point paints stop[0]");
    c = RadialGradientShader.colorAt(oc, FPoint(3, 5));
    assert(c.r == 0, "opposite side of the r=2 circle reaches t=1");

    // bbox defaults cx=cy=r=50% of a 10x10 box: centre (5,5),
    // r = sqrt((100+100)/2) = 10 user units.
    auto sb = cast(RadialGradientShader) makeGradient(doc, "bb", r10, 100, 100, 1.0f);
    c = RadialGradientShader.colorAt(sb, FPoint(5, 5));
    assert(c.r == 255);
    c = RadialGradientShader.colorAt(sb, FPoint(15, 5));
    assert(c.r <= 3, "bbox r is the box diagonal (10), so (15,5) is the rim");
    assert(makeGradient(doc, "r", FRect(5, 5, 5, 15), 100, 100, 1.0f)
        !is null, "userSpaceOnUse survives a flat bbox");

    // Flat bbox with bbox units: §7.11's supplemental (0,0)->(1,1)
    // mapping is degenerate, so the reference fails - the server errors
    // and paints nothing (pservers-grad-17-b's fallback case).
    assert(makeGradient(doc, "bb", FRect(5, 5, 5, 15), 100, 100, 1.0f)
        is null, "flat bbox + objectBoundingBox = server error");
}
