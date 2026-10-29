module graphics.svg.smil;

import graphics.svg.parser;
import std.algorithm : canFind, max, min;
import std.array : replace, split;
import std.conv : ConvException, to;
import std.math : atan2, floor, isFinite, PI;
import std.range : empty;
import std.string : indexOf, strip;

// SMIL animation core subset (SVG 1.1 §19.2.12-19.2.16), evaluated as a
// static end state: the renderer paints the document as though the
// timeline had run to completion (t = +infinity). Every
// animate/animateColor/animateTransform/set then resolves to:
//
//   - an ended run with fill="remove" contributes nothing (base value);
//   - an ended run with fill="freeze" keeps the end value of its run
//     (§19.2.2: at the simple-duration boundary the *closed* end wins,
//     so repeatCount="2" freezes at f = 1 of the second iteration);
//   - dur="indefinite" (or indefinite repeats, no numeric end) is still
//     active at t=+inf: a <set> holds its `to`, an <animate> sits at its
//     initial value (from / values[0]);
//   - max=/min= clamp the active duration (SMIL smil20 §2.6, mirrored in
//     every animate element's attributes): numeric `max` cuts it short,
//     numeric `min` stretches it;
//   - a begin list with no resolvable time (events, "indefinite",
//     syncbase references that do not resolve) never starts. Syncbase
//     tokens resolve "id.begin", "id.end", "id.repeat(n)" plus optional
//     clock offset against animations already seen in the document;
//     event tokens (click, accessKey) never fire in a static render, so
//     the run that waits on them for its *end* stays active at +inf.
//
// additive="sum" and accumulate="sum" (§19.2.5-19.2.6) do their numeric
// arithmetic (accumulation adds each complete iteration's end value:
// k*V(1) + V(f)); transform targets get the transform-list analogues
// (post-multiplication: base " " anim, k copies of the iteration value).
// String targets (visibility, fill, d...) simply take the end value.
// Where several animations share one target attribute, the sandwich
// model (§19.2.8) puts the later-starting one on top - at t=+inf that is
// the largest numeric begin, document order breaking ties - so effects
// are applied in that order and additive runs compose.
//
// animateMotion's frozen position rides on the target as a supplemental
// translate applied *before* (to the left of) the element's transform
// chain - the order animate-elem-53-t's guide rects can prove
// (SVG 1.1 §9.5); rotate="auto"/"auto-reverse" turn along the path's
// end tangent (animate-elem-08-t). keyPoints and mpath are not tracked.
// Reference and image documents stay static: applySMILEndStates runs on
// the CLI's document only (SVG images have no timeline -
// struct-image-17-b's <set> red never applies).

private enum Kind { str, num, transform, motion }

private struct Effect
{
    size_t target;
    string attr;
    Kind kind;
    string text;    // str: end value; transform: animation value
    double num;     // num: end value, or the delta when addToBase
    bool addToBase; // num: sum onto the underlying attr; transform: post-multiply
    double begin;   // sandwich priority (§19.2.8)
    size_t order;   // tie-break: document order
}

/// Rewrite target attributes in place to their timeline end values.
void applySMILEndStates(ref Document doc)
{
    Effect[] effs, motions;
    Sync ctx;
    size_t order;

    void scan(size_t idx, size_t parent)
    {
        auto n = doc.nodes[idx];
        if (canFind(["animate", "animateColor", "animateTransform",
                     "animateMotion", "set"], n.name))
        {
            Effect e;
            if (!effect(n, parent, doc, order++, ctx, e))
                return;
            (e.kind == Kind.motion ? motions : effs) ~= e;
            return; // animation elements have no renderable children
        }
        foreach (ch; n.children)
            scan(ch, idx);
    }
    scan(0, Document.unknown);
    if (!effs.length && !motions.length)
        return;

    // insertion sort by (begin, document order): small n, and `order`
    // is unique, so the sandwich sequence is a total order.
    void sortEffs(ref Effect[] arr)
    {
        foreach (i; 1 .. arr.length)
        {
            auto e = arr[i];
            size_t j = i;
            while (j != 0 && (arr[j - 1].begin > e.begin
                || (arr[j - 1].begin == e.begin && arr[j - 1].order > e.order)))
            {
                arr[j] = arr[j - 1];
                --j;
            }
            arr[j] = e;
        }
    }
    sortEffs(effs);
    sortEffs(motions);

    // The arena was built mutable and sealed by the parser; the animation
    // target values are just the next stage of document preparation.
    auto nodes = cast(Element[]) doc.nodes;
    void applyTo(ref const Effect e)
    {
        ref string[string] attrs = nodes[e.target].attrs;
        if (e.kind == Kind.transform)
        {
            auto base = attrs.get("transform", "");
            attrs["transform"] = e.addToBase && base.length
                ? base ~ " " ~ e.text : e.text;
        }
        else if (e.kind == Kind.motion)
        {
            auto base = attrs.get("transform", "");
            attrs["transform"] = base.length
                ? e.text ~ " " ~ base : e.text;
        }
        else if (e.kind == Kind.num)
        {
            if (e.addToBase)
            {
                double und;
                attrs[e.attr] = toDouble(attrs.get(e.attr, ""), und)
                    ? to!string(und + e.num) : to!string(e.num);
            }
            else
                attrs[e.attr] = to!string(e.num);
        }
        else
            attrs[e.attr] = e.text;
    }
    // the transform-attribute chain first, then animateMotion's
    // supplemental translate on top of whatever that produced
    foreach (ref e; effs)
        applyTo(e);
    foreach (ref e; motions)
        applyTo(e);
}

