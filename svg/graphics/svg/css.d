module graphics.svg.css;

// CSS styling (SVG 1.1 §6.2/§6.4): a style-sheet parser for the `<style>`
// elements of a document, compiled selectors, and a matcher that walks the
// parser arena (selectors match the *original* tree, so `use` clones match
// at their source position, as styling-css-* pins).
//
// Core: type/`*`/`.class`/`#id`/`[attr]` compounds with descendant, `>`
// and `+` combinators, `:first-child`/`:lang()`, the specificity triple,
// `!important`, and `@import` spliced in at the import point (CSS 2.1
// §6.4.3 sheet order). Constructs not yet applied (interaction
// pseudo-classes, @media, @font-face) compile away: the at-rules are
// skipped, and unsupported selectors keep their rules but never match.

import std.algorithm : canFind, find, sort;
import std.array : appender, join, split;
import std.ascii : isAlpha, isAlphaNum, isWhite, toLower;
import std.file : exists, readText;
import std.path : dirName;
import std.range;
import std.string : indexOf, strip;

import graphics.svg.parser : Document, Element, parseSVG;

/// One `[name]` / `[name op value]` condition. `op`: 0 = presence only,
/// '=' exact, '~' whitespace-word, '|' value or value-prefixed-by-a-hyphen,
/// 'n' an operator this engine does not apply yet (CSS3 ^= $= *= - the
/// condition, and hence the compound, never matches).
struct Attr
{
    string name;
    char   op;
    string val;
}

/// One compound simple selector: `circle`, `*`, `.test3`, `#alpha-2`,
/// `g#alpha`, `circle[cx="50"]`, `.test6:first-child`, `:lang(en)`, ...
/// `never` marks a construct that cannot match at runtime: the
/// interaction pseudo-classes and pseudo-elements (the compound is still
/// kept, and counted, so its specificity behaves the same).
struct Compound
{
    string     type;       // element name (case-sensitive: XML); "" = none
    bool       star;       // `*`: any element, contributes no specificity
    string     id;
    string[]   classes;
    Attr[]     attrs;
    bool       firstChild; // :first-child (no preceding element sibling)
    string     lang;       // :lang(tag), lower-cased; "" = no :lang
    bool       never;
}

/// A style rule: one compiled selector chain and its declarations. A
/// comma-separated selector group shares one declaration block; each
/// selector becomes its own Rule (sharing the declaration slices).
struct Rule
{
    Compound[] chain;
    char[]     comb;   // comb[i], i > 0: '>' child, '+' adjacent sibling,
                       // anything else descendant
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
/// caller threads through every <style> element so sheet order survives;
/// `baseDir` resolves this sheet's `@import` targets (nested imports
/// resolve against their own file), `depth` caps import recursion.
Rule[] parseSheet(string src, ref size_t order, string baseDir = "", int depth = 0)
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

        if (src[i] == '@')
        {
            // @import is the one at-rule whose content applies: its sheet
            // splices in right at the import point, so its rules cascade
            // exactly as if written there (CSS 2.1 §6.4.3). The rest are
            // noise: a statement ends at its top-level `;`, a block at
            // its matching `}` (@font-face; @media is skipped whole too).
            string url;
            immutable semi = topAt(src, i, ';');
            if (depth < 8 && parseImport(src[i .. $], url) && semi != npos)
            {
                immutable brace = findFrom(src, i, '{');
                if (brace == npos || semi < brace)
                {
                    rules ~= importRules(url, baseDir, order, depth);
                    i = semi + 1;
                    continue;
                }
            }
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
                rules ~= Rule(c.chain, c.comb, c.spec, order++,
                              props, vals, imps);
            }
        }
        i = close == npos ? src.length : close + 1;
    }
    return rules;
}

/// All rules of every <style> element, in document order; `baseDir` is
/// the document's directory for resolving `@import` targets. Style text
/// arrives as the parser wrote it: sxml hands `&gt;` through raw while
/// CDATA sections are literal, and the suite writes the same `>`
/// selector both ways (styling-css-04-f escapes, struct-use-10-f is
/// CDATA), so the text is XML-unescaped before it is tokenized.
Rule[] collectStyles(in Document doc, string baseDir = "")
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
                rules ~= parseSheet(xmlUnescape(src), order, baseDir);
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

