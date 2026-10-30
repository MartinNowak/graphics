module graphics.svg.parser;

import std.algorithm : canFind, countUntil, startsWith;
import std.exception;
import std.experimental.xml.cursor, std.experimental.xml.lexers, std.experimental.xml.parser;
import std.experimental.xml.interfaces : isCursor, XMLKind;
import std.range : empty;

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

/// The five entities every XML document has (XML 1.0 §4.4.7); a document may
/// not redeclare them (§4.2), so they never enter the entity table and a
/// reference to one keeps its spelling for whatever decodes it later.
private enum xmlBuiltins = ["amp", "lt", "gt", "quot", "apos"];

/// XML 1.0 §4.4.2: a reference to an internal general entity is replaced by
/// the content of its declaration before the document is parsed. SVG makes
/// the document XML - §G.2 requires a conforming fragment to "be XML
/// well-formed ([XML10], section 2.1)" - so `<g>&shape;</g>` is a `<g>`
/// containing the octagon `<path>` the test suite declares in its DOCTYPE.
/// The expansion runs over the source text, which is the only place where a
/// replacement that is *markup* can become markup: the token walk below sees
/// the elements exactly where the reference stood, and a replacement that is
/// text still ends up in a text node.
///
/// Only the internal subset is read. The external subset is never fetched,
/// as §1.3 advises ("While a DTD is provided in this specification, the use
/// of DTDs for validating XML documents is known to be problematic ... It is
/// not recommended that a DOCTYPE declaration be included in SVG documents");
/// a document that relies on `&external;` therefore keeps its reference
/// written out, and an undeclared reference is left alone too - dropping
/// content is worse than showing what was typed. Documents without entity
/// declarations, which is nearly all of them, are returned unchanged.
private string expandEntities(string src)
{
    auto at = countUntil(src, "<!DOCTYPE");
    if (at < 0)
        return src;
    immutable subset = internalSubset(src, cast(size_t) at);
    if (subset[0] is size_t.max)
        return src; // `<!DOCTYPE svg PUBLIC "..." "...">`: nothing declared here

    auto table = internalEntities(src[subset[0] .. subset[1]]);
    if (table.empty)
        return src;

    // Declarations may reference other declarations. Resolve them first, so
    // one pass over the document suffices; XML forbids an entity from
    // referencing itself (§4.4.2), and the guard below makes such a cycle
    // leave the nested reference written out instead of spinning.
    bool[string] active;
    string resolve(string name)
    {
        auto p = name in table;
        if (p is null || name in active)
            return null; // unknown, or a cycle: the caller keeps `&name;`
        active[name] = true;
        immutable expanded = replaceRefs(*p, &resolve);
        active.remove(name);
        return expanded;
    }
    foreach (name; table.keys)
    {
        auto value = resolve(name);
        if (value !is null)
            table[name] = value;
    }

    // Everything from the subset's `]` on is document text. The declaration
    // itself is left byte-for-byte as it was, so the XML lexer still sees a
    // complete (and still ignorable) DOCTYPE.
    return src[0 .. subset[1]] ~ replaceRefs(src[subset[1] .. $], &resolve);
}

/// `[begin, end)` of the internal subset of the `<!DOCTYPE` at `dtd`, or
/// `[size_t.max, size_t.max]` when the declaration has none. `>` and `]`
/// inside a comment or an entity's replacement text mean nothing to the
/// declaration around them, so both are stepped over.
private size_t[2] internalSubset(string src, size_t dtd)
{
    size_t i = dtd + "<!DOCTYPE".length;
    for (; i < src.length; )
    {
        immutable next = skipMarkup(src, i);
        if (next != i)
            i = next;
        else if (src[i] == '[')
            break;
        else if (src[i] == '>')
            return [size_t.max, size_t.max];
        else
            ++i;
    }
    if (i >= src.length)
        return [size_t.max, size_t.max];

    immutable begin = i + 1;
    for (++i; i < src.length; )
    {
        immutable next = skipMarkup(src, i);
        if (next != i)
            i = next;
        else if (src[i] == ']')
            return [begin, i];
        else
            ++i;
    }
    return [size_t.max, size_t.max];
}