// ------------------------------------------------------------------ parse

// Strictly numeric clock-ish string: no "indefinite", no events, no
// syncbase, no NaN/hex - those all fail toDouble and mark a timing token
// as "not a wall-clock time".
private bool toDouble(string s, ref double v)
{
    if (s.empty)
        return false;
    foreach (c; s)
        if (!(c >= '0' && c <= '9') && !canFind("+-.eE", c))
            return false;
    try
        v = to!double(s);
    catch (ConvException)
        return false;
    return v.isFinite;
}

// One SMIL clock value ("9s", "0.5", "120ms", "2min"); false for
// indefinite/event/syncbase tokens (§5.2).
private bool clock(string t, ref double secs)
{
    t = t.strip;
    double scale = 1;
    if (t.length >= 3 && t[$ - 3 .. $] == "min")
        scale = 60, t = t[0 .. $ - 3];
    else if (t.length >= 2 && t[$ - 2 .. $] == "ms")
        scale = 0.001, t = t[0 .. $ - 2];
    else if (t.length >= 1 && (t[$ - 1] == 's' || t[$ - 1] == 'h'))
    {
        if (t[$ - 1] == 'h')
            scale = 3600;
        t = t[0 .. $ - 1];
    }
    if (!toDouble(t, secs))
        return false;
    secs *= scale;
    return true;
}

// Resolved wall-clock timing of the animations seen so far, so that
// later syncbase tokens can refer to them (§19.2.10, SMIL smil20 §10.3).
private struct Sync
{
    double[string] beginOf, endOf, durOf;
}

// "secondSet.begin + 2s", "repeatBase.repeat(2)", "endBase.end-2s":
// resolves against an animation id already collected this pass; event
// tokens ("x.click", "accessKey(a)", "wallclock(...)") and unknown or
// forward ids are not wall-clock times and resolve to false.
private bool syncbase(string tok, ref Sync ctx, ref double secs)
{
    tok = tok.strip;
    immutable dot = indexOf(tok, '.');
    if (dot < 1)
        return false;
    auto id = tok[0 .. dot].strip;
    auto evt = tok[dot + 1 .. $];

    size_t e; // event word: up to '(' or a signed offset
    while (e < evt.length
        && (evt[e] == '_' || (evt[e] >= 'a' && evt[e] <= 'z')
            || (evt[e] >= 'A' && evt[e] <= 'Z')
            || (evt[e] >= '0' && evt[e] <= '9')))
        ++e;
    auto name = evt[0 .. e];
    auto rest = evt[e .. $];

    double n = 0;
    if (name == "repeat")
    {
        if (rest.length < 2 || rest[0] != '(')
            return false;
        immutable close = indexOf(rest, ')');
        if (close < 1 || !clock(rest[1 .. close], n))
            return false;
        rest = rest[close + 1 .. $];
    }
    double ofs = 0;
    auto off = rest.replace(" ", "");
    if (!off.empty && !clock(off, ofs))
        return false;

    if (name == "begin" || name == "end" || name == "repeat")
    {
        auto b = id in ctx.beginOf;
        if (b is null)
            return false;
        if (name == "repeat")
        {
            auto d = id in ctx.durOf;
            if (d is null || !isFinite(*d))
                return false;
            secs = *b + n * *d + ofs;
        }
        else
        {
            auto t = name == "begin" ? b : id in ctx.endOf;
            if (t is null || !isFinite(*t))
                return false;
            secs = *t + ofs;
        }
        return true;
    }
    return false;
}

// The wall-clock members of a ';'-separated begin/end list: plain
// clock values plus any syncbase tokens that resolve (§5.2).
private double[] clocks(string s, ref Sync ctx)
{
    double[] res;
    foreach (tok; s.split(";"))
    {
        double v;
        if (clock(tok, v) || syncbase(tok, ctx, v))
            res ~= v;
    }
    return res;
}

private string[] segs(string s)
{
    string[] res;
    foreach (p; s.split(";"))
        res ~= p.strip;
    return res;
}

// transform parameters ("1,1", "-10 5"): all doubles or null.
private double[] nums(string s)
{
    double[] res;
    foreach (t; s.replace(",", " ").split)
    {
        double v;
        if (!toDouble(t, v))
            return null;
        res ~= v;
    }
    return res;
}