/// sib[i] = arena index of node i's previous *element* sibling, -1 when
/// there is none (`+` and :first-child only count elements, CSS-wise).
/// Arena order is document DFS order, so one pass suffices.
int[] cssPrevSib(in immutable(Element)[] nodes, in int[] parent)
{
    int[] sib = new int[](nodes.length);
    int[] last = new int[](nodes.length); // per-parent: last element child
    sib[] = -1;
    last[] = -1;

    foreach (i, ref el; nodes)
    {
        immutable p = i ? parent[i] : -1;
        if (p < 0 || el.name.empty)
            continue;
        sib[i] = last[p];
        last[p] = cast(int) i;
    }
    return sib;
}

/// Does rule `r` apply to node `idx`? The last compound is matched
/// against the element itself and the chain is walked right-to-left:
/// `>` steps exactly one parent, `+` one previous sibling, and a space
/// any number of ancestors.
bool matches(in immutable(Element)[] nodes, in int[] parent, in int[] sib,
             size_t idx, ref const Rule r)
{
    int cur = cast(int) idx;
    if (!matchCompound(nodes, parent, sib, cur, r.chain[$ - 1]))
        return false;

    for (int i = cast(int) r.chain.length - 2; i >= 0; --i)
    {
        immutable ch = r.comb[i + 1];
        if (ch == '+' || ch == '>')
        {
            cur = ch == '+' ? sib[cur] : parent[cur];
            if (cur < 0 || !matchCompound(nodes, parent, sib, cur, r.chain[i]))
                return false;
        }
        else
        {
            while (true)
            {
                cur = parent[cur];
                if (cur < 0)
                    return false;
                if (matchCompound(nodes, parent, sib, cur, r.chain[i]))
                    break;
            }
        }
    }
    return true;
}

