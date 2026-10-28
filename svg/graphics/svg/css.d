module graphics.svg.css;

// CSS styling (SVG 1.1 §6.2/§6.4): a style-sheet parser for the `<style>`
// elements of a document, compiled selectors, and a matcher that walks the
// parser arena (selectors match the *original* tree, so `use` clones match
// at their source position, as styling-css-* pins).
//
// Core: type/`*`/`.class`/`#id` compounds with descendant and `>`
// combinators, the specificity triple, and `!important`. Constructs not
// yet applied (attribute selectors, `+`, `:first-child`, `:lang()`,
// interaction pseudo-classes) compile to a never-match compound, which
// keeps their rules inert and the rendered picture identical to no CSS.

import std.algorithm : canFind, sort;
import std.array : appender, split;
import std.ascii : isWhite, toLower;
import std.range;
import std.string : strip;

import graphics.svg.parser : Document, Element, parseSVG;

/// One compound simple selector: `circle`, `*`, `.test3`, `#alpha-2`,
/// `g#alpha`, ... `never` marks a construct that cannot match at runtime:
/// the not-yet-implemented pseudo-classes and pseudo-elements (a compound
/// is still kept, and counted, so its specificity behaves the same).
struct Compound
{
    string     type;     // element name (case-sensitive: XML); "" = none
    bool       star;     // `*`: any element, contributes no specificity
    string     id;
    string[]   classes;
    bool       never;
}

/// A style rule: one compiled selector chain and its declarations. A
/// comma-separated selector group shares one declaration block; each
/// selector becomes its own Rule (sharing the declaration slices).
struct Rule
{
    Compound[] chain;
    bool[]     child;  // child[i], i > 0: the combinator before chain[i] is `>`
    int[3]     spec;   // (#id, .class/attr/pseudo-class, type) triple
    size_t     order;  // sheet order across all <style> elements
    string[]   props;  // property names, lower-cased (CSS: case-insensitive)
    string[]   vals;
    bool[]     imp;    // !important
}

/// A declaration from a `style=""` attribute (same grammar as a rule
/// block body), with the `!important` marker separated.
struct Decl
{
    string prop;
    string val;
    bool   imp;
}

private enum npos = size_t.max;

/// Parse one style sheet. `order` is the document-wide rule counter the
/// caller threads through every <style> element so sheet order survives.
Rule[] parseSheet(string src, ref size_t order)
{
    Rule[] rules;
    src = stripComments(src);

    size_t i = 0;
    while (i < src.length)
    {
        while (i < src.length && isWhite(src[i]))
            ++i;
        if (i >= src.length)
            break;

        // At-rules are noise for now: a statement ends at its top-level
        // `;`, a block at its matching `}` (@font-face; @media would also
        // just be skipped whole here).
        if (src[i] == '@')
        {
            i = skipAtRule(src, i);
            continue;
        }

        immutable brace = findFrom(src, i, '{');
        if (brace == npos)
            break; // trailing junk without a block: the sheet is done
        immutable semi = topAt(src, i, ';');
        if (semi < brace) // garbage ahead of the selector: skip the statement
        {
            i = semi + 1;
            continue;
        }

        immutable close = closeBrace(src, brace);
        auto block = src[brace + 1 .. close == npos ? src.length : close];
        auto decls = parseDecls(block);
        if (!decls.empty)
        {
            string[] props, vals;
            bool[] imps;
            foreach (ref d; decls)
            {
                props ~= d.prop;
                vals ~= d.val;
                imps ~= d.imp;
            }
            foreach (sel; splitTop(src[i .. brace], ','))
            {
                auto c = compileSelector(sel);
                if (c.malformed || c.chain.empty)
                    continue; // an invalid selector drops the rule
                rules ~= Rule(c.chain, c.child, c.spec, order++,
                              props, vals, imps);
            }
        }
        i = close == npos ? src.length : close + 1;
    }
    return rules;
}

