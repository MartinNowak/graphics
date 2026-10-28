module graphics.svg.parser;

import std.algorithm : countUntil;
import std.exception;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser;
import std.experimental.xml.interfaces : isCursor, XMLKind;

enum xlinkNS = "http://www.w3.org/1999/xlink";

// Flatten the attributes of the cursor's current element into a map,
// resolving namespace prefixes against `ns`. XLink attributes are
// defined by namespace, not by prefix spelling (§5.1.2): a `P:local`
// attribute whose prefix resolves to the XLink namespace is stored
// normalized as `xlink:local`, and one bound to any other namespace
// (conform-viewers-03-f binds `xlink` to nonsense on purpose) is
// dropped - such attributes carry no rendering meaning. The undeclared
// `xlink` prefix keeps working (seeded default, lenient as before);
// `xml:` and `xmlns:` declarations are kept verbatim.
string[string] attrs(CursorType)(ref CursorType cursor, in string[string] ns)
    if (isCursor!CursorType)
{
    string[string] res;
    foreach (a; cursor.attributes)
    {
        immutable col = countUntil(a.name, ':');
        if (col > 0)
        {
            immutable prefix = a.name[0 .. cast(size_t) col];
            if (prefix != "xmlns")
            {
                auto uri = prefix in ns;
                if (uri !is null && *uri != xlinkNS && prefix != "xml")
                    continue; // unknown-namespace attribute: inert
                if (uri !is null && *uri == xlinkNS)
                {
                    res["xlink:" ~ a.name[cast(size_t) col + 1 .. $]] = a.value;
                    continue;
                }
            }
        }
        res[a.name] = a.value;
    }
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
    // The cursor tree-walk, not std.experimental.xml's saxParser wrapper:
    // 0.1.7's wrapper drives the document with enter/next/exit but relies
    // on the handler popping its stack at every onElementEnd - while the
    // cursor's enter() uses `advanceInput() && kind != elementEnd` to
    // test for emptiness, *consuming* the close tag when an element's
    // whole content is whitespace (the parser drops whitespace-only text
    // by default). That END event never reaches the handler, the stack
    // shifts, and the unclosed element swallows its following siblings
    // (masking-path-08-b's `<clipPath id="emptyclip">` ate the rest of
    // its <defs>, everything behind it with it). The cursor's own
    // enter/next/exit semantics are correct, so the walk lives here.
    auto c = source.lexer.parser.cursor((CursorError e) {});
    c.setSource(source);

    Element[] nodes = [Element.init]; // nodes[0]: the document pseudo-root
    size_t[string] ids;
    size_t root = Document.unknown;

    // Prefix -> namespace URIs, live for the subtree currently being
    // walked. `xlink` starts out bound so documents that never declare
    // it still render (as before); an explicit rebinding shadows it.
    string[string] ns = ["xlink": xlinkNS,
        "xml": "http://www.w3.org/XML/1998/namespace"];

    struct Binding
    {
        string prefix, old; // old == null: the prefix had no binding
    }

    // Apply the current element's own xmlns: declarations (they cover
    // its attributes too, so this runs before attrs()); returns what
    // to undo after the subtree.
    Binding[] bindNs()
    {
        Binding[] changed;
        foreach (a; c.attributes)
            if (a.name.length > 6 && a.name[0 .. 6] == "xmlns:")
            {
                immutable prefix = a.name[6 .. $];
                auto p = prefix in ns;
                changed ~= Binding(prefix, p ? *p : null);
                ns[prefix] = a.value;
            }
        return changed;
    }

    void unbindNs(ref Binding[] changed)
    {
        foreach_reverse (b; changed)
            if (b.old is null)
                ns.remove(b.prefix);
            else
                ns[b.prefix] = b.old;
    }

    void addElement(size_t parent)
    {
        immutable idx = nodes.length;
        auto a = attrs(c, ns);
        nodes ~= Element(c.name, a);
        nodes[parent].children ~= idx;
        auto idp = "id" in a;
        if (idp && !(*idp in ids))
            ids[*idp] = idx;
        if (root is Document.unknown && c.name == "svg")
            root = idx;
    }

    void addText(size_t parent)
    {
        immutable idx = nodes.length;
        nodes ~= Element("", null, c.content, null);
        nodes[parent].children ~= idx;
    }

    // Children of the arena node `parent`; the cursor sits on the first
    // child. Iterating siblings with next() skips over the end tags of
    // descended-into children (exit() parks the cursor on the parent's
    // own end tag, which the caller's next() steps past). Comments,
    // PIs and DTD noise are dropped; text and CDATA become text nodes.
    void walkChildren(size_t parent)
    {
        do switch (c.kind)
        {
        case XMLKind.elementStart:
            {
                auto declared = bindNs();
                addElement(parent);
                if (c.enter())
                    walkChildren(nodes.length - 1);
                unbindNs(declared);
            }
            break;
        case XMLKind.elementEmpty:
            {
                auto declared = bindNs();
                addElement(parent);
                unbindNs(declared);
            }
            break;
        case XMLKind.text, XMLKind.cdata:
            addText(parent);
            break;
        default:
            break;
        }
        while (c.next());
        c.exit();
    }

    if (c.enter()) // the document's first child (after any <?xml?>)
        walkChildren(0);
    enforce(root != Document.unknown, "no <svg> root element");

    Document doc;
    doc.nodes = cast(immutable) nodes; // seal the arena
    doc.ids = ids;
    doc.root = root;
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

unittest
{
    import std.range;
    // An element whose entire content is whitespace must still close:
    // the XML library's sax wrapper loses that element's end event
    // (cursor.enter() consumes the close tag while testing for
    // emptiness), which used to nest every following sibling inside it
    // - masking-path-08-b's whitespace-only <clipPath> swallowed the
    // rest of its <defs>. The manual cursor walk keeps siblings siblings.
    auto doc = parseSVG(`<svg><defs>
        <clipPath id="e">
        </clipPath><rect id="R" width="1" height="1"/></defs>
        <rect id="S" width="2" height="2"/></svg>`);

    auto cp = doc.byId("e");
    assert(doc.nodes[cp].name == "clipPath");
    assert(doc.nodes[cp].children.empty, "whitespace-only clipPath: no children");

    size_t defs;
    foreach (ch; doc.nodes[doc.root].children)
        if (doc.nodes[ch].name == "defs")
            defs = ch;
    bool rUnderDefs;
    foreach (ch; doc.nodes[defs].children)
        if (ch == doc.byId("R"))
            rUnderDefs = true;
    assert(rUnderDefs, "the rect following an empty element is its sibling");
    assert(doc.byId("S") != Document.unknown);
}

unittest
{
    // XLink is the namespace, not the prefix: a prefix bound elsewhere
    // is inert (conform-viewers-03-f's `<g xmlns:xlink="bogus">` must
    // not paint its image), any prefix bound to the real namespace
    // normalizes to `xlink:`, and bindings unwind with the subtree.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
            xmlns:x="http://www.w3.org/1999/xlink">
        <image x:href="norm.png"/>
        <g xmlns:xlink="http://example.net/bar">
            <image xlink:href="bad.png"/>
        </g>
        <image xlink:href="good.png"/>
        </svg>`);
    string[] hrefs;
    foreach (n; doc.nodes)
        if (auto p = "xlink:href" in n.attrs)
            hrefs ~= *p;
    assert(hrefs == ["norm.png", "good.png"],
        "XLink attributes follow their namespace binding");
}