/// The rules matching node `idx` in cascade order: specificity triple
/// ascending, then sheet order (CSS 2.1 §6.4.3 - the winner is last).
const(Rule)[] cssCascade(in immutable(Element)[] nodes, in int[] parent,
                         in int[] sib, size_t idx, in Rule[] rules)
{
    const(Rule)[] ms;
    foreach (ref const r; rules)
        if (matches(nodes, parent, sib, idx, r))
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

private bool matchCompound(in immutable(Element)[] nodes, in int[] parent,
                           in int[] sib, int idx, ref const Compound c)
{
    ref immutable(Element) el = nodes[idx];
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
    foreach (ref a; c.attrs)
    {
        // Attribute names and values are XML: case-sensitive, and an
        // attribute with an empty value still counts as present.
        auto have = a.name in el.attrs;
        if (have is null)
            return false;
        if (a.op == 0)
            continue;
        if (a.op == 'n')
            return false; // CSS3 operator: the compound never matches
        if (a.op == '=')
        {
            if (*have != a.val)
                return false;
        }
        else if (a.op == '~')
        {
            if (!canFind(split(*have), a.val))
                return false;
        }
        else // '|': the value itself, or value + '-' subtag
        {
            if (*have != a.val &&
                !((*have).length > a.val.length &&
                    (*have)[0 .. a.val.length] == a.val &&
                    (*have)[a.val.length] == '-'))
                return false;
        }
    }
    if (c.firstChild && sib[idx] >= 0)
        return false;
    if (!c.lang.empty && !langMatches(nodes, parent, idx, c.lang))
        return false;
    return true;
}

// CSS 2.1 §6.4: an element's language is the value of the nearest
// lang/xml:lang attribute on it or any ancestor; :lang(tag) matches
// that tag or a hyphen-extended subtag of it, case-insensitively.
private bool langMatches(in immutable(Element)[] nodes, in int[] parent,
                         int idx, string want)
{
    for (int i = idx; i >= 0; i = parent[i])
    {
        string v = nodes[i].attrs.get("xml:lang", nodes[i].attrs.get("lang", ""));
        if (v.empty)
            continue;

        string low;
        foreach (ch; v)
            low ~= cast(char) toLower(ch);
        if (low == want)
            return true;
        return low.length > want.length && low[0 .. want.length] == want &&
            low[want.length] == '-';
    }
    return false;
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
    char[]     comb;
    int[3]     spec;
    bool       malformed;
}

private Chain compileSelector(string s)
{
    Chain cs;

    Compound c;
    bool open;       // `c` holds a compound not yet emitted
    char curComb;    // the combinator before the open compound
    char pendingComb; // a `>`/`+` seen after the last compound ended

    void emit()
    {
        cs.comb ~= curComb ? curComb : ' '; // ' ' also the index-0 placeholder
        curComb = 0;
        if (!c.id.empty)
            ++cs.spec[0];
        cs.spec[1] += cast(int) c.classes.length + cast(int) c.attrs.length;
        if (c.firstChild || !c.lang.empty)
            ++cs.spec[1]; // pseudo-classes count like .class (CSS 2.1)
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

        if (s[i] == '>' || s[i] == '+')
        {
            if (!open || pendingComb)
            {
                cs.malformed = true; // combinator with nothing on its left
                return cs;
            }
            pendingComb = s[i];
            ++i;
            continue;
        }

        if (!startsCompound(s[i]))
        {
            cs.malformed = true; // `~`, `|`, junk
            return cs;
        }

        if (open)
        {
            emit();
            curComb = pendingComb;
        }
        pendingComb = 0;

        if (!parseCompound(s, i, c))
        {
            cs.malformed = true;
            return cs;
        }
        open = true;
    }

    if (open && pendingComb)
    {
        cs.malformed = true; // dangling combinator
        return cs;
    }
    if (open)
        emit();
    return cs;
}

private bool startsCompound(char ch)
{
    return ch == '*' || ch == '#' || ch == '.' || ch == ':' ||
        ch == '[' || isIdentStart(ch);
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
        else if (ch == '[')
        {
            ++i;
            while (i < s.length && isWhite(s[i]))
                ++i;
            immutable start = i;
            while (i < s.length && isIdent(s[i]))
                ++i;
            if (i == start)
                return false;
            immutable name = s[start .. i];

            char op = 0;
            while (i < s.length && isWhite(s[i]))
                ++i;
            if (i < s.length && s[i] == '=')
                op = '=', ++i;
            else if (i + 1 < s.length && (s[i] == '~' || s[i] == '|' ||
                s[i] == '^' || s[i] == '$' || s[i] == '*') && s[i + 1] == '=')
            {
                op = s[i] == '~' ? '~' : s[i] == '|' ? '|' : 'n';
                i += 2;
            }

            string val;
            if (op)
            {
                while (i < s.length && isWhite(s[i]))
                    ++i;
                if (i < s.length && (s[i] == '"' || s[i] == '\''))
                {
                    immutable q = s[i++];
                    immutable v = i;
                    while (i < s.length && s[i] != q)
                        ++i;
                    if (i >= s.length)
                        return false; // unterminated string
                    val = s[v .. i];
                    ++i;
                }
                else
                {
                    immutable v = i;
                    while (i < s.length && isIdent(s[i]))
                        ++i;
                    if (i == v)
                        return false; // missing value
                    val = s[v .. i];
                }
                while (i < s.length && isWhite(s[i]))
                    ++i;
            }
            if (i >= s.length || s[i] != ']')
                return false;
            ++i;
            c.attrs ~= Attr(name, op, val);
        }
        else if (ch == ':')
        {
            if (++i < s.length && s[i] == ':') // pseudo-element: never
            {
                c.never = true;
                ++i;
                while (i < s.length && isIdent(s[i]))
                    ++i;
            }
            else
            {
                immutable start = i;
                while (i < s.length && isIdent(s[i]))
                    ++i;
                immutable name = s[start .. i];

                string arg;
                if (i < s.length && s[i] == '(')
                {
                    immutable start2 = ++i;
                    int depth = 1;
                    while (i < s.length && depth)
                    {
                        if (s[i] == '(')
                            ++depth;
                        else if (s[i] == ')')
                            --depth;
                        if (depth)
                            ++i;
                    }
                    if (depth)
                        return false; // unterminated
                    arg = strip(s[start2 .. i]);
                    ++i; // the ')'
                }

                if (name == "first-child")
                    c.firstChild = true;
                else if (name == "lang")
                {
                    if (arg.empty)
                        return false; // :lang needs its tag
                    foreach (ch2; arg)
                        c.lang ~= cast(char) toLower(ch2);
                }
                else
                    c.never = true; // :hover and friends stay inert
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

// Recognize `@import <url-token>|<string>` at the start of s; `url`
// comes back with any quotes gone. Trailing media queries are not the
// caller's problem: an `@import` that is not a plain statement fails
// the caller's `;`-before-`{` test and is skipped whole anyway.
private bool parseImport(string s, out string url)
{
    size_t i = 1;
    while (i < s.length && isIdent(s[i]))
        ++i;
    string kw;
    foreach (ch; s[1 .. i])
        kw ~= cast(char) toLower(ch);
    if (kw != "import")
        return false;
    while (i < s.length && isWhite(s[i]))
        ++i;

    string head;
    if (i + 4 <= s.length)
        foreach (ch; s[i .. i + 4])
            head ~= cast(char) toLower(ch);

    if (head == "url(")
    {
        i += 4;
        while (i < s.length && isWhite(s[i]))
            ++i;
        if (i < s.length && (s[i] == '"' || s[i] == '\''))
        {
            immutable q = s[i++];
            immutable start = i;
            while (i < s.length && s[i] != q)
                ++i;
            if (i >= s.length)
                return false; // unterminated string inside url(
            url = s[start .. i];
            ++i;
        }
        else
        {
            immutable start = i;
            while (i < s.length && s[i] != ')' && !isWhite(s[i]))
                ++i;
            url = s[start .. i];
        }
        while (i < s.length && s[i] != ')')
            ++i;
        if (i >= s.length)
            return false; // unterminated url(
        ++i;
    }
    else if (i < s.length && (s[i] == '"' || s[i] == '\''))
    {
        immutable q = s[i++];
        immutable start = i;
        while (i < s.length && s[i] != q)
            ++i;
        if (i >= s.length)
            return false;
        url = s[start .. i];
        ++i;
    }
    else
        return false;
    return !url.empty;
}

// Read and parse one imported sheet. Missing files and URL schemes
// contribute no rules; the target's own directory becomes the base
// for anything IT imports. resolveHref wants its base slash-terminated,
// and dirName() hands back one without.
private Rule[] importRules(string url, string baseDir, ref size_t order, int depth)
{
    immutable base = baseDir.length && baseDir[$ - 1] != '/' ? baseDir ~ "/" : baseDir;
    immutable path = resolveHref(base, url);
    if (path.empty || canFind(path, ':') || !path.exists)
        return null;
    return parseSheet(cast(string) readText(path), order, dirName(path) ~ "/", depth + 1);
}

// ------------------------------------------------------------------- URLs

// §5.1.2 URL plumbing, for <image> hrefs and @import targets alike:
// only plain filesystem paths are in play. resolveHref returns null
// for an empty href, a same-document fragment (an <image> cannot paint
// an inline element) and any URL scheme (http:, data:, ... - no
// network, and no file: pretence); otherwise the path joined onto
// `base` with ./.. segments collapsed.
string resolveHref(string base, string href)
{
    if (href.empty || href[0] == '#')
        return null;
    if (auto h = find(href, '#')) // drop the #fragment
        href = href[0 .. cast(ptrdiff_t)(h.ptr - href.ptr)];
    if (href.empty)
        return null;

    // letters [+alnum.-]* before a ':' = a URL scheme. Everything but
    // data: needs a network we don't have; data: (04-t embeds both a
    // JPEG and a PNG) is handled by loadSVGImage.
    immutable c = indexOf(href, ':');
    if (c > 0 && isAlpha(href[0]))
    {
        bool scheme = true;
        foreach (ch; href[1 .. c])
            if (!(isAlphaNum(ch) || ch == '+' || ch == '-' || ch == '.'))
                scheme = false;
        if (scheme)
            return href[0 .. c] == "data" ? href : null;
    }

    string path = href[0] == '/' ? href : (base.length ? base ~ href : href);
    string[] segs;
    foreach (seg; split(path, '/'))
    {
        if (seg.empty || seg == ".")
            continue;
        if (seg == "..")
        {
            if (segs.length && segs[$ - 1] != "..")
                segs.length = segs.length - 1;
            else if (path[0] != '/')
                segs ~= ".."; // escape of a relative base
            continue;
        }
        segs ~= seg;
    }
    string r = segs.join("/");
    if (path[0] == '/')
        r = "/" ~ r;
    return r.empty ? "." : r;
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
    assert(c.comb[1] == ' ' && c.comb[2] == ' ');

    c = compileSelector(`g#alpha`);
    assert(c.chain.length == 1 && c.chain[0].type == "g" &&
        c.chain[0].id == "alpha" && c.spec == [1, 0, 1]);

    c = compileSelector(`defs > rect`);
    assert(c.chain.length == 2 && c.comb[1] == '>');

    c = compileSelector(`*.test2`); // (groups split in parseSheet)
    assert(!c.malformed && c.chain[0].star && c.chain[0].classes == ["test2"]);
    c = compileSelector(`.a.b`);
    assert(c.chain.length == 1 && c.chain[0].classes.length == 2);
    c = compileSelector(`a > b c`);
    assert(c.chain.length == 3 && c.comb[1] == '>' && c.comb[2] == ' ');

    c = compileSelector(`a + rect`); // (styling-css-04-f `/* 101 */`-style chains)
    assert(!c.malformed && c.comb[1] == '+');
    c = compileSelector(`g#delta + g > rect + rect`);
    assert(!c.malformed && c.spec == [1, 0, 4] &&
        c.comb[1] == '+' && c.comb[2] == '>' && c.comb[3] == '+');
    c = compileSelector(`a:hover`);
    assert(!c.malformed && c.chain[0].never); // kept inert, not dropped
    c = compileSelector(`a + + b`);
    assert(c.malformed); // double combinator

    // Attribute conditions (unquoted values included), :first-child and
    // :lang; both pseudo-classes count like .class (CSS 2.1 §6.4.3,
    // even where the test's hand-written /* 102 */ comments disagree).
    c = compileSelector(`[id=testAttributeSelector]`);
    assert(!c.malformed && c.chain[0].attrs.length == 1 &&
        c.chain[0].attrs[0].name == "id" && c.chain[0].attrs[0].op == '=' &&
        c.chain[0].attrs[0].val == "testAttributeSelector" && c.spec == [0, 1, 0]);
    c = compileSelector(`circle[cx] .test8`);
    assert(!c.malformed && c.chain[0].attrs[0].op == 0);
    c = compileSelector(`circle[ foo ~= "warning1" ]`);
    assert(!c.malformed && c.chain[0].attrs[0].op == '~' &&
        c.chain[0].attrs[0].val == "warning1");
    c = compileSelector(`[lang |= en]`);
    assert(!c.malformed && c.chain[0].attrs[0].op == '|' &&
        c.chain[0].attrs[0].val == "en");
    c = compileSelector(`circle[foo^="x"]`);
    assert(!c.malformed && c.chain[0].attrs[0].op == 'n'); // inert condition
    c = compileSelector(`.test6:first-child`);
    assert(!c.malformed && c.chain[0].firstChild && c.spec == [0, 2, 0]);
    c = compileSelector(`#delta + g#epsilon * rect:first-child`);
    assert(!c.malformed && c.spec == [2, 1, 2]);
    c = compileSelector(`:lang(fr-ca)`);
    assert(!c.malformed && c.chain[0].lang == "fr-ca" && c.spec == [0, 1, 0]);
    c = compileSelector(`a:first-child`);
    assert(!c.malformed && !c.chain[0].never); // no longer a `never` pseudo
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
    assert(rules[1].chain[0].type == "defs" && rules[1].comb[1] == '>'); // escaped `&gt;` compiled as `>`

    auto parent = cssAncestry(doc.nodes);
    auto sib = cssPrevSib(doc.nodes, parent);

    auto ms = cssCascade(doc.nodes, parent, sib, doc.byId("r1"), rules);
    assert(ms.length == 2); // `rect` and `#alpha .testClass1` (r1's
                            // parent is the g, so the `defs >` rule misses)
    assert(ms[0].spec == [0, 0, 1]); // `rect` first: specificity 001
    assert(ms[1].spec == [1, 1, 0]); // winner last: #alpha .testClass1

    ms = cssCascade(doc.nodes, parent, sib, doc.byId("r2"), rules);
    assert(ms.length == 3); // rect, .b, g#beta > rect
    assert(ms[$ - 1].spec == [1, 0, 2]); // two type names count twice

    // r3: class value is case-sensitive (testclass1 != .testClass1),
    // the `:hover` rule never matches, and only bare `rect` applies.
    ms = cssCascade(doc.nodes, parent, sib, doc.byId("r3"), rules);
    assert(ms.length == 1 && ms[0].spec == [0, 0, 1]);

    // `use` clones match at the original position: r1 keeps matching
    // through #alpha no matter where it gets painted (it is in <defs>).
    assert(matches(doc.nodes, parent, sib, doc.byId("r1"), rules[2]));
    assert(!matches(doc.nodes, parent, sib, doc.byId("r1"), rules[1])); // `defs > rect` misses: parent is the g
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

unittest
{
    // 5b matching: `+` on the sibling map, attribute conditions,
    // :first-child, :lang() - the shapes pinned by struct-use-11-f,
    // styling-css-04-f, selector-types-*.css and styling-css-05-b.
    auto doc = parseSVG(`<svg xmlns="http://www.w3.org/2000/svg">
        <g id="sibs"><circle id="c1" cx="50"/><circle id="c2"/><rect id="q"/></g>
        <g id="fc"><text id="t1" xml:lang="en-GB">x</text><text id="t2" xml:lang="fr-ca">y</text></g>
        <path id="pa" foo="a warning1 b" lang="en"/>
    </svg>`);
    auto parent = cssAncestry(doc.nodes);
    auto sib = cssPrevSib(doc.nodes, parent);
    assert(sib[doc.byId("c1")] < 0 && sib[doc.byId("q")] == cast(int) doc.byId("c2"));

    size_t order = 0;
    auto rules = parseSheet(`
        circle + rect { fill: gold }      /* the sibling rule hits only #q */
        [id=missing] { fill: black }      /* unquoted value; matches nothing */
        circle[cx] { fill: blue }
        circle[cx="50"] { fill: red }
        [foo~="warning1"] { fill: orange }
        [lang|="en"] { stroke: silver }
        text:first-child { fill: teal }
        :lang(en) { stroke-width: 2 }
        :lang(fr) { stroke-dasharray: 4 }
    `, order);
    assert(rules.length == 9);

    auto ms = cssCascade(doc.nodes, parent, sib, doc.byId("q"), rules);
    assert(ms.length == 1 && ms[0].vals[0] == "gold");

    // c1: [cx] and [cx="50"] tie at 011, so sheet order decides - and
    // c2 (no cx at all) matches neither.
    ms = cssCascade(doc.nodes, parent, sib, doc.byId("c1"), rules);
    assert(ms.length == 2 && ms[$ - 1].vals[0] == "red");
    assert(cssCascade(doc.nodes, parent, sib, doc.byId("c2"), rules).empty);

    // t1 is #fc's first element child, t2 is not; :lang(fr) matches
    // fr-ca as a range prefix, :lang(en) matches en-GB likewise.
    ms = cssCascade(doc.nodes, parent, sib, doc.byId("t1"), rules);
    assert(ms.length == 2); // teal + stroke-width
    ms = cssCascade(doc.nodes, parent, sib, doc.byId("t2"), rules);
    assert(ms.length == 1 && ms[0].vals[0] == "4"); // :lang(fr) only

    ms = cssCascade(doc.nodes, parent, sib, doc.byId("pa"), rules);
    assert(ms.length == 3); // [foo~=], [lang|=], :lang(en) via `lang=`
}

unittest
{
    // @import splices the imported sheet AT the import point (sheet
    // order keeps the cascade right), nested imports resolve against
    // their own file, and a missing target contributes nothing (the
    // x.css above simply yielded no rules).
    import std.file : remove, write;
    enum poly = "css5b_poly_test.css"; // innermost: one rule
    enum mid = "css5b_mid_test.css";   // imports poly, then adds one
    write(poly, `polygon { fill: purple }`);
    write(mid, `@import "css5b_poly_test.css"; ellipse { fill: gold }`);
    scope (exit) remove(mid);
    scope (exit) remove(poly);

    size_t order = 0;
    auto rules = parseSheet(`
        rect { fill: red }
        @import url("css5b_mid_test.css");
        circle { fill: blue }
    `, order, ".");
    assert(rules.length == 4);
    assert(rules[0].chain[0].type == "rect" && rules[0].order == 0);
    assert(rules[1].chain[0].type == "polygon" && rules[1].order == 1);
    assert(rules[2].chain[0].type == "ellipse" && rules[2].order == 2);
    assert(rules[3].chain[0].type == "circle" && rules[3].order == 3);
}