/// All rules of every <style> element, in document order. Style text
/// arrives as the parser wrote it: sxml hands `&gt;` through raw while
/// CDATA sections are literal, and the suite writes the same `>`
/// selector both ways (styling-css-04-f escapes, struct-use-10-f is
/// CDATA), so the text is XML-unescaped before it is tokenized.
Rule[] collectStyles(in Document doc)
{
    Rule[] rules;
    size_t order = 0;

    void walk(size_t idx)
    {
        foreach (ch; doc.nodes[idx].children)
        {
            if (doc.nodes[ch].name == "style")
            {
                string src;
                foreach (t; doc.nodes[ch].children)
                    if (doc.nodes[t].name.empty)
                        src ~= doc.nodes[t].text;
                rules ~= parseSheet(xmlUnescape(src), order);
            }
            walk(ch);
        }
    }

    walk(0);
    return rules;
}

/// parent[i] = arena index of node i's parent, -1 for nodes[0]
/// (the document pseudo-root). The selector matcher walks it upwards.
int[] cssAncestry(in immutable(Element)[] nodes)
{
    int[] parent = new int[](nodes.length);
    parent[0] = -1;

    void walk(size_t idx)
    {
        foreach (ch; nodes[idx].children)
        {
            parent[ch] = cast(int) idx;
            walk(ch);
        }
    }

    walk(0);
    return parent;
}

/// Does rule `r` apply to node `idx`? The last compound is matched
/// against the element itself and the chain is walked right-to-left up
/// the parent array: `>` steps exactly one parent, a space any number.
bool matches(in immutable(Element)[] nodes, in int[] parent,
             size_t idx, ref const Rule r)
{
    int cur = cast(int) idx;
    if (!matchCompound(nodes[cur], r.chain[$ - 1]))
        return false;

    for (int i = cast(int) r.chain.length - 2; i >= 0; --i)
    {
        if (r.child[i + 1])
        {
            cur = parent[cur];
            if (cur < 0 || !matchCompound(nodes[cur], r.chain[i]))
                return false;
        }
        else
        {
            while (true)
            {
                cur = parent[cur];
                if (cur < 0)
                    return false;
                if (matchCompound(nodes[cur], r.chain[i]))
                    break;
            }
        }
    }
    return true;
}

/// The rules matching node `idx` in cascade order: specificity triple
/// ascending, then sheet order (CSS 2.1 §6.4.3 - the winner is last).
const(Rule)[] cssCascade(in immutable(Element)[] nodes, in int[] parent,
                         size_t idx, in Rule[] rules)
{
    const(Rule)[] ms;
    foreach (ref const r; rules)
        if (matches(nodes, parent, idx, r))
            ms ~= r;

    // Sort indices: the elements themselves are const.
    size_t[] ix;
    foreach (i; 0 .. ms.length)
        ix ~= i;
    ix.sort!((a, b) => ms[a].spec[0] != ms[b].spec[0]
        ? ms[a].spec[0] < ms[b].spec[0]
        : ms[a].spec[1] != ms[b].spec[1] ? ms[a].spec[1] < ms[b].spec[1]
        : ms[a].spec[2] != ms[b].spec[2] ? ms[a].spec[2] < ms[b].spec[2]
        : ms[a].order < ms[b].order);

    const(Rule)[] sorted;
    foreach (i; ix)
        sorted ~= ms[i];
    return sorted;
}

/// Declarations of a `style=""` attribute value.
Decl[] styleDecls(string src)
{
    return parseDecls(src);
}

/// True when a declaration value carries the `!important` marker. In a
/// presentation attribute it is not valid (§6.2: attribute values take
/// no markers), and the whole attribute is then dropped.
bool hasImportant(string v)
{
    return importantPos(v) != npos;
}

private size_t importantPos(string v)
{
    int depth = 0;
    char quote = 0;
    size_t i = 0;
    while (i < v.length)
    {
        immutable c = v[i];
        if (quote)
        {
            if (c == quote)
                quote = 0;
        }
        else if (c == '"' || c == '\'')
            quote = c;
        else if (c == '(' || c == '[')
            ++depth;
        else if (c == ')' || c == ']')
            depth = depth ? depth - 1 : 0;
        else if (c == '!' && !depth)
        {
            string rest;
            foreach (ch; v[i + 1 .. $])
                if (!isWhite(ch))
                    rest ~= cast(char) toLower(ch);
            if (rest == "important")
                return i;
        }
        ++i;
    }
    return npos;
}

