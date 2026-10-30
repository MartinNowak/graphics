module graphics.svg.gradient;

import std.algorithm, std.conv, std.exception, std.math, std.range, std.string;
import graphics.core.matrix;
import graphics.core.pmcolor;
import graphics.core.shader;
import graphics.svg.color;
import graphics.svg.core : transformSVG;
import graphics.svg.parser;
import graphics.svg.pserver;
import guip.point, guip.rect;

// SVG 1.1 §13.2 gradients: linear/radial paint servers built from the
// document's <linearGradient>/<radialGradient> elements. Blitter.Choose hands
// a MappingShader the CTM inverse, so mapPt(device) lands in user space; the
// shaders then do one more step of their own - the sample point is carried
// into the gradient's coordinate system, which is user space for
// gradientUnits="userSpaceOnUse" and the shape's bbox for objectBoundingBox
// units (the default). See GradSpace below for why that step is a map and
// not something folded into the geometry.

enum Spread { pad, reflect, repeat }

struct GradientStop
{
    float offset;
    PMColor color; // premultiplied, with stop-opacity folded in
}

// §7.11: gradientUnits="objectBoundingBox" (the default) installs a
// supplemental matrix taking the gradient's unit square onto the referencing
// shape's bbox - and that matrix is *non-uniform* unless the box is square.
// Both shaders therefore keep their geometry in the gradient's own coordinate
// system and carry the sample point back through this map instead of folding
// the per-axis scales into the numbers: that is what makes a radial gradient
// in a non-square box an ellipse (§13.2.3) and keeps a linear ramp's iso-lines
// perpendicular to the axis in gradient space. userSpaceOnUse keeps it the
// identity.
//
// §13.2.2's gradientTransform rides underneath that: it maps the gradient's
// own coordinates into the space its numbers are authored in - the bbox unit
// square for objectBoundingBox units, user space for userSpaceOnUse - so once
// one is present the map is a general affine and not just a pair of per-axis
// scales.
struct GradSpace
{
    // The map runs gradient -> user, laid out as graphics.core.matrix.Matrix
    // is: x' = a*x + c*y + e, y' = b*x + d*y + f. The per-axis extents are
    // never zero (a flat bbox is an error, and a gradientTransform that
    // collapses the plane cannot be undone); the origin stays in user units.
    double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;

    this(double x0, double y0, double sx, double sy)
    {
        this.e = x0;
        this.f = y0;
        this.a = sx;
        this.d = sy;
    }

    /// Append a gradientTransform, which the gradient's own coordinates go
    /// through first: the product stays left-to-right, the same way
    /// transformSVG accumulates a transform list.
    void compose(in Matrix gt)
    {
        immutable double
            na = a * gt[0][0] + c * gt[1][0],
            nb = b * gt[0][0] + d * gt[1][0],
            nc = a * gt[0][1] + c * gt[1][1],
            nd = b * gt[0][1] + d * gt[1][1],
            ne = a * gt[0][2] + c * gt[1][2] + e,
            nf = b * gt[0][2] + d * gt[1][2] + f;
        a = na;
        b = nb;
        c = nc;
        d = nd;
        e = ne;
        f = nf;
    }

    /// Sampling means walking the map backwards, so a gradient that cannot be
    /// undone cannot paint (see makeGradient's @return).
    @property bool invertible() const
    {
        return b == 0 && c == 0 ? (a != 0 && d != 0) : (a * d - b * c != 0);
    }