private double minOf(double[] xs)
{
    double m = xs[0];
    foreach (x; xs[1 .. $])
        if (x < m)
            m = x;
    return m;
}

// ------------------------------------------------------------ interpolate

// Value at simple fraction f (§19.2.2). f=1 (the usual case here) picks
// the last entry even when keyTimes stop short (discrete tests such as
// animate-elem-14-t use keyTimes="0;.2;.4;.6"); mid-run fractions only
// arise from fractional repeats and end= cut-offs, where spline/paced
// degenerates to linear without changing the frozen endpoint.
private double valueAt(in double[] v, in double[] kt, bool discrete, double f)
{
    if (v.length == 1)
        return v[0];
    if (discrete)
    {
        size_t i = 0;
        if (kt is null)
            i = cast(size_t) floor(f * v.length);
        else
            foreach (j, t; kt)
                if (f >= t)
                    i = j;
        return v[min(i, v.length - 1)];
    }
    size_t i;
    double t;
    if (kt is null)
    {
        t = f * (v.length - 1);
        i = cast(size_t) t;
        if (i >= v.length - 1)
            return v[$ - 1];
        t -= i;
    }
    else
    {
        size_t j = 0;
        while (j < kt.length - 1 && kt[j + 1] < f)
            ++j;
        if (f >= kt[$ - 1] && kt[$ - 1] <= 1.0)
            return v[$ - 1];
        i = j;
        immutable span = kt[j + 1] - kt[j];
        t = span > 0 ? (f - kt[j]) / span : 1.0;
    }
    return v[i] + (v[i + 1] - v[i]) * min(max(t, 0.0), 1.0);
}

// The parameter list of the transform animation at f: the same
// bracketing, but whole lists.
private double[] paramsAt(in string[] vv, double f)
{
    if (f <= 0)
        return nums(vv[0]).length ? nums(vv[0]) : null;
    if (f >= 1)
        return nums(vv[$ - 1]);
    immutable i = min(cast(size_t) (f * (vv.length - 1)), vv.length - 1);
    return nums(vv[i]);
}

// ---------------------------------------------------------------- collect

