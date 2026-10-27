module graphics.svg.parser;

import std.exception;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser, std.experimental.xml.sax;
import std.experimental.xml.interfaces : isCursor;

// Flatten the attributes of the cursor's current element into a map.
string[string] attrs(CursorType)(ref CursorType cursor) if (isCursor!CursorType)
{
    string[string] res;
    foreach (a; cursor.attributes)
        res[a.name] = a.value;
    return res;
}

/// One node of the parsed document arena (see `parseSVG`).
///
/// Element nodes have a `name`; text nodes (character data *and* CDATA
/// sections, the two ways SVG carries text into `<text>`) have an empty
/// name and carry the raw (not whitespace-normalized) content in `text`.
/// `children` are arena indices, so the tree stays pointer-stable while
/// the arena grows and after it is sealed.
struct Element
{
    string name;         // empty -> text node
    string[string] attrs;
    string text;         // text nodes only
    size_t[] children;   // arena indices, document order
}

/// A parsed SVG document: the sealed node arena plus the `id` registry.
/// Forward references (`<use href>`, gradients, patterns, `clip-path`,
/// `mask`, ...) can point anywhere, forward or backward, so rendering
/// needs the whole document before it starts: the arena is built by
/// `parseSVG`, sealed `immutable` on return, and handed to the renderer,
/// which walks it by index and resolves `id`s through `ids` (indices, so
/// nothing ever refers to a node by address).
struct Document
{
    enum unknown = size_t.max;

    immutable(Element)[] nodes; // arena; nodes[0] is the document pseudo-root
    size_t[string] ids;         // id attribute -> arena index (first occurrence wins)
    size_t root;                // first <svg> element in document order

    /// The arena index of the element carrying `id`, or `unknown`.
    size_t byId(string id) const
    {
        auto p = id in ids;
        return p ? *p : unknown;
    }
}

/// Parse `source` into a `Document`. Tolerates documents without an XML
/// declaration (SVG does not require one); XML errors are reported to the
/// parser's error sink and the best-effort tree is kept, as before.
/// Throws if the document contains no <svg> element.
Document parseSVG(string source)
{
    auto c = source.lexer.parser.cursor((CursorError e) {});
    alias C = typeof(c);

    static struct Builder
    {
        Element[] nodes = [Element.init]; // nodes[0]: the document pseudo-root
        size_t[] open = [0];              // stack of open element indices
        size_t[string] ids;
        size_t root = Document.unknown;

        size_t addElement(ref C node)
        {
            immutable parent = open[$-1];
            immutable idx = nodes.length;
            auto a = attrs(node);
            nodes ~= Element(node.name, a);
            nodes[parent].children ~= idx;
            auto idp = "id" in a;
            if (idp && !(*idp in ids))
                ids[*idp] = idx;
            if (root is Document.unknown && node.name == "svg")
                root = idx;
            return idx;
        }

        void addText(ref C node)
        {
            immutable parent = open[$-1];
            immutable idx = nodes.length;
            nodes ~= Element("", null, node.content, null);
            nodes[parent].children ~= idx;
        }

        void onElementStart(ref C node)
        {
            open ~= addElement(node);
        }

        void onElementEmpty(ref C node)
        {
            addElement(node);
        }

        void onElementEnd(ref C node)
        {
            if (open.length > 1) // mismatched end tags: keep the stack rooted
                open = open[0 .. $-1];
        }

        void onText(ref C node)
        {
            addText(node);
        }

        void onCDataSection(ref C node)
        {
            addText(node);
        }
    }

    auto sax = c.saxParser!(Builder);
    sax.setSource(source);
    sax.processDocument();
    enforce(sax.handler.root != Document.unknown, "no <svg> root element");

    Document doc;
    doc.nodes = cast(immutable) sax.handler.nodes; // seal the arena
    doc.ids = sax.handler.ids;
    doc.root = sax.handler.root;
    return doc;
}

unittest
{
    import std.range;
    auto doc = parseSVG(`<?xml version="1.0"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
            <defs>
                <linearGradient id="g1"><stop offset="0"/></linearGradient>
            </defs>
            <g id="grp" transform="rotate(10)" display="inline">
                <rect id="dup" width="1" height="1"/>
                <rect id="dup" width="2" height="2"/>
            </g>
            <text>t <tspan>s</tspan></text>
        </svg>`);

    // The root is the first <svg> element; the arena is rooted at 0 and
    // has the root as its only *element* child (prolog whitespace may
    // show up as text children).
    assert(doc.root > 0 && doc.nodes[doc.root].name == "svg");
    assert(doc.nodes[0].name.empty);
    size_t rootKids;
    foreach (ch; doc.nodes[0].children)
        if (!doc.nodes[ch].name.empty)
            ++rootKids, assert(ch == doc.root);
    assert(rootKids == 1);

    // Attributes arrive flattened in the element's map.
    auto svg = doc.nodes[doc.root];
    assert(svg.attrs["width"] == "10" && svg.attrs["xmlns"] == "http://www.w3.org/2000/svg");

    // defs/clipPath content is part of the document and its id registry:
    // forward and backward references resolve to arena indices. Gradients
    // and shapes inside <defs> or later in the tree all register.
    assert(doc.byId("g1") != Document.unknown);
    assert(doc.nodes[doc.byId("g1")].name == "linearGradient");
    assert(doc.byId("grp") != Document.unknown);
    assert(doc.byId("nope") == Document.unknown);
    // duplicate ids: the first occurrence wins (XML ids are unique).
    auto firstDup = doc.byId("dup");
    assert(doc.nodes[firstDup].attrs["width"] == "1");

    // Children keep document order, and text/CDATA are nodes too: the
    // <text> element's children are the text, the <tspan> element and -
    // inside the tspan - its text, interleaved. (Indentation between the
    // rects below shows up as text children, like any XML whitespace.)
    size_t textEl, rects;
    foreach (ch; doc.nodes[doc.byId("grp")].children)
        if (!doc.nodes[ch].name.empty)
            ++rects, assert(doc.nodes[ch].name == "rect");
    assert(rects == 2);
    foreach (ch; svg.children)
        if (doc.nodes[ch].name == "text")
            textEl = ch;
    auto kids = doc.nodes[textEl].children;
    assert(kids.length == 2);
    assert(doc.nodes[kids[0]].name.empty && doc.nodes[kids[0]].text == "t ");
    assert(doc.nodes[kids[1]].name == "tspan");
    auto tspanKids = doc.nodes[kids[1]].children;
    assert(tspanKids.length == 1 && doc.nodes[tspanKids[0]].text == "s");
}

unittest
{
    // CDATA flows in as text nodes; the root may be nested in the
    // document; a document without <svg> is an error.
    auto doc = parseSVG(`<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN">
        <wrapper><svg width="4" height="3"><![CDATA[hi]]></svg></wrapper>`);
    assert(doc.root != 0 && doc.nodes[doc.root].name == "svg");

    bool thrown;
    try
        parseSVG(`<html><body>no svg here</body></html>`);
    catch (Exception e)
        thrown = true;
    assert(thrown, "documents without <svg> must throw");
}