    // The sample point in the gradient's own coordinates, in double. Two
    // reasons, and they compound: objectBoundingBox numbers are fractions,
    // so the map divides by a length that runs to hundreds of user units;
    // and spreadMethod's folding is discontinuous, so a sample the spec
    // places exactly on a period boundary lands on the other colour if the
    // arithmetic is 24-bit - the reference renders put that boundary on a
    // whole pixel column.
    Point!double op(in FPoint p) const
    {
        // Translate/scale only (every gradient in the suite without a
        // gradientTransform, and most with one): stay on the plain divides.
        // The general form below is equivalent algebra but not the same bits,
        // and those boundary columns are decided in the last bits.
        if (b == 0 && c == 0)
            return Point!double((p.x - e) / a, (p.y - f) / d);
        immutable det = a * d - b * c; // invertible() promised it non-zero
        return Point!double((d * (p.x - e) - c * (p.y - f)) / det,
            (a * (p.y - f) - b * (p.x - e)) / det);
    }
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
    this(Point!double p0, Point!double p1, GradientStop[] stops,
        Spread spread, GradSpace space)
    {
        this.p0 = p0;
        this.p1 = p1;
        this.stops = stops;
        this.spread = spread;
        this.space = space;
        immutable double dx = p1.x - p0.x, dy = p1.y - p0.y;
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

    static PMColor colorAt(LinearGradientShader pthis, in FPoint p)
    {
        if (pthis.denom == 0) // §13.2.2: a degenerate vector paints the
            return pthis.stops[$ - 1].color; // last stop's color solid
        // §7.11: the vector, and the iso-lines perpendicular to it, belong to
        // the gradient's own space, so the sample point comes through the map.
        immutable pt = pthis.space.op(p);
        immutable vx = pthis.p1.x - pthis.p0.x, vy = pthis.p1.y - pthis.p0.y;
        immutable t = ((pt.x - pthis.p0.x) * vx + (pt.y - pthis.p0.y) * vy)
            / pthis.denom;
        return sampleStops(pthis.stops, pthis.spread, cast(float) t);
    }

    Point!double p0, p1;
    GradientStop[] stops;
    Spread spread;
    GradSpace space;
    private double denom;
}

// <radialGradient> (§13.2.1/§13.2.4): the ramp runs over the family of
// circles with centre f + t*(c - f) and radius r*t (t=0 collapses at the
// focus f). Solving |pt - centre(t)| = r*t is the spec's suggested t-finder.
class RadialGradientShader : MappingShader
{
    this(Point!double c, double r, Point!double f, GradientStop[] stops,
        Spread spread, GradSpace space)
    {
        this.c = c;
        this.r = r;
        // §13.2.3: a focal point outside the end circle snaps to the
        // intersection of the (c -> f) ray with that circle - in the
        // gradient's own units, which is where the circle is defined.
        immutable double Lx = f.x - c.x, Ly = f.y - c.y;
        immutable double d2 = Lx * Lx + Ly * Ly;
        if (r > 0 && d2 > r * r)
        {
            immutable k = r / sqrt(d2);
            f = Point!double(c.x + Lx * k, c.y + Ly * k);
        }
        this.f = f;
        this.stops = stops;
        this.spread = spread;
        this.space = space;
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

    static PMColor colorAt(RadialGradientShader pthis, in FPoint p)
    {
        if (pthis.r <= 0) // §13.2.3: r=0 paints the last stop's colour solid
            return pthis.stops[$ - 1].color;

        // Everything below measures in the gradient's own space, where an
        // objectBoundingBox circle is a circle and the shape's non-uniform
        // bbox map waits outside (§7.11) - in double, for the same reason
        // the map itself is double.
        immutable pt = pthis.space.op(p);
        immutable double Lx = pthis.c.x - pthis.f.x, Ly = pthis.c.y - pthis.f.y;
        immutable Dx = pthis.f.x - pt.x, Dy = pthis.f.y - pt.y;

        if (Dx == 0 && Dy == 0) // at the focus: t = 0
            return sampleStops(pthis.stops, pthis.spread, 0);

        // The gradient lives on the circles centred f + t*(c - f) with
        // radius r*t; |pt - centre(t)| = r*t expands, with D = f - pt and
        // L = c - f, to (L.L - r^2) t^2 + 2 (D.L) t + D.D = 0.
        immutable a = Lx * Lx + Ly * Ly - pthis.r * pthis.r;
        immutable b = 2 * (Dx * Lx + Dy * Ly);
        immutable cq = Dx * Dx + Dy * Dy;

        double t;
        if (a == 0) // focus exactly on the end circle: the t^2 term goes,
        {           // and with it the far side of that circle
            if (b >= 0) // b == 0 asks cq = 0 of a point that is not the
                return sampleStops(pthis.stops, pthis.spread, 1); // focus
            t = -cq / b;
        }
        else
        {
            auto disc = b * b - 4 * a * cq;
            if (disc < 0) // no circle of the family reaches this point
                return sampleStops(pthis.stops, pthis.spread, 1);
            disc = sqrt(disc);
            // Roots the last bits can be trusted with. The textbook pair is
            // not merely inelegant here: §13.2.3's focal snap leaves |L| == r
            // up to rounding, so a is often a residual of one ulp and then
            // (-b +/- disc) is a difference of nearly equal numbers over that
            // residual - pservers-grad-21-b's third row turned into plateaus
            // of constant alpha, and the far side of its end circle painted
            // stop[0] instead of padding. q keeps the half of the formula
            // whose numerator cannot cancel; the product of the roots (cq/a)
            // gives the other half for free.
            immutable q = -(b + copysign(disc, b)) / 2;
            immutable t1 = q / a;
            immutable t2 = q == 0 ? 0 : cq / q;
            // A point belongs to one circle of the family with t >= 0: with
            // the focus inside the end circle (a < 0) the two roots straddle
            // zero and the positive one is it, while both negative means the
            // family points the other way and the point is outside it.
            if (t1 < 0 && t2 < 0)
                return sampleStops(pthis.stops, pthis.spread, 1);
            t = t1 < 0 ? t2 : (t2 < 0 ? t1 : min(t1, t2));
        }
        return sampleStops(pthis.stops, pthis.spread, cast(float) t);
    }

    Point!double c, f;
    double r;
    GradientStop[] stops;
    Spread spread;
    GradSpace space;
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
/// an xlink:href leading outside the gradient elements or cycling, a
/// gradientTransform that does not parse or cannot be undone, no
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

    // percentage bases: fractions of the bbox, or viewport lengths. Double,
    // along with the numbers read against them: §7.11's map divides those by
    // the box extent, and spreadMethod folds t at hard discontinuities, so
    // the reference's answer at a boundary column is decided by whether the
    // author's 0.4 stays 0.4 or enters as 0.4f (pservers-grad-10-b is that
    // boundary, twice over).
    immutable double pxScale = userSpace ? vpW : 1.0;
    immutable double pyScale = userSpace ? vpH : 1.0;
    immutable double prScale =
        userSpace ? sqrt((vpW * vpW + vpH * vpH) / 2.0) : 1.0;

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

    // cx/cy/r default to "50%" (§7.5: in userSpaceOnUse the r basis is the
    // normalized diagonal; with objectBoundingBox every one of these is a
    // fraction), fx/fy to cx/cy - all resolved per unit system already.
    immutable cx = attr(chain, "cx", pxScale * 0.5, pxScale);
    immutable cy = attr(chain, "cy", pyScale * 0.5, pyScale);
    immutable r = attr(chain, "r", prScale * 0.5, prScale);
    immutable fx = attr(chain, "fx", cx, pxScale);
    immutable fy = attr(chain, "fy", cy, pyScale);

    // The objectBoundingBox-resolved numbers are bbox fractions, and §7.11's
    // mapping onto the shape's user-space box goes to the shaders as a map
    // rather than being folded into them: it is non-uniform whenever the box
    // is not square, and that is exactly the geometry at stake. A flat box
    // bailed out above, so the map's per-axis sizes cannot be zero.
    GradSpace space;
    if (userSpace)
        space = GradSpace(0, 0, 1, 1); // the identity
    else
        space = GradSpace(bbox.left, bbox.top, bbox.width, bbox.height);

    // §13.2.2: gradientTransform establishes the coordinate system the
    // geometry numbers are authored in, so it goes under the map above and
    // not over it - for objectBoundingBox units the whole transformed unit
    // square is then carried onto the bbox, per-axis scales last. It inherits
    // along the href chain like the other gradient attributes. A malformed
    // list puts the server in error (pattern.d's patternTransform rule), and
    // so does a transform that turns the plane inside out: a matrix(0 0 0 0)
    // stops rendering, and anything else with a zero determinant leaves
    // nothing to sample, because the shaders walk this map backwards.
    if (auto t = strAttr(chain, "gradientTransform"))
    {
        Matrix gt;
        try
        {
            if (!transformSVG(gt, t))
                return null;
        }
        catch (Exception)
            return null;
        space.compose(gt);
    }
    if (!space.invertible)
        return null;

    if (radial)
    {
        if (r < 0)
            return null; // negative r is a parse error (§13.2.3)
        // With objectBoundingBox units every number is a fraction - cx/cy/
        // fx/fy of the matching axis, r of the unit square - so r stays a
        // single number and the ellipse is the map's doing. §13.2.3's focal
        // clamp belongs to the same space as the end circle, so it happens
        // inside the shader.
        return new RadialGradientShader(Point!double(cx, cy), r,
            Point!double(fx, fy), stops, spread, space);
    }

    immutable x1 = attr(chain, "x1", 0.0, pxScale);
    immutable y1 = attr(chain, "y1", 0.0, pyScale);
    immutable x2 = attr(chain, "x2", pxScale, pxScale);
    immutable y2 = attr(chain, "y2", 0.0, pyScale);
    // A zero-length vector is not an error: §13.2.2 paints the last stop
    // solid (the shader's colourAt handles it).
    return new LinearGradientShader(Point!double(x1, y1), Point!double(x2, y2),
        stops, spread, space);
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
    // §13.2.2: gradientTransform establishes the system that x1/y1/x2/y2 are
    // authored in, so translate(20 5) scale(2) moves the (0,0)-(10,0) vector
    // onto user (20,5)-(40,5) - pservers-grad-06-b's top bar at half scale.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0"
            gradientTransform="translate(20 5) scale(2)">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </linearGradient>
        </svg>`);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "g", FRect(0, 0, 10, 10), 10, 10, 1.0f);
    assert(sh !is null, "a valid transform list is no error");
    auto c = LinearGradientShader.colorAt(sh, FPoint(20, 5));
    assert(c.r == 255, "the ramp starts where the transform puts x1");
    c = LinearGradientShader.colorAt(sh, FPoint(40, 5));
    assert(c.b == 255, "and ends where it puts x2");
    c = LinearGradientShader.colorAt(sh, FPoint(50, 5));
    assert(c.b == 255, "pad holds past the end");
    c = LinearGradientShader.colorAt(sh, FPoint(30, 5));
    assert(c.r >= 124 && c.r <= 128 && c.b >= 124 && c.b <= 128, "half-way along the span");
    c = LinearGradientShader.colorAt(sh, FPoint(30, 25)); // a scaled unit off the axis
    assert(c.r >= 124 && c.r <= 128 && c.b >= 124 && c.b <= 128,
        "iso-lines stay perpendicular in gradient space");
}

unittest
{
    // A skew is where the inverse map stops being a pair of divides:
    // translate(240,155) skewX(45) on an r=60 radial (pservers-grad-06-b's
    // middle bar) sends gradient (x,y) to user (x+y+240, y+155), so the
    // circle paints as a tilted ellipse - user (270,185) sits 42 user px
    // from the centre but only 30 gradient units out, i.e. mid-ramp.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <radialGradient id="g" gradientUnits="userSpaceOnUse" cx="0" cy="0" fx="0" fy="0" r="60"
            gradientTransform="translate(240,155) skewX(45)">
            <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </radialGradient>
        </svg>`);
    auto sh = cast(RadialGradientShader) makeGradient(doc, "g", FRect(0, 0, 10, 10), 10, 10, 1.0f);
    assert(sh !is null);
    auto c = RadialGradientShader.colorAt(sh, FPoint(240, 155));
    assert(c.r == 255, "the focus rides along with the transform");
    c = RadialGradientShader.colorAt(sh, FPoint(300, 215)); // gradient (0,60): on the circle
    assert(c.b == 255 && c.r == 0, "the sheared edge is stop[1]");
    c = RadialGradientShader.colorAt(sh, FPoint(270, 185)); // gradient (0,30)
    assert(c.r >= 124 && c.r <= 128 && c.b >= 124 && c.b <= 128,
        "measured in gradient units, not user ones");
}

unittest
{
    // §7.11's bbox map composes *over* gradientTransform, never under it:
    // objectBoundingBox units with rotate(90) on a 20x10 box put the default
    // unit-square ramp (0,0)-(1,0) on user (0,0)-(0,10). The other order
    // would run it along the bottom edge, out to (20,0).
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="g" gradientTransform="rotate(90)">
            <stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>
        </linearGradient>
        </svg>`);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "g", FRect(0, 0, 20, 10), 20, 10, 1.0f);
    assert(sh !is null);
    auto c = LinearGradientShader.colorAt(sh, FPoint(0, 10));
    assert(c.r > 250, "up the left edge, in box fractions");
    c = LinearGradientShader.colorAt(sh, FPoint(20, 0));
    assert(c.r == 0, "not along the bottom edge");
}

unittest
{
    // A gradientTransform that cannot be read or cannot be undone puts the
    // server in error, matching pattern.d's patternTransform rule, and the
    // attribute inherits along the href chain like the geometry ones.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink">
        <linearGradient id="junk" gradientTransform="translate(abc)">
            <stop offset="0" stop-color="lime"/><stop offset="1" stop-color="red"/>
        </linearGradient>
        <linearGradient id="singular" gradientTransform="scale(0)">
            <stop offset="0" stop-color="lime"/><stop offset="1" stop-color="red"/>
        </linearGradient>
        <linearGradient id="off" gradientTransform="matrix(0 0 0 0 5 5)">
            <stop offset="0" stop-color="lime"/><stop offset="1" stop-color="red"/>
        </linearGradient>
        <linearGradient id="par" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0"
            gradientTransform="translate(20)">
            <stop offset="0" stop-color="lime"/><stop offset="1" stop-color="red"/>
        </linearGradient>
        <linearGradient id="child" xlink:href="#par"/>
        </svg>`);
    immutable r10 = FRect(0, 0, 10, 10);
    assert(makeGradient(doc, "junk", r10, 10, 10, 1.0f) is null, "unparsable list");
    assert(makeGradient(doc, "singular", r10, 10, 10, 1.0f) is null, "scale(0) cannot be undone");
    assert(makeGradient(doc, "off", r10, 10, 10, 1.0f) is null, "matrix(0 0 0 0) disables it");
    auto sh = cast(LinearGradientShader) makeGradient(doc, "child", r10, 10, 10, 1.0f);
    assert(sh !is null, "the transform travels down the href chain");
    auto c = LinearGradientShader.colorAt(sh, FPoint(20, 0));
    assert(c.g == 255, "and sits under the geometry numbers it establishes");
    c = LinearGradientShader.colorAt(sh, FPoint(30, 0));
    assert(c.r == 255, "so the ramp ends at user x=30");
}