private bool effect(in Element n, size_t parent, ref Document doc,
                    size_t order, ref Sync ctx, ref Effect res)
{
    auto a = n.attrs;
    auto attr = n.name == "animateMotion"
        ? "transform" // animateMotion implicitly targets transform
        : a.get("attributeName", "");
    if (attr.empty || (attr.length > 5 && attr[0 .. 5] == "xlink"))
        return false;

    // Default target is the parent element; an href retargets to the
    // id it names (§19.2.0: href identifies the target, not the host).
    size_t target = parent;
    if (auto hp = "xlink:href" in a)
    {
        const href = strip(*hp);
        target = href.length && href[0] == '#'
            ? doc.byId(href[1 .. $]) : Document.unknown;
    }
    if (target == Document.unknown || target == 0)
        return false;

    // Timing. A begin list with no resolvable time never starts; the
    // earliest resolvable entry is the sandwich-priority begin.
    double begin = 0;
    if (auto bp = "begin" in a)
    {
        auto bs = clocks(*bp, ctx);
        if (!bs.length)
            return false;
        begin = minOf(bs);
    }
    double dur = double.infinity;
    if (auto dp = "dur" in a)
    {
        double d;
        if (clock(*dp, d))
            dur = d;
    }
    bool endless = !dur.isFinite, repIndef = false;
    double reps = 1;
    if (auto rp = "repeatCount" in a)
    {
        double r;
        if (!clock(*rp, r))
            endless = true, repIndef = true; // indefinite
        else if (r <= 0)
            return false;
        else
            reps = r;
    }
    if (auto qp = "repeatDur" in a)
    {
        double q;
        if (!clock(*qp, q))
            endless = true, repIndef = true;
        else if (dur.isFinite)
            reps = q / dur;
    }
    double endAt = double.infinity;
    if (auto ep = "end" in a)
    {
        auto es = clocks(*ep, ctx);
        if (es.length)
            endAt = minOf(es);
    }
    // max/min bound the whole active duration (SMIL smil20 §2.6).
    double maxv = double.infinity, minv = 0;
    if (auto xp = "max" in a)
    {
        double x;
        if (clock(*xp, x))
            maxv = x;
    }
    if (auto np = "min" in a)
    {
        double x;
        if (clock(*np, x))
            minv = x;
    }
    if (maxv.isFinite && endAt > begin + maxv)
        endAt = begin + maxv;

    // Publish this run's clock so later syncbase tokens can resolve it.
    if (auto ip = "id" in a)
    {
        double natEnd = endAt;
        if (dur.isFinite && !repIndef && begin + reps * dur < natEnd)
            natEnd = begin + reps * dur;
        ctx.beginOf[*ip] = begin;
        ctx.endOf[*ip] = natEnd;
        ctx.durOf[*ip] = dur;
    }
    if (endAt <= begin)
        return false; // ended (or cut) before it started

    // Branch A: still running at t=+inf (fill plays no role; an active
    // animation always shows). Branch B: run over; only fill="freeze"
    // keeps the end value.
    double k = 0;   // complete iterations before the frozen instant
    double f = 0;   // fraction of the simple duration at that instant
    if (endless && !endAt.isFinite)
    {
        // k=0, f=0: the initial value
    }
    else
    {
        if (a.get("fill", "") != "freeze")
            return false;
        if (!dur.isFinite)
            k = 0, f = 0; // indefinite dur cut by end= : still at the start
        else
        {
            immutable span = min(endAt - begin,
                max((repIndef ? double.infinity : reps) * dur, minv));
            if (span <= 0)
                return false;
            k = max(floor((span - 1e-9) / dur), 0.0);
            f = (span - k * dur) / dur;
            if (f <= 0)
                f = 1; // exact multiple: frozen at the end of an iteration
        }
    }

    res.target = target;
    res.attr = attr;
    res.begin = begin;
    res.order = order;

    auto vs = "values" in a ? segs(*("values" in a)) : null;
    if (vs !is null && !vs.length)
        return false;
    auto src = a.get("from", "");
    auto dst = a.get("to", "");
    auto dlt = a.get("by", "");

    if (n.name == "set")
    {
        const held = vs is null ? (dst.length ? dst : src) : vs[$ - 1];
        if (held.empty)
            return false;
        res.kind = Kind.str;
        res.text = held;
        return true;
    }

    if (n.name == "animateTransform")
    {
        immutable ty = a.get("type", "");
        if (ty.empty)
            return false;
        auto tp = vs !is null ? null : nums(dst);
        auto fp = vs !is null ? null : nums(src);
        auto bp = vs !is null ? null : nums(dlt);

        auto str = (in double[] p) => p is null || p.length == 0
            ? "" : ty ~ "(" ~ joinP(p) ~ ")";
        double[] at; // animation parameters at f
        if (vs !is null)
        {
            at = paramsAt(vs, f);
            if (at is null)
                return false;
        }
        else if (bp !is null && fp is null && tp is null)
            at = scale(bp, f); // by-only: f scaled from the identity
        else
        {
            if (fp is null && tp is null)
                return false;
            if (fp is null)
            {
                if (f <= 0)
                    return false; // to-only at f=0: the underlying value
                at = tp; // mid-run without a `from` is rare; take `to`
            }
            else if (tp is null)
            {
                if (f >= 1)
                    return false; // from-only ends at the underlying value
                at = fp;
            }
            else
                at = lerpP(fp, tp, min(max(f, 0.0), 1.0));
            if (bp !is null && f >= 1 && fp !is null && tp !is null)
                at = sumP(fp, bp); // from+by: end is from offset by by
        }
        if (at is null)
            return false;

        string text = str(at);
        if (a.get("accumulate", "none") == "sum")
        {
            // each complete iteration post-multiplies its end value
            double[] fin = vs !is null ? paramsAt(vs, 1)
                       : bp !is null && fp is null && tp is null ? bp
                       : tp !is null ? tp : sumP(fp, bp);
            while (k-- > 0)
                text = str(fin) ~ " " ~ text;
        }
        res.kind = Kind.transform;
        res.text = text;
        res.addToBase = a.get("additive", "replace") == "sum"
            || (bp !is null && fp is null && tp is null && vs is null);
        return true;
    }

    if (n.name == "animateMotion")
    {
        // the frozen position is a supplemental translate, spun by
        // rotate="auto"/"auto-reverse" along the path's end tangent;
        // keyPoints and mpath are not tracked.
        double[] at;
        double deg;
        if (vs !is null)
            at = nums(vs[f >= 1 ? $ - 1 : 0]);
        else
        {
            auto pp = a.get("path", "");
            auto fp = nums(src), tp = nums(dst), bp = nums(dlt);
            if (pp.length)
            {
                double px, py;
                if (!pathEnd(pp, px, py, deg))
                    return false;
                at = [px, py]; // partial path stops are not tracked
            }
            else if (fp !is null && tp !is null)
                at = lerpP(fp, tp, min(max(f, 0.0), 1.0));
            else if (tp !is null)
                at = f <= 0 ? null : tp; // to-only at f=0: no offset
            else if (fp !is null)
                at = f >= 1 ? null : fp; // from-only ends back at origin
            else if (bp !is null)
                at = scale(bp, f); // by-only rides from the origin
            else
                return false;
        }
        if (at is null || at.length < 2)
            return false;
        immutable rot = a.get("rotate", "");
        res.text = "translate(" ~ joinP(at[0 .. 2]) ~ ")";
        if (rot == "auto" || rot == "auto-reverse")
            res.text ~= " rotate("
                ~ to!string(deg + (rot == "auto-reverse" ? 180.0 : 0.0)) ~ ")";
        else if (at[0] == 0 && at[1] == 0)
            return false; // no offset, no turn: identity
        res.kind = Kind.motion;
        return true;
    }

    // animate / animateColor: numeric kinds do the arithmetic, string
    // kinds take the end value verbatim.
    enum NUM = 0, STR = 1;
    int cls = STR;
    double[] vnum;
    double fromv, tov, byv;
    if (vs !is null)
    {
        cls = NUM;
        foreach (s; vs)
        {
            double x;
            if (!toDouble(s, x))
            {
                cls = STR;
                break;
            }
            vnum ~= x;
        }
    }
    else
    {
        bool okF = src.empty || toDouble(src, fromv);
        bool okT = dst.empty || toDouble(dst, tov);
        bool okB = dlt.empty || toDouble(dlt, byv);
        cls = okF && okT && okB ? NUM : STR;
    }

    if (cls == STR)
    {
        string text;
        if (vs !is null)
            text = f <= 0 ? vs[0] : vs[$ - 1];
        else if (dst.length)
            text = src.length || f >= 1 ? dst : ""; // src->dst ends at `dst`
        else if (src.length)
            text = f <= 0 ? src : ""; // from-only ends at the underlying
        else
            return false; // by/string makes no sense
        if (text.empty)
            return false;
        res.kind = Kind.str;
        res.text = text;
        return true;
    }

    // numeric: V(f) plus accumulation, then additive placement.
    bool hasV = vnum.length != 0;
    bool hasF = !src.empty, hasT = !dst.empty, hasB = !dlt.empty;
    if (!hasV && !hasF && !hasT && !hasB)
        return false;
    double V1, Vf;
    bool toBase = a.get("additive", "replace") == "sum";
    if (hasV)
    {
        double[] kt;
        if (auto kp = "keyTimes" in a)
        {
            bool ok = true;
            foreach (s; segs(*kp))
            {
                double x;
                if (!toDouble(s, x))
                {
                    ok = false;
                    break;
                }
                kt ~= x;
            }
            if (!ok || kt.length != vnum.length)
                kt = null;
        }
        immutable disc = a.get("calcMode", "") == "discrete";
        V1 = valueAt(vnum, kt, disc, 1.0);
        Vf = valueAt(vnum, kt, disc, f);
    }
    else if (hasB && !hasF && !hasT)
    {
        // by-only: the animation function rides on the underlying value
        // (§19.2.5); accumulate repeats the full by each iteration.
        res.kind = Kind.num;
        res.addToBase = true;
        res.num = a.get("accumulate", "none") == "sum"
            ? (k + f) * byv : f * byv;
        return res.num != 0;
    }
    else if (hasT && !hasF)
    {
        if (f <= 0)
            return false; // to-only at f=0: the underlying value
        V1 = tov + (hasB ? byv : 0.0);
        Vf = tov + (hasB ? f * byv : 0.0);
    }
    else if (hasF && !hasT)
    {
        if (f >= 1 && !hasB)
            return false; // from-only ends at the underlying value
        V1 = fromv + (hasB ? byv : 0.0);
        Vf = fromv + (hasB ? f * byv : 0.0);
    }
    else
    {
        // from and to together: `by` is ignored (§19.2.3-19.2.4).
        V1 = tov;
        Vf = valueAt([fromv, tov], null, false, f);
    }
    res.kind = Kind.num;
    res.addToBase = toBase;
    res.num = a.get("accumulate", "none") == "sum" ? k * V1 + Vf : Vf;
    return true;
}

