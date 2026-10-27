module graphics.svg.pattern;

import std.algorithm, std.conv, std.math, std.string;
import graphics.core.matrix, graphics.core.pmcolor, graphics.core.shader;
import graphics.svg.core : transformSVG;
import graphics.svg.parser;
import graphics.svg.pserver;
import guip.point, guip.rect;

// SVG 1.1 §14.2 <pattern> paint servers. This module resolves the model
// (href chain, units, tile lattice, content placement inputs); the tile
// rasterisation lives in graphics.svg.render (it needs the renderer
// machinery), and PatternShader tiles the rasterised result: the
// rasterizer hands the shader the CTM inverse, so sampling runs in user
// space, through patternTransform, into the tile lattice.

struct PatternServer
{
    float X, Y, W, H;      // tile lattice rect & period, in pattern coords
    const(size_t)[] content; // children of the chain element that provides them
    const(Element)[] chain;  // for style inheritance when rasterising
    bool contentBBox;        // patternContentUnits="objectBoundingBox"
    string viewBoxRaw;       // raw viewBox string (null = none)
    string parRaw;           // raw preserveAspectRatio (null = default)
    Matrix pt;               // patternTransform (identity when absent)
}

/// Resolve `id` into pattern geometry. Returns false - the caller then
/// treats the paint as a server error (documented fallback or none) - on
/// an unknown id, an href chain leaving <pattern>, an unparseable
/// patternTransform, objectBoundingBox units against a degenerate bbox
/// (§7.11's supplemental mapping, same rule as for gradients), or a
/// zero/negative tile size without a viewBox.
///
/// A zero/negative tile size *with* a viewBox resolves successfully:
/// patternPaint then paints an empty area (no fallback). The W3C
/// references split the two: pservers-pattern-03-f's viewBox-less empty
/// patterns take their `lime` fallbacks ("empty patterns are not
/// rendered, and the fallback colour is used instead"), while
/// pservers-pattern-09-f's zero-sized `pattern3`, which carries a
/// viewBox, leaves its rectangle blank. SE §14.1.1 lists them all as
/// errors; the era UAs measured here did not.
bool patternResolve(ref const(Document) doc, string id, in FRect bbox,
    float vpW, float vpH, out PatternServer ps)
{
    immutable idx = doc.byId(id);
    if (idx == Document.unknown)
        return false;

    bool invalid;
    static const string[] patternKinds = ["pattern"];
    auto chain = hrefChain(doc, idx, invalid, patternKinds);
    if (invalid || chain.empty || chain[0].name != "pattern")
        return false;

    // patternUnits defaults to objectBoundingBox (§14.2).
    bool userSpace;
    if (auto u = strAttr(chain, "patternUnits"))
        userSpace = toLower(u) == "userspaceonuse";

    if (!userSpace && (bbox.width <= 0 || bbox.height <= 0))
        return false; // degenerate objectBoundingBox mapping

    // Percentages run against the viewport in userSpaceOnUse, against the
    // bbox in objectBoundingBox units.
    immutable xs = userSpace ? vpW : bbox.width;
    immutable ys = userSpace ? vpH : bbox.height;
    auto x = attr(chain, "x", 0.0f, xs);
    auto y = attr(chain, "y", 0.0f, ys);
    auto w = attr(chain, "width", 0.0f, xs);
    auto h = attr(chain, "height", 0.0f, ys);
    if (!userSpace) // bbox fractions -> the shape's user space (§7.11)
    {
        x = bbox.left + x * bbox.width;
        y = bbox.top + y * bbox.height;
        w *= bbox.width;
        h *= bbox.height;
    }
    ps.X = x; ps.Y = y; ps.W = w; ps.H = h;

    if (auto cu = strAttr(chain, "patternContentUnits"))
        ps.contentBBox = toLower(cu) == "objectboundingbox";

    ps.viewBoxRaw = strAttr(chain, "viewBox");
    ps.parRaw = strAttr(chain, "preserveAspectRatio");

    if (w <= 0 || h <= 0) // the "invisible" split, see @return above
        return ps.viewBoxRaw !is null;

    ps.pt.reset();
    if (auto t = strAttr(chain, "patternTransform"))
    {
        try
            transformSVG(ps.pt, t);
        catch (Exception)
            return false; // malformed transform list: server in error
    }

    // Content: the pattern's own children, or - if it defines none - the
    // nearest href ancestor that does.
    ps.chain = chain;
    foreach (ref e; chain)
        if (e.children.length)
        {
            ps.content = e.children;
            break;
        }
    return true;
}