// ---------------------------------------------------------------- matcher

private bool matchCompound(ref const Element el, ref const Compound c)
{
    if (el.name.empty || c.never)
        return false;
    if (!c.star && !c.type.empty && el.name != c.type)
        return false; // type selectors are case-sensitive in XML/SVG
    if (!c.id.empty && el.attrs.get("id", "") != c.id)
        return false;
    if (c.classes.length)
    {
        auto cls = el.attrs.get("class", "");
        if (cls.empty)
            return false;
        foreach (want; c.classes)
        {
            bool found;
            foreach (tok; split(cls))
                if (tok == want) // class values are case-sensitive
                {
                    found = true;
                    break;
                }
            if (!found)
                return false;
        }
    }
    return true;
}

// -------------------------------------------------------- declaration side

private Decl[] parseDecls(string block)
{
    Decl[] decls;
    foreach (ref chunk; splitTop(block, ';'))
    {
        chunk = strip(chunk);
        if (chunk.empty)
            continue;
        immutable colon = topAt(chunk, 0, ':');
        if (colon == npos)
            continue; // no value: the declaration is invalid
        string prop;
        foreach (ch; strip(chunk[0 .. colon]))
            prop ~= cast(char) toLower(ch); // property names are ASCII
        if (prop.empty || !isIdentStr(prop))
            continue;

        auto val = strip(chunk[colon + 1 .. $]);
        bool imp = false;
        immutable p = importantPos(val);
        if (p != npos)
        {
            val = strip(val[0 .. p]);
            imp = true;
        }
        if (val.empty)
            continue;
        decls ~= Decl(prop, val, imp);
    }
    return decls;
}

// ------------------------------------------------------- selector compiler

private struct Chain
{
    Compound[] chain;
    bool[]     child;
    int[3]     spec;
    bool       malformed;
}

private Chain compileSelector(string s)
{
    Chain cs;

    Compound c;
    bool open;    // `c` holds a compound not yet emitted
    bool curGt;   // combinator before the open compound
    bool pendingGt; // a `>` seen after the last compound ended

    void emit()
    {
        cs.child ~= cs.chain.empty ? false : curGt;
        curGt = false;
        if (!c.id.empty)
            ++cs.spec[0];
        cs.spec[1] += cast(int) c.classes.length;
        if (!c.type.empty) // `*` adds nothing (styling-css-04-f: `#alpha * rect` = 101)
            ++cs.spec[2];
        cs.chain ~= c;
        c = Compound.init;
    }

    size_t i = 0;

    while (i < s.length)
    {
        while (i < s.length && isWhite(s[i]))
            ++i;
        if (i >= s.length)
            break;

        if (s[i] == '>')
        {
            if (!open)
            {
                cs.malformed = true; // `>` with nothing to its left
                return cs;
            }
            pendingGt = true;
            ++i;
            continue;
        }

        if (!startsCompound(s[i]))
        {
            cs.malformed = true; // `+`, `~`, `|`, `[`, junk
            return cs;
        }

        if (open)
        {
            emit();
            curGt = pendingGt;
        }
        pendingGt = false;

        if (!parseCompound(s, i, c))
        {
            cs.malformed = true;
            return cs;
        }
        open = true;
    }

    if (open && pendingGt)
    {
        cs.malformed = true; // dangling `>`
        return cs;
    }
    if (open)
        emit();
    return cs;
}

private bool startsCompound(char ch)
{
    return ch == '*' || ch == '#' || ch == '.' || ch == ':' ||
        isIdentStart(ch);
}

private bool isIdentStart(char ch)
{
    return ch == '-' || ch == '_' || (ch >= 'a' && ch <= 'z') ||
        (ch >= 'A' && ch <= 'Z');
}

private bool isIdent(char ch)
{
    return isIdentStart(ch) || (ch >= '0' && ch <= '9');
}