// ------------------------------------------------- transform param lists

private string joinP(in double[] p)
{
    string s;
    foreach (i, x; p)
        s ~= (i ? "," : "") ~ to!string(x);
    return s;
}

private double[] lerpP(in double[] a, in double[] b, double t)
{
    double[] r;
    if (a.length != b.length)
    {
        foreach (x; b)
            r ~= x;
        return r;
    }
    foreach (i; 0 .. a.length)
        r ~= a[i] + (b[i] - a[i]) * t;
    return r;
}

private double[] sumP(in double[] a, in double[] b)
{
    double[] r;
    if (a.length != b.length)
    {
        foreach (x; b)
            r ~= x;
        return r;
    }
    foreach (i; 0 .. a.length)
        r ~= a[i] + b[i];
    return r;
}

private double[] scale(in double[] a, double t)
{
    double[] r;
    foreach (x; a)
        r ~= x * t;
    return r;
}

// ---------------------------------------------------------------- path

// The last current point and final tangent of 'path' data
// (animateMotion's position and rotate="auto" heading): track only the
// current point through the command list; each command's endpoint
// parameters are its final pair (or single H/V value), and the tangent
// at an endpoint is C: P3-P2, Q/S: endpoint-control, else: the chord.
private bool pathEnd(string d, ref double x, ref double y, ref double deg)
{
    enum segLen = (char c) => c == 'A' || c == 'a' ? 7
        : c == 'C' || c == 'c' ? 6
        : c == 'S' || c == 's' || c == 'Q' || c == 'q' ? 4
        : c == 'H' || c == 'V' || c == 'h' || c == 'v' ? 1 : 2;
    enum control = (char c) => c == 'C' || c == 'c' ? 2
        : c == 'S' || c == 's' || c == 'Q' || c == 'q' ? 0 : size_t.max;

    bool rel, have, first = true;
    char cmd;
    size_t p;
    double sx = 0, sy = 0, dx = 0, dy = 0, cx = 0, cy = 0;
    x = y = deg = 0; // the initial current point

    void finish()
    {
        if (dx || dy)
            deg = atan2(dy, dx) * 180.0 / PI;
    }

    size_t i;
    while (i < d.length)
    {
        immutable c = d[i];
        if (canFind("MmZzLlHhVvCcSsQqTtAa", c))
        {
            cmd = c, rel = c >= 'a', p = 0;
            dx = dy = 0;
            if (c == 'Z' || c == 'z')
            {
                if (have)
                    dx = sx - x, dy = sy - y, finish();
                x = sx, y = sy, have = true;
            }
            ++i;
            continue;
        }
        if (c == ',' || c == ' ' || (c >= '\t' && c <= '\r'))
        {
            ++i;
            continue;
        }
        // one number: sign, digits/dot, optional exponent
        size_t j = i;
        if (d[j] == '+' || d[j] == '-')
            ++j;
        while (j < d.length && (d[j] >= '0' && d[j] <= '9' || d[j] == '.'))
            ++j;
        if (j < d.length && (d[j] == 'e' || d[j] == 'E'))
        {
            ++j;
            if (j < d.length && (d[j] == '+' || d[j] == '-'))
                ++j;
            while (j < d.length && d[j] >= '0' && d[j] <= '9')
                ++j;
        }
        double v;
        if (!toDouble(d[i .. j], v))
            return false;
        i = j;
        if (cmd == 0 || cmd == 'Z' || cmd == 'z')
            continue;

        immutable len = segLen(cmd);
        immutable ctl = control(cmd);
        if (ctl != size_t.max && (p == ctl || p == ctl + 1))
        {
            if (p == ctl)
                cx = v;
            else
                cy = v;
        }
        if (len == 1)
        {
            if (cmd == 'H' || cmd == 'h')
            {
                cx = rel ? x + v : v;
                dx = cx - x;
                x = cx;
            }
            else
            {
                cy = rel ? y + v : v;
                dy = cy - y;
                y = cy;
            }
            have = true;
            finish();
        }
        else if (p == len - 2) // endpoint x
        {
            immutable nx = rel ? x + v : v;
            dx = nx - (p == ctl + 2 ? cx : x); // C/Q/S: endpoint - control
            x = nx;
            have = true;
        }
        else if (p == len - 1) // endpoint y; completes the pair
        {
            immutable ny = rel ? y + v : v;
            dy = ny - (p == ctl + 3 ? cy : y);
            y = ny;
            finish();
            if (cmd == 'M' || cmd == 'm')
            {
                if (first)
                    sx = x, sy = y, first = false;
                cmd = rel ? 'l' : 'L'; // extra pairs are implicit lines
            }
        }
        p = p + 1 == len ? 0 : p + 1;
    }
    return have;
}