unittest
{
    import graphics.svg.parser : parseSVG;

    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">
        <pattern id="p1" width="0.5" height="0.5"><rect/></pattern>
        <pattern id="p2" patternUnits="userSpaceOnUse" x="5" width="20" height="10"/>
        <pattern id="p3" xlink:href="#p2" y="7"/>
        <pattern id="zero" width="0" height="10"/>
        <pattern id="zerovb" patternUnits="userSpaceOnUse" width="0" height="10" viewBox="0 0 10 10"/>
        <rect id="notpat"/>
        <pattern id="wrong" xlink:href="#notpat"/>
        <pattern id="dangling" patternUnits="userSpaceOnUse" xlink:href="#missing" width="10" height="10"/>
        <pattern id="cyc1" xlink:href="#cyc2" width="4" height="4"/>
        <pattern id="cyc2" xlink:href="#cyc1" width="4" height="4"/>
        </svg>`);

    PatternServer ps;
    immutable FRect bbox = FRect(10, 10, 50, 30); // left, top, right, bottom

    // patternUnits defaults to objectBoundingBox: fractions of the shape
    // bbox, offset from its corner.
    assert(patternResolve(doc, "p1", bbox, 100, 100, ps));
    assert(ps.X == 10 && ps.Y == 10 && ps.W == 20 && ps.H == 10);
    assert(ps.content.length == 1); // own children

    // A degenerate bbox with bbox units is a server error (§7.11).
    assert(!patternResolve(doc, "p1", FRect(5, 5, 5, 25), 100, 100, ps));

    // userSpaceOnUse: literal lengths.
    assert(patternResolve(doc, "p2", bbox, 100, 100, ps));
    assert(ps.X == 5 && ps.Y == 0 && ps.W == 20 && ps.H == 10);
    assert(ps.content.length == 0); // defines no children

    // href inheritance: unset attributes come from the chain; content and
    // the unit kind ride along too (p3 has no patternUnits of its own, so
    // it inherits userSpaceOnUse from p2).
    assert(patternResolve(doc, "p3", bbox, 100, 100, ps));
    assert(ps.X == 5 && ps.Y == 7 && ps.W == 20 && ps.H == 10);

    // Zero tile size, no viewBox: server error - the fallback takes over
    // (pservers-pattern-03-f's eight green squares).
    assert(!patternResolve(doc, "zero", bbox, 100, 100, ps));

    // ...but a zero tile carrying a viewBox resolves: a valid server
    // painting no area, fallback untouched (pservers-pattern-09-f #3).
    assert(patternResolve(doc, "zerovb", bbox, 100, 100, ps));
    assert(ps.W == 0 && ps.H == 10);

    // href leaving <pattern> invalidates the whole server.
    assert(!patternResolve(doc, "wrong", bbox, 100, 100, ps));
    assert(!patternResolve(doc, "cyc1", bbox, 100, 100, ps));

    // A dangling href only ends the chain (pservers-pattern-07-f/08-f:
    // "an invalid xlink:href has no effect on the pattern element").
    assert(patternResolve(doc, "dangling", bbox, 100, 100, ps));
    assert(ps.W == 10 && ps.H == 10);

    // Unknown ids are plain reference errors.
    assert(!patternResolve(doc, "nope", bbox, 100, 100, ps));

    // Percentages run against the viewport in userSpaceOnUse.
    auto pct = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        width="100" height="100">
        <pattern id="q" patternUnits="userSpaceOnUse" width="50%" height="25%"/>
        </svg>`);
    assert(patternResolve(pct, "q", bbox, 100, 100, ps));
    assert(ps.W == 50 && ps.H == 25);
}

final class PatternShader : MappingShader
{
    this(const PMColor[][] rows, float X, float Y, float W, float H,
        float scale, in Matrix invPT)
    {
        assert(rows.length && rows[0].length);
        this.rows = rows;
        this.X = X; this.Y = Y; this.W = W; this.H = H;
        this.scale = scale;
        this.invPT = invPT;
    }

    override @property bool opaque() const
    {
        return false; // tile edges are antialiased at worst, and content
                      // may itself be translucent or clipped
    }

    override void getRange(float x, float y, PMColor[] data)
    {
        return mapLine!colorAt(this, x, y, data);
    }

    // mapPt lands in user space; patternTransform then maps the pattern
    // coord system onto user space, so its inverse reaches pattern space.
    // There the lattice repeats every (W, H) from (X, Y); tile bitmaps
    // cover [0, W)x[0, H) at `scale` px per pattern unit.
    static PMColor colorAt(PatternShader pthis, in FPoint dev)
    {
        immutable p = pthis.invPT * pthis.mapPt(dev);

        auto tx = p.x - pthis.X;
        auto ty = p.y - pthis.Y;
        tx -= floor(tx / pthis.W) * pthis.W;
        ty -= floor(ty / pthis.H) * pthis.H;

        immutable ix = min(to!int(tx * pthis.scale),
            cast(int) pthis.rows[0].length - 1);
        immutable iy = min(to!int(ty * pthis.scale),
            cast(int) pthis.rows.length - 1);
        return pthis.rows[iy][ix];
    }

    const PMColor[][] rows;
    float X, Y, W, H, scale;
    Matrix invPT;
}