unittest
{
    // §7.11 + §13.2.3: objectBoundingBox geometry is a circle in the
    // gradient's own space and the bbox map is non-uniform, so on a
    // non-square box it paints an *ellipse* - r="50%" of a 120x90 box
    // reaches 60 px along x and 45 px along y, and pservers-grad-21-b's
    // guide ellipses (rx=24 ry=18 for r="20%") are exactly that shape.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <radialGradient id="ell">
            <stop offset="0" stop-color="lime"/>
            <stop offset="1" stop-color="red"/>
        </radialGradient>
        </svg>`);
    auto sh = cast(RadialGradientShader) makeGradient(doc, "ell",
        FRect(0, 0, 120, 90), 100, 100, 1.0f);
    assert(sh !is null, "built the ellipse gradient");
    auto c = RadialGradientShader.colorAt(sh, FPoint(60, 45));
    assert(c.g == 255 && c.r == 0, "the 0% stop sits at cx,cy");
    // Half an end-radius out along either axis: same ramp position, 30 px
    // of x or 22.5 px of y. Folding the box into a single radius (the old
    // normalized diagonal) puts these two at different t.
    immutable midX = RadialGradientShader.colorAt(sh, FPoint(90, 45));
    immutable midY = RadialGradientShader.colorAt(sh, FPoint(60, 22.5f));
    assert(midX == midY, "t=0.5 reaches 30 px right and 22.5 px up");
    assert(midX.r > 100 && midX.r < 200 && midX.g > 100 && midX.g < 200,
        "t=0.5 really is a blend");
    // One whole end-radius out, the same holds of the box edges: the ellipse
    // passes through both, and pad starts there. A 60 px circle would still
    // be blending at both.
    immutable edgeX = RadialGradientShader.colorAt(sh, FPoint(120, 45));
    immutable edgeY = RadialGradientShader.colorAt(sh, FPoint(60, 0));
    assert(edgeX == edgeY, "the end circle is the ellipse through both");
    assert(edgeX.r == 255 && edgeX.g == 0, "which is the 100% stop");
}

unittest
{
    // The same map for <linearGradient>: the ramp's iso-lines are
    // perpendicular to the axis in gradient space, so a diagonal ramp on a
    // non-square box is sheared - perpendicular to the unit square's
    // diagonal, not the box's.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <linearGradient id="diag" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="black"/>
            <stop offset="1" stop-color="white"/>
        </linearGradient>
        </svg>`);
    auto sh = cast(LinearGradientShader) makeGradient(doc, "diag",
        FRect(0, 0, 120, 90), 100, 100, 1.0f);
    assert(sh !is null, "built the sheared ramp");
    // Fractions (0.75,0) and (0,0.75) share t=0.375 - user (90,0) and
    // (0,67.5). Projection in user space instead would split them at
    // t=0.48 and t=0.27.
    immutable left = LinearGradientShader.colorAt(sh, FPoint(90, 0));
    immutable up = LinearGradientShader.colorAt(sh, FPoint(0, 67.5));
    assert(left == up, "iso-lines follow the unit square");
    assert(left.r > 60 && left.r < 130, "t=0.375 is a dark grey");
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
    // objectBoundingBox r is a fraction of the unit square, mapped by the
    // shape's box (§7.11).
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

    // bbox defaults cx=cy=r=50% of a 10x10 box: centre (5,5), and r is half
    // the box - 5 user units when the box is square, so (15,5) is past the
    // rim and pads at the last stop.
    auto sb = cast(RadialGradientShader) makeGradient(doc, "bb", r10, 100, 100, 1.0f);
    c = RadialGradientShader.colorAt(sb, FPoint(5, 5));
    assert(c.r == 255);
    c = RadialGradientShader.colorAt(sb, FPoint(15, 5));
    assert(c.r <= 3, "bbox r is half the box, so (15,5) pads at stop[last]");
    assert(makeGradient(doc, "r", FRect(5, 5, 5, 15), 100, 100, 1.0f)
        !is null, "userSpaceOnUse survives a flat bbox");

    // Flat bbox with bbox units: §7.11's supplemental (0,0)->(1,1)
    // mapping is degenerate, so the reference fails - the server errors
    // and paints nothing (pservers-grad-17-b's fallback case).
    assert(makeGradient(doc, "bb", FRect(5, 5, 5, 15), 100, 100, 1.0f)
        is null, "flat bbox + objectBoundingBox = server error");
}