// ---------------------------------------------------------------- tests

private Document animDoc(string body)
{
    return parseSVG(`<svg xmlns="http://www.w3.org/2000/svg" width="100" `
        ~ `height="100">` ~ body ~ `</svg>`);
}

unittest
{
    // freeze keeps the run's end value; fill="remove" (the default for
    // an ended run) keeps the base.
    auto doc = animDoc(`<rect id="r" width="10">
        <animate attributeName="width" from="10" to="40" dur="2s"
            fill="freeze"/></rect>
        <rect id="s" width="10">
        <animate attributeName="width" from="10" to="40" dur="2s"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("r")].attrs["width"] == "40");
    assert(doc.nodes[doc.byId("s")].attrs["width"] == "10");
}

unittest
{
    // from+by and by alone resolve like animate-elem-13-t: 30+270 = 300.
    auto doc = animDoc(`<rect id="a" width="30">
        <animate attributeName="width" from="30" by="270" begin="2s"
            dur="3s" fill="freeze"/></rect>
        <rect id="b" width="30">
        <animate attributeName="width" by="270" begin="2s" dur="3s"
            fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("a")].attrs["width"] == "300");
    assert(doc.nodes[doc.byId("b")].attrs["width"] == "300");
}

unittest
{
    // discrete values whose keyTimes stop short still freeze on the
    // last value (animate-elem-14-t).
    auto doc = animDoc(`<rect id="w" width="10">
        <animate attributeName="width" calcMode="discrete"
            values="300;255;180;30" keyTimes="0;.2;.4;.6" begin="0s"
            dur="10s" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("w")].attrs["width"] == "30");
}

unittest
{
    // accumulate="sum" adds each complete iteration's end value:
    // repeatCount="2" with from=200 to=20 freezes at 2*20 = 40, and
    // additive="sum" rides that on the base 20 to make 60
    // (animate-elem-02-t).
    auto doc = animDoc(`<rect id="a7" y="20" height="20">
        <animate attributeName="height" calcMode="discrete"
            additive="replace" accumulate="sum" repeatCount="2" from="200"
            to="20" begin="0s" dur="4s" fill="freeze"/></rect>
        <rect id="a8" y="20" height="20">
        <animate attributeName="height" calcMode="discrete"
            additive="sum" accumulate="sum" repeatCount="2" from="200"
            to="20" begin="0s" dur="4s" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("a7")].attrs["height"] == "40");
    assert(doc.nodes[doc.byId("a8")].attrs["height"] == "60");
}