private bool isIdentStr(string s)
{
    foreach (ch; s)
        if (!isIdent(ch))
            return false;
    return true;
}

// Read one compound; false = malformed. `i` lands on the first character
// that ends it (whitespace, combinator, `,`, or end).
private bool parseCompound(string s, ref size_t i, ref Compound c)
{
    while (i < s.length)
    {
        immutable ch = s[i];
        if (isIdentStart(ch))
        {
            if (c.type.length || c.star)
                return false; // a second bare name inside one compound
            immutable start = i;
            while (i < s.length && isIdent(s[i]))
                ++i;
            c.type = s[start .. i];
        }
        else if (ch == '*')
        {
            if (c.star || c.type.length)
                return false;
            c.star = true;
            ++i;
        }
        else if (ch == '#')
        {
            if (c.id.length)
                return false;
            immutable start = ++i;
            while (i < s.length && isIdent(s[i]))
                ++i;
            if (i == start)
                return false;
            c.id = s[start .. i];
        }
        else if (ch == '.')
        {
            immutable start = ++i;
            while (i < s.length && isIdent(s[i]))
                ++i;
            if (i == start)
                return false;
            c.classes ~= s[start .. i];
        }
        else if (ch == ':')
        {
            // Nothing pseudo matches yet: interaction states never by
            // nature, structural ones until they are implemented - a
            // never compound keeps the rule inert either way.
            c.never = true;
            if (++i < s.length && s[i] == ':') // pseudo-element
                ++i;
            while (i < s.length && isIdent(s[i]))
                ++i;
            if (i < s.length && s[i] == '(')
            {
                int depth = 1;
                for (++i; i < s.length && depth; ++i)
                    if (s[i] == '(')
                        ++depth;
                    else if (s[i] == ')')
                        --depth;
            }
        }
        else
            break;
    }
    return true;
}

// ------------------------------------------------------------ sheet lexer

private string stripComments(string s)
{
    if (!canFind(s, "/*"))
        return s;
    auto acc = appender!string;
    size_t i = 0;
    while (i < s.length)
    {
        if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '*')
        {
            size_t j = i + 2;
            while (j + 1 < s.length && !(s[j] == '*' && s[j + 1] == '/'))
                ++j;
            i = j + 1 < s.length ? j + 2 : s.length;
            acc.put(' '); // a comment is a separator, never glue
        }
        else
            acc.put(s[i++]);
    }
    return acc.data;
}

private size_t skipAtRule(string s, size_t i) // s[i] == '@'
{
    int depth = 0;
    while (i < s.length)
    {
        immutable char c = s[i];
        if (c == ';' && !depth)
            return i + 1;
        if (c == '{')
            ++depth;
        else if (c == '}')
        {
            if (!depth)
                return i + 1; // the block this at-rule belonged to
            if (--depth == 0)
                return i + 1; // block at-rules end with their own brace
        }
        ++i;
    }
    return s.length;
}

private size_t closeBrace(string s, size_t open) // index of the matching `}`
{
    int depth = 0;
    char quote = 0;
    for (size_t i = open; i < s.length; ++i)
    {
        immutable c = s[i];
        if (quote)
        {
            if (c == quote)
                quote = 0;
        }
        else if (c == '"' || c == '\'')
            quote = c;
        else if (c == '{')
            ++depth;
        else if (c == '}' && --depth == 0)
            return i;
    }
    return npos;
}

// Index at or after i of the first sep outside any (), [] or string.
private size_t topAt(string s, size_t i, char sep)
{
    int depth = 0;
    char quote = 0;
    while (i < s.length)
    {
        immutable c = s[i];
        if (quote)
        {
            if (c == quote)
                quote = 0;
        }
        else if (c == '"' || c == '\'')
            quote = c;
        else if (c == '(' || c == '[')
            ++depth;
        else if (c == ')' || c == ']')
            depth = depth ? depth - 1 : 0;
        else if (c == sep && !depth)
            return i;
        ++i;
    }
    return npos;
}

private size_t findFrom(string s, size_t i, char c)
{
    while (i < s.length && s[i] != c)
        ++i;
    return i < s.length ? i : npos;
}

