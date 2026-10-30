module graphics.svg.pserver;

import std.algorithm, std.conv, std.range, std.string;
import graphics.svg.parser;

// Shared plumbing for the <defs> paint servers (gradients, patterns, and
// the clipping/masking/markers to come): xlink:href inheritance chains
// and first-found-along-the-chain attribute lookup.

// The element plus the xlink:href chain it leads. An href resolving to
// an element outside `kinds`, or a cycle, invalidates the whole server;
// hrefs between compatible server kinds inherit normally. A dangling
// href merely ends the chain - the element stands on its own definition
// (pservers-pattern-07-f: "an invalid xlink:href has no effect on the
// 'pattern' element"; no gradient test pins the opposite).
const(Element)[] hrefChain(ref const(Document) doc, size_t start,
    ref bool invalid, const string[] kinds)
{
    const(Element)[] chain;
    size_t[] seen;
    auto idx = start;
    while (idx != Document.unknown)
    {
        if (seen.canFind(idx))
        {
            invalid = true;
            break;
        }
        seen ~= idx;
        auto e = doc.nodes[idx];
        chain ~= e;

        auto href = e.attrs.get("href", e.attrs.get("xlink:href", ""));
        if (href.length < 2 || href[0] != '#')
            break; // external documents: unsupported reference
        idx = doc.byId(href[1 .. $]);
        if (idx == Document.unknown)
            break; // dangling href: the chain ends, the element's own
                   // definition stands
        if (!kinds.canFind(doc.nodes[idx].name))
        {
            invalid = true; // the href must lead to a compatible server
            break;
        }
    }
    return chain;
}

// First value found walking own-then-inherited (the href chain).
// Percentages scale by pctScale; the caller passes already-scaled defaults.
// The number type follows the defaults: gradient geometry asks for double.
T attr(T = float)(const(Element)[] chain, string key, T def, T pctScale)
{
    foreach (ref e; chain)
        if (auto p = key in e.attrs)
        {
            string v = strip(*p);
            if (v.empty)
                continue;
            try
            {
                if (v.endsWith("%"))
                    return to!T(v[0 .. $ - 1]) / 100 * pctScale;
                return to!T(v);
            }
            catch (ConvException)
                continue; // malformed value: attribute is ignored
        }
    return def;
}

// Same first-found walk for keyword/string-valued attributes; empty or
// missing counts as unset (caller applies the default).
string strAttr(const(Element)[] chain, string key)
{
    foreach (ref e; chain)
        if (auto p = key in e.attrs)
            if (auto v = lengthened(strip(*p)))
                return v;
    return null;
}

// strip + emptiness guard for the `if (auto v = ...)` idiom.
auto lengthened(string s)
{
    return s.empty ? null : s;
}