unittest
{
    // animateTransform: additive="sum" post-multiples onto the base and
    // composes through the sandwich; accumulate="sum" repeats the
    // iteration end value (animate-elem-81-t rows 2 and 6).
    auto doc = animDoc(`<rect id="r2" transform="skewX(30)">
        <animateTransform attributeName="transform" type="rotate"
            from="0" to="90" dur="5s" additive="sum" fill="freeze"/>
        <animateTransform attributeName="transform" type="scale"
            from="1,1" to="2,2" dur="5s" additive="sum"
            fill="freeze"/></rect>
        <rect id="r6" transform="skewX(30)">
        <animateTransform attributeName="transform" type="scale"
            from="0,0" to="2,2" dur="2.5s" repeatCount="2"
            accumulate="sum" additive="sum" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("r2")].attrs["transform"]
        == "skewX(30) rotate(90) scale(2,2)");
    assert(doc.nodes[doc.byId("r6")].attrs["transform"]
        == "skewX(30) scale(2,2) scale(2,2)");
}

unittest
{
    // xlink:href on the animation retargets it (animate-elem-27-t).
    auto doc = animDoc(`<rect id="rect1" height="160"/>
        <rect id="host" height="160">
        <animate xlink:href="#rect1" attributeName="height" from="160"
            to="40" begin="3s" dur="3s" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("rect1")].attrs["height"] == "40");
    assert(doc.nodes[doc.byId("host")].attrs["height"] == "160");
}

unittest
{
    // Indefinite runs: a dur="indefinite" set is still active and holds
    // its to; a begin without any wall-clock time never starts.
    auto doc = animDoc(`<rect id="g" fill="black">
        <set attributeName="fill" to="green" begin="1s"
            dur="indefinite"/></rect>
        <rect id="b" fill="black">
        <animate attributeName="fill" from="black" to="blue"
            begin="indefinite" dur="3s" fill="freeze"/></rect>
        <rect id="c" fill="black">
        <animate attributeName="fill" to="blue" dur="indefinite"
            fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("g")].attrs["fill"] == "green");
    assert(doc.nodes[doc.byId("b")].attrs["fill"] == "black");
    assert(doc.nodes[doc.byId("c")].attrs["fill"] == "black",
        "a to-only animate at f=0 is the underlying value");
}

unittest
{
    // Sandwich: among frozen animations on one target attribute the
    // later begin sits on top (animate-elem-31-t); a mid-list wall-clock
    // begin ("0s; syncbase + 1s") still starts at 0s.
    auto doc = animDoc(`<rect id="v" visibility="visible">
        <animate attributeName="visibility" from="hidden" to="visible"
            begin="1s" dur="2s" fill="freeze"/>
        <animate attributeName="visibility" from="visible" to="hidden"
            begin="3s; first.end + 1s" dur="3s" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("v")].attrs["visibility"] == "hidden");
}

unittest
{
    // A later document element starting early must not displace an
    // earlier element's later animation: with two grow/shrink pairs
    // (begins 0,3,0,3) each target must end back at 0
    // (animate-elem-32-t).
    auto doc = animDoc(`<rect id="a" width="60" height="50">
        <animate attributeName="width" from="0" to="25" begin="0" dur="3"
            fill="freeze"/>
        <animate attributeName="width" from="25" to="0" begin="3" dur="3"
            fill="freeze"/></rect>
        <rect id="b" width="25" height="60">
        <animate attributeName="height" from="0" to="50" begin="0" dur="3"
            fill="freeze"/>
        <animate attributeName="height" from="50" to="0" begin="3" dur="3"
            fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("a")].attrs["width"] == "0");
    assert(doc.nodes[doc.byId("b")].attrs["height"] == "0");
}

unittest
{
    // max= cuts even an indefinite run short; with the default
    // fill="remove" the target keeps its base value (animate-elem-66-t).
    auto doc = animDoc(`<rect id="a" x="20">
        <set attributeName="x" to="74" max="5s" dur="indefinite"/></rect>
        <rect id="b" x="30">
        <animate attributeName="x" from="30" to="90" max="5s"
            dur="indefinite" fill="freeze"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("a")].attrs["x"] == "20");
    assert(doc.nodes[doc.byId("b")].attrs["x"] == "30",
        "cut at 5s of an indefinite dur: f is still 0, so still at the start");
}