// Split on a top-level separator (selector comma lists, `;` declaration
// lists), dropping empty pieces.
private string[] splitTop(string s, char sep)
{
    string[] res;
    size_t i = 0;
    while (i < s.length)
    {
        immutable p = topAt(s, i, sep);
        auto piece = strip(s[i .. p == npos ? s.length : p]);
        if (!piece.empty)
            res ~= piece;
        i = p == npos ? s.length : p + 1;
    }
    return res;
}

// -------------------------------------------------------------- XML text

/// Decode the character references sxml hands through untouched, plus
/// any numeric reference: the five XML built-ins and &#...; / &#x...;.
/// A `&` that starts nothing decodable is left as written.
string xmlUnescape(string s)
{
    if (!canFind(s, '&'))
        return s;

    auto acc = appender!string;
    size_t i = 0;
    while (i < s.length)
    {
        if (s[i] != '&')
        {
            acc.put(s[i++]);
            continue;
        }
        immutable semi = findFrom(s, i + 1, ';');
        if (semi == npos || semi - i > 10)
        {
            acc.put(s[i++]);
            continue;
        }
        auto ent = s[i + 1 .. semi];
        int cp = -1;
        switch (ent)
        {
        case "lt":   cp = '<'; break;
        case "gt":   cp = '>'; break;
        case "amp":  cp = '&'; break;
        case "quot": cp = '"'; break;
        case "apos": cp = '\''; break;
        default:
            if (ent.length > 2 && ent[0] == '#')
            {
                bool hex = ent[1] == 'x' || ent[1] == 'X';
                int base = hex ? 16 : 10;
                size_t j = hex ? 2 : 1;
                int num = 0;
                for (; j < ent.length; ++j)
                {
                    immutable d = hex ? hexVal(ent[j]) : (ent[j] >= '0' &&
                        ent[j] <= '9' ? ent[j] - '0' : -1);
                    if (d < 0)
                    {
                        num = -1;
                        break;
                    }
                    num = num * base + d;
                }
                cp = num;
            }
            break;
        }
        if (cp < 0)
        {
            acc.put(s[i++]);
            continue;
        }
        if (cp < 0x80)
            acc.put(cast(char) cp);
        else if (cp < 0x800)
        {
            acc.put(cast(char) (0xC0 | (cp >> 6)));
            acc.put(cast(char) (0x80 | (cp & 0x3F)));
        }
        else
        {
            acc.put(cast(char) (0xE0 | (cp >> 12)));
            acc.put(cast(char) (0x80 | ((cp >> 6) & 0x3F)));
            acc.put(cast(char) (0x80 | (cp & 0x3F)));
        }
        i = semi + 1;
    }
    return acc.data;
}