unittest
{
    // §13.2.3's focal snap leaves the focus *on* the end circle, and that is
    // the one geometry where the t^2 coefficient of |pt - centre(t)| = r*t
    // vanishes - in a non-square bbox it usually survives as a one-ulp
    // residual, which is worse, because the solver then divides a difference
    // of nearly equal numbers by it. pservers-grad-21-b's third row is that
    // case (cx=100%, fx=25%, r=20% over a 120x90 box): the reference paints a
    // smooth ramp from the snapped focus to the centre and stop[1] over the
    // far side of the end circle. cx=0% with the same fx/fy/r reaches the
    // same geometry through exact arithmetic, so the two must agree.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <radialGradient id="c100" cx="100%" r="20%" fx="25%">
            <stop offset="0" stop-color="black"/>
            <stop offset="1" stop-color="black" stop-opacity="0"/>
        </radialGradient>
        <radialGradient id="c0" cx="0%" r="20%" fx="25%">
            <stop offset="0" stop-color="black"/>
            <stop offset="1" stop-color="black" stop-opacity="0"/>
        </radialGradient>
        </svg>`);
    immutable box = FRect(0, 0, 120, 90);

    // cx=100%: centre at x=120, focus snapped to x=96, end circle over x=96..144
    auto sa = cast(RadialGradientShader) makeGradient(doc, "c100", box, 120, 90, 1.0f);
    assert(sa !is null);
    assert(RadialGradientShader.colorAt(sa, FPoint(96, 45)).a == 255,
        "the snapped focus paints stop[0]");
    // t = 0.2917 on the axis there, so the fade sits at 255*(1-t)
    immutable mid = RadialGradientShader.colorAt(sa, FPoint(110, 45));
    assert(mid.a >= 178 && mid.a <= 183, to!string(mid.a));
    int prev = 256;
    foreach (x; 97 .. 120) // no plateau anywhere on the focus -> centre ramp
    {
        immutable alpha = RadialGradientShader.colorAt(sa, FPoint(x, 45)).a;
        assert(alpha < prev, to!string([x, alpha, prev]));
        prev = alpha;
    }
    // behind the focus, and past the end circle, no circle of the family
    // reaches: the fade runs out and pads at stop[1].
    assert(RadialGradientShader.colorAt(sa, FPoint(40, 45)).a == 0);

    // cx=0%: centre at x=0, focus snapped to x=24, end circle over x=-24..24
    auto sb = cast(RadialGradientShader) makeGradient(doc, "c0", box, 120, 90, 1.0f);
    assert(sb !is null);
    assert(RadialGradientShader.colorAt(sb, FPoint(24, 45)).a == 255);
    immutable same = RadialGradientShader.colorAt(sb, FPoint(10, 45));
    assert(same.a >= 178 && same.a <= 183, to!string(same.a)); // mirrors x=110 above
    immutable far = RadialGradientShader.colorAt(sb, FPoint(40, 45));
    assert(far.a == 0 && far.r == 0 && far.g == 0 && far.b == 0,
        "past the end circle pads at stop[1], not stop[0]");
}