unittest
{
    // syncbase ends resolve against the wall-clock timing of animations
    // seen earlier in the document (animate-elem-62/63-t); a click
    // never fires in a static render, so that run stays active at +inf.
    auto doc = animDoc(`<g id="h1"><set id="secondSet"
            attributeName="fill" to="#F33" begin="0s" end="2s"
            dur="indefinite"/></g>
        <rect id="r2" fill="black">
        <set attributeName="fill" to="#F33" end="secondSet.begin + 2s"
            dur="indefinite"/></rect>
        <g id="h3"><set id="reps" attributeName="display" to="inline"
            begin="0s" dur="1s" repeatCount="4"/></g>
        <rect id="r3" fill="black">
        <set attributeName="fill" to="#F33" end="reps.repeat(3) + 2s"
            dur="indefinite"/></rect>
        <rect id="rc" fill="black">
        <set attributeName="fill" to="#3F3" end="rc.click"
            dur="indefinite"/></rect>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("r2")].attrs["fill"] == "black",
        "secondSet.begin + 2s = 2s: ended, fill=remove keeps the base");
    assert(doc.nodes[doc.byId("r3")].attrs["fill"] == "black",
        "reps.repeat(3) + 2s = 5s: ended");
    assert(doc.nodes[doc.byId("rc")].attrs["fill"] == "#3F3",
        "the click never fires: still active at +inf");
}

unittest
{
    // frozen animateMotion ends at the last values entry or path
    // endpoint, and rides on the element as a supplemental translate
    // left of the transform chain (animate-elem-24-t and -53-t).
    auto doc = animDoc(`<polygon id="rg" points="0,0 30,0 30,30 0,30">
        <animateMotion values="0,0;0,40;0,120" begin="0" dur="6"
            calcMode="linear" fill="freeze"/>
        <animateTransform attributeName="transform" type="scale" from="1"
            to="1.9428" begin="6" dur="3" fill="freeze"/></polygon>
        <text id="t" transform="rotate(-30)">x
        <animateMotion path="M 0 0 L 50 180" begin="3s" dur="6s"
            fill="freeze"/>
        <animateTransform attributeName="transform" type="rotate"
            from="-30" to="0" begin="3s" dur="6s" fill="freeze"/>
        <animateTransform attributeName="transform" type="scale" from="1"
            to="3" additive="sum" begin="3s" dur="6s"
            fill="freeze"/></text>`);
    applySMILEndStates(doc);
    assert(doc.nodes[doc.byId("rg")].attrs["transform"]
        == "translate(0,120) scale(1.9428)");
    assert(doc.nodes[doc.byId("t")].attrs["transform"]
        == "translate(50,180) rotate(0) scale(3)");
}

unittest
{
    // pathEnd tracks the current point (implicit lineto pairs, relative
    // commands, arcs, H/V, closepath) and the end tangent: C is P3-P2,
    // L is the chord.
    double x, y, deg;
    assert(pathEnd("M 0 0 L 50 180", x, y, deg) && x == 50 && y == 180);
    assert(deg > 70 && deg < 75, "chord (50,180) points steeply down");
    assert(pathEnd("M1,2C3,4,5,6,7,8", x, y, deg) && x == 7 && y == 8);
    assert(deg > 44 && deg < 46, "C tangent P3-P2 = (7-5, 8-6) runs down-right");
    assert(pathEnd("m5 5 l10 -3", x, y, deg) && x == 15 && y == 2);
    assert(pathEnd("M 10 10 L 50 50 Z", x, y, deg) && x == 10 && y == 10);
    assert(pathEnd("M 4 4 A 2 2 0 0 1 8 4 H 2", x, y, deg) && x == 2 && y == 4);
    assert(deg > 179 && deg < 181, "final H 2 runs left");
    assert(pathEnd("M 1 1 H 9 V 5", x, y, deg) && x == 9 && y == 5);
    assert(deg > 89 && deg < 91, "final V 5 runs down");
}

unittest
{
    // rotate="auto" rides along the path tangent at its endpoint,
    // auto-reverse half a turn beyond (animate-elem-08-t: both cars'
    // cubic tangents P3-P2 are (50,50), i.e. 45 degrees).
    auto doc = animDoc(`<text id="a">x
        <animateMotion path="M25,225 C25,175 125,150 175,200"
            rotate="auto" begin="0s" dur="6s" fill="freeze"/></text>
        <text id="b">x
        <animateMotion path="M275,225 C275,175 375,150 425,200"
            rotate="auto-reverse" begin="0s" dur="6s"
            fill="freeze"/></text>`);
    applySMILEndStates(doc);
    immutable tangent = atan2(50.0, 50.0) * 180.0 / PI;
    assert(doc.nodes[doc.byId("a")].attrs["transform"]
        == "translate(175,200) rotate(" ~ to!string(tangent) ~ ")");
    assert(doc.nodes[doc.byId("b")].attrs["transform"]
        == "translate(425,200) rotate(" ~ to!string(tangent + 180.0) ~ ")");
}