/// The subset's general entity declarations as `name => replacement text`.
/// Parameter entities (`<!ENTITY % name ...>`, §4.2) are not general
/// entities and never appear as `&name;`; external-entity declarations
/// (`SYSTEM`/`PUBLIC`) and unparsed ones (an `NDATA` marker, §4.7) carry no
/// replacement text. None of them is collected.
private string[string] internalEntities(string subset)
{
    string[string] res;
    for (size_t i = 0; i < subset.length; )
    {
        immutable next = skipMarkup(subset, i);
        if (next != i)
        {
            i = next;
            continue;
        }
        if (!subset[i .. $].startsWith("<!ENTITY"))
        {
            ++i;
            continue;
        }

        string name, value;
        bool general;
        size_t j = skipSpace(subset, i + "<!ENTITY".length);
        if (j < subset.length && subset[j] != '%')
        {
            immutable begin = j;
            while (j < subset.length && isNameChar(subset[j]))
                ++j;
            name = subset[begin .. j];
            j = skipSpace(subset, j);
            if (!name.empty && j < subset.length && (subset[j] == '"' || subset[j] == '\''))
            {
                immutable after = skipMarkup(subset, j); // just past the literal
                immutable end = pastGT(subset, after);   // just past the '>'
                value = subset[j + 1 .. after - 1];
                general = !canFind(subset[after .. end], "NDATA");
            }
        }

        i = skipDecl(subset, i);
        if (general && !canFind(xmlBuiltins, name))
            res[name] = value;
    }
    return res;
}

/// Replace each `&name;` in `text` that `lookup` has a replacement for; a
/// null answer leaves the reference exactly as written. Character references
/// begin with `#`, so they never reach a name, and comment and CDATA content
/// holds no references (§2.2, §2.7) - both are copied through untouched.
private string replaceRefs(string text, scope string delegate(string) lookup)
{
    string res;
    res.reserve(text.length);
    for (size_t i = 0; i < text.length; )
    {
        if (text[i .. $].startsWith("<!--"))
        {
            immutable end = countUntil(text[i + 4 .. $], "-->");
            immutable stop = end < 0 ? text.length : i + 4 + cast(size_t) end + 3;
            res ~= text[i .. stop];
            i = stop;
            continue;
        }
        if (text[i .. $].startsWith("<![CDATA["))
        {
            immutable end = countUntil(text[i + 9 .. $], "]]>");
            immutable stop = end < 0 ? text.length : i + 9 + cast(size_t) end + 3;
            res ~= text[i .. stop];
            i = stop;
            continue;
        }

        if (text[i] != '&')
        {
            res ~= text[i];
            ++i;
            continue;
        }

        size_t j = i + 1;
        while (j < text.length && isNameChar(text[j]))
            ++j;
        immutable value = j > i + 1 && j < text.length && text[j] == ';'
            ? lookup(text[i + 1 .. j]) : null;
        if (value is null)
            res ~= text[i++]; // not a reference we know
        else
        {
            res ~= value;
            i = j + 1;
        }
    }
    return res;
}

/// Step over a comment or a quoted literal starting at `i`; returns `i`
/// itself when neither starts there.
private size_t skipMarkup(string s, size_t i)
{
    if (s[i .. $].startsWith("<!--"))
    {
        immutable end = countUntil(s[i + 4 .. $], "-->");
        return end < 0 ? s.length : i + 4 + cast(size_t) end + 3;
    }
    if (s[i] == '"' || s[i] == '\'')
    {
        immutable end = countUntil(s[i + 1 .. $], s[i .. i + 1]);
        return end < 0 ? s.length : i + 1 + cast(size_t) end + 1;
    }
    return i;
}

/// Index just past the `>` that closes the markup declaration at `i`.
private size_t skipDecl(string s, size_t i)
{
    return pastGT(s, i + 1);
}

/// Index just past the first `>` at or after `p` that is neither quoted nor
/// commented. A replacement text is full of them - `&shape;` is a `<path/>` -
/// so every DTD scan has to step over the literals to find the `>` that
/// actually ends the declaration.
private size_t pastGT(string s, size_t p)
{
    for (; p < s.length; )
    {
        immutable next = skipMarkup(s, p);
        if (next != p)
            p = next;
        else if (s[p] == '>')
            return p + 1;
        else
            ++p;
    }
    return s.length;
}