private int hexVal(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

// ------------------------------------------------------------------ tests

unittest
{
    // sxml keeps entity references raw, so the prepass decodes them.
    assert(xmlUnescape(`g &gt; rect`) == `g > rect`);
    assert(xmlUnescape(`a &lt; &quot;&apos;&amp;`) == `a < "'&`);
    assert(xmlUnescape(`&#62; &#x3E;`) == `> >`);
    assert(xmlUnescape(`a &(b`) == `a &(b`); // not a reference
}

unittest
{
    // Comments, at-rules, declaration grammar, !important.
    size_t order = 0;
    auto rules = parseSheet(`
        @import url(x.css);
        @font-face { font-family: FOO; src: url(a.ttf); }
        /* comment */ g /* x */ { fill: red /*y*/ ; stroke:blue !important }
        x { FiLl: oRaNgE }
    `, order);
    assert(rules.length == 2);
    assert(rules[0].props == ["fill", "stroke"]);
    assert(rules[0].vals == ["red", "blue"]);
    assert(!rules[0].imp[0] && rules[0].imp[1]);
    assert(rules[1].props[0] == "fill"); // property names lower-case
    assert(rules[1].vals[0] == "oRaNgE"); // values as written
}

unittest
{
    // Selector compilation: compounds, combinators, specificity.
    auto c = compileSelector(`#alpha * rect`);
    assert(!c.malformed && c.chain.length == 3);
    assert(c.spec == [1, 0, 1]); // `*` contributes nothing
    assert(!c.child[1] && !c.child[2]);

    c = compileSelector(`g#alpha`);
    assert(c.chain.length == 1 && c.chain[0].type == "g" &&
        c.chain[0].id == "alpha" && c.spec == [1, 0, 1]);

    c = compileSelector(`defs > rect`);
    assert(c.chain.length == 2 && c.child[1]);

    c = compileSelector(`*.test2`); // (groups split in parseSheet)
    assert(!c.malformed && c.chain[0].star && c.chain[0].classes == ["test2"]);
    c = compileSelector(`.a.b`);
    assert(c.chain.length == 1 && c.chain[0].classes.length == 2);
    c = compileSelector(`a > b c`);
    assert(c.chain.length == 3 && c.child[1] && !c.child[2]); // `>` binds one link

    c = compileSelector(`a + rect`);
    assert(c.malformed); // next phase; dropped until then
    c = compileSelector(`a:hover`);
    assert(!c.malformed && c.chain[0].never); // kept inert, not dropped
}

unittest
{
    // Matching against the arena, cascade order, and class lists.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink">
        <defs>
            <g id="alpha">
                <rect id="r1" class="testClass1" />
            </g>
        </defs>
        <g id="beta">
            <rect id="r2" class="a b" />
            <a><rect id="r3" class="testclass1" /></a>
        </g>
    </svg>`);

    size_t order = 0;
    auto rules = parseSheet(xmlUnescape(`
        rect { fill: black }                    /* 001 */
        defs &gt; rect { fill: green }          /* escaped text sheet */
        #alpha .testClass1 { fill: red }        /* 110 */
        g#beta > rect { fill: blue }            /* 111 */
        .b { visibility: hidden }               /* 010 */
        a:hover rect { fill: purple }           /* inert */
    `), order);
    assert(rules.length == 6); // the `:hover` rule stays, inert
    assert(rules[1].chain[0].type == "defs" && rules[1].child[1]); // escaped `&gt;` compiled as `>`

    auto parent = cssAncestry(doc.nodes);

    auto ms = cssCascade(doc.nodes, parent, doc.byId("r1"), rules);
    assert(ms.length == 2); // `rect` and `#alpha .testClass1` (r1's
                            // parent is the g, so the `defs >` rule misses)
    assert(ms[0].spec == [0, 0, 1]); // `rect` first: specificity 001
    assert(ms[1].spec == [1, 1, 0]); // winner last: #alpha .testClass1

    ms = cssCascade(doc.nodes, parent, doc.byId("r2"), rules);
    assert(ms.length == 3); // rect, .b, g#beta > rect
    assert(ms[$ - 1].spec == [1, 0, 2]); // two type names count twice

    // r3: class value is case-sensitive (testclass1 != .testClass1),
    // the `:hover` rule never matches, and only bare `rect` applies.
    ms = cssCascade(doc.nodes, parent, doc.byId("r3"), rules);
    assert(ms.length == 1 && ms[0].spec == [0, 0, 1]);

    // `use` clones match at the original position: r1 keeps matching
    // through #alpha no matter where it gets painted (it is in <defs>).
    assert(matches(doc.nodes, parent, doc.byId("r1"), rules[2]));
    assert(!matches(doc.nodes, parent, doc.byId("r1"), rules[1])); // `defs > rect` misses: parent is the g
}

unittest
{
    // collectStyles: style text from CDATA and escaped text alike, and
    // rules from a <style> before the first <svg> still participate.
    auto doc = parseSVG(`<style>g { fill: green }</style>
        <svg xmlns="http://www.w3.org/2000/svg"><defs>
        <style><![CDATA[rect { fill: blue }]]></style></defs></svg>`);
    auto rules = collectStyles(doc);
    assert(rules.length == 2);
    assert(rules[0].chain[0].type == "g" && rules[0].order == 0);
    assert(rules[1].chain[0].type == "rect" && rules[1].order == 1);
}