size_t skipSpace(string s, size_t i)
{
    while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
        ++i;
    return i;
}

/// True for the XML Name characters (§2.13) an entity name is built of.
private bool isNameChar(char ch)
{
    return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z'
        || ch >= '0' && ch <= '9' || ch == '.' || ch == '-'
        || ch == '_' || ch == ':';
}

/// Parse `source` into a `Document`. Tolerates documents without an XML
/// declaration (SVG does not require one); XML errors are reported to the
/// parser's error sink and the best-effort tree is kept, as before.
/// Throws if the document contains no <svg> element.
Document parseSVG(string source)
{
    // Internal general entities are markup by the time anything looks at the
    // document (XML 1.0 §4.4.2), so they are already expanded for the walk.
    auto text = expandEntities(source);

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
    auto c = text.lexer.parser.cursor((CursorError e) {});
    c.setSource(text);

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

unittest
{
    // Internal general entities (XML 1.0 §4.4.2) are content, not text: the
    // suite's render-elems-03-t draws its octagon as `&shape;`, a whole
    // <path> declared in the DOCTYPE's internal subset, and the
    // coords-viewattr tests place their marker rects the same way. A
    // replacement that is markup becomes markup, in place; parameter
    // entities (§4.2) and unparsed ones (NDATA, §4.7) carry no replacement
    // text; a cycle - which §4.4.2 forbids - stays as written.
    auto doc = parseSVG(`<!DOCTYPE svg [
        <!ENTITY % paint "fill='red'">
        <!ENTITY shape "<path id='P' d='M0,0 l9,0 l0,9 z'/>">
        <!ENTITY w "7">
        <!ENTITY row "w=&w;">
        <!ENTITY loop "&loop;">
        <!ENTITY raster "photo.png" NDATA png>
        <!ENTITY ext SYSTEM "logo.svg">
    ]>
    <svg width="10" height="10">
        <g id="g">&shape;</g>
        <rect id="r" width="&w;"/>
        <image id="i" xlink:href="&ext;"/>
        <text id="t">&row; &raster; &loop; &undeclared; %paint;</text>
        <text id="b">R&amp;D &#65;</text>
        <!-- &shape; -->
        <svg id="c"><![CDATA[&shape;]]></svg>
    </svg>`);

    // Markup in, markup out: the path is a child of the <g>, in place.
    auto g = doc.byId("g");
    assert(doc.nodes[g].name == "g");
    size_t paths, kids;
    foreach (ch; doc.nodes[g].children)
        if (!doc.nodes[ch].name.empty)
            ++kids, assert(doc.nodes[ch].name == "path" && ch == doc.byId("P"));
    assert(kids == 1, "the entity's path is the group's only element child");

    // Attribute values expand too, and a declaration may reference another
    // declaration: the rect's width is `7`, the text starts `w=7`.
    assert(doc.nodes[doc.byId("r")].attrs["width"] == "7");

    string allText(size_t i)
    {
        string s = doc.nodes[i].text;
        foreach (ch; doc.nodes[i].children)
            if (doc.nodes[ch].name.empty)
                s ~= allText(ch);
        return s;
    }
    assert(allText(doc.byId("t")) == `w=7 &raster; &loop; &undeclared; %paint;`,
        "unparsed, cyclic, undeclared and parameter references stay written out");

    // Predefined entities and character references are not the expander's
    // business: neither name is in the table (`#` is not a Name character),
    // so both reach the text node as written.
    import std.format : format;
    assert(allText(doc.byId("b")) == `R&amp;D &#65;`,
        format("built-ins and character references reach text as written: %s",
            allText(doc.byId("b"))));

    // An external-entity reference names a file, not replacement text, and
    // neither comments nor CDATA hold references (§2.2, §2.7): exactly one
    // <path> exists in the whole document.
    assert(doc.nodes[doc.byId("i")].attrs["xlink:href"] == "&ext;");
    assert(allText(doc.byId("c")) == "&shape;");
    foreach (n; doc.nodes)
        if (n.name == "path")
            ++paths;
    assert(paths == 1, "only the expanded reference is a path");
}
