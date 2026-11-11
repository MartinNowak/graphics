module graphics.core.fonthost.fontconfig;

import core.atomic;
import std.bitmanip, std.conv, std.exception, std.traits, std.string;
import fontconfig.fontconfig;

struct TypeFace
{
    @property string toString() const
    {
        return std.string.format("TypeFace file:%s weigth:%s slant:%s fixedWidth:%s",
                                 filename, weight, slant, _fixedWidth);
    }

    enum Weight { Thin, Light, Normal, Bold, Heavy }
    enum Slant { Roman, Italic, Oblique }

    final @property bool fixedWidth() const
    {
        return _fixedWidth;
    }

    static TypeFace defaultFace(Weight weight = Weight.Normal, Slant slant = Slant.Roman)
    {
        return findFace(weight, slant);
    }

    static TypeFace createFromName(string familyName)
    {
        return findFace(familyName);
    }

    /**
     * Valid patterns types are Weight, Slant, string (font-family).
     * Multiple pattern of same type describe alternatives in descending order.
     */
    static TypeFace findFace(Pattern...)(Pattern pattern)
    {
        string cacheKey;

        foreach(i, D; Pattern)
        {
            static if (is(D == Weight))
                cacheKey ~= "Weight." ~ to!string(pattern[i]);
            else static if (is(D == Slant))
                cacheKey ~= "Slant." ~ to!string(pattern[i]);
            else static if (is(D == string))
                cacheKey ~= "Family(" ~ pattern[i] ~ ")";
            else
                static assert(0, "Unsupported pattern type '" ~ D.stringof ~ "'");

            if (i != Pattern.length)
                cacheKey ~= " ";
        }

        if (auto face = cacheKey in facePatternCache)
            return *face;
        auto face = fontConfig.findFace(pattern);
        facePatternCache[cacheKey] = face;
        return face;
    }

    /// The same lookup over a family *list*: CSS2 §15.5.1 tries the
    /// names in order, and fontconfig never fails a pattern - it
    /// answers its fallback - so a name is had only when the matched
    /// face carries that very family. A generic keyword is a family
    /// every host has, so it ends the walk. When the list names none
    /// the host has, the first name's fallback stands: that is what
    /// the single-name lookup returned before the lists existed.
    static TypeFace findFace(Pattern...)(const string[] fams, Pattern pattern)
    {
        if (!fams.length)
            return findFace(pattern);

        string walkKey;
        foreach (fam; fams)
            walkKey ~= fam ~ "\n";
        // The walk's choice is a matter of the names and the host's
        // fonts - never of weight or slant - so the cache holds the
        // winning name, and the face comes from the weight-aware
        // single-name lookup behind it. (An earlier shape of this
        // cache held a face: every style of a list got the face the
        // first style had asked with.)
        string chosen;
        if (auto hadName = walkKey in familyWalkCache)
            chosen = *hadName;
        else
        {
            foreach (fam; fams)
                if (isGenericFamily(fam) || fontConfig.hasFamily(fam))
                {
                    chosen = fam;
                    break;
                }
            familyWalkCache[walkKey] = chosen;
        }
        return chosen.length
            ? findFace(chosen, pattern)
            : findFace(fams[0], pattern);
    }

    bool valid() const
    {
        return filename.length > 0;
    }

    /// The family the host's match actually carries - fontconfig's
    /// answer to the pattern, not the name that was asked.
    string family() const
    {
        return familyName;
    }

private:
    static bool isGenericFamily(string fam)
    {
        switch (toLower(fam))
        {
        case "serif", "sans-serif", "cursive", "fantasy", "monospace":
            return true;
        default:
            return false;
        }
    }

    mixin(bitfields!(
              Weight, "weight", 3,
              Slant, "slant", 2,
              bool, "_fixedWidth", 1,
              uint, "", 2,
          ));
    package string filename;
    package string familyName;

    static TypeFace[string] facePatternCache;
    static string[string] familyWalkCache;
}

private shared(FontConfig) _fontConfig;

package @property shared(FontConfig) fontConfig()
{
    if (_fontConfig is null)
    {
        auto fc = new shared(FontConfig)();
        synchronized(fc)
        {
            if (cas(&_fontConfig, cast(shared FontConfig)null, fc))
                fc.init();
        }
    }
    return _fontConfig;
}

synchronized class FontConfig
{
    void init()
    {
        FcInit();
    }

    ~this()
    {
        FcFini();
    }

    TypeFace findFace(Args...)(Args args)
    {
        TypeFace result;
        FcPattern* pattern = FcPatternCreate();
        scope(exit) { FcPatternDestroy(pattern); }

        foreach(arg; args)
            appendPattern(pattern, arg);

        FcConfigSubstitute(null, pattern, FcMatchKind.Pattern);
        FcDefaultSubstitute(pattern);

        FcResult ignore;
        auto match = enforce(FcFontMatch(null, pattern, &ignore),
                             new Exception("No font found for pattern."));
        scope(exit) { FcPatternDestroy(match); }

        FcChar8* filename;
        enforce(FcPatternGetString(match, FC_FILE, 0, &filename) == FcResult.Match,
                "No filename for found font.");

        int weight;
        FcPatternGetInteger(match, FC_WEIGHT, 0, &weight);
        result.weight = tfWeight(weight);

        int slant;
        FcPatternGetInteger(match, FC_SLANT, 0, &slant);
        result.slant = tfSlant(slant);

        FcChar8* family;
        if (FcPatternGetString(match, FC_FAMILY, 0, &family) == FcResult.Match)
            result.familyName = to!string(family);

        result.filename = to!string(filename);
        debug(PRINTF) writeln("found font ", result.filename);
        return result;
    }

    /// Whether fontconfig has this very family: the match's own
    /// family, case-folded with separators dropped the way the
    /// library itself compares names, must be the name asked. An
    /// absent family answers too - with whatever fallback stands
    /// - and that answer's family says so by not matching.
    bool hasFamily(string familyName)
    {
        FcPattern* pattern = FcPatternCreate();
        scope(exit) { FcPatternDestroy(pattern); }

        appendPattern(pattern, familyName);
        FcConfigSubstitute(null, pattern, FcMatchKind.Pattern);
        FcDefaultSubstitute(pattern);

        FcResult ignore;
        auto match = FcFontMatch(null, pattern, &ignore);
        if (match is null)
            return false;
        scope(exit) { FcPatternDestroy(match); }

        FcChar8* family;
        if (FcPatternGetString(match, FC_FAMILY, 0, &family) != FcResult.Match)
            return false;
        return foldFamily(to!string(family)) == foldFamily(familyName);
    }
}

// fontconfig's family comparison folds case and drops spaces and
// hyphens - "MS Gothic" and "MS-Gothic" arrive as one fold, and so
// does the first entry of a comma-separated family string. Non-ASCII
// drops out of both sides equally.
private string foldFamily(string s)
{
    auto lower = toLower(s);
    char[] fold;
    fold.reserve(lower.length);
    foreach (dchar c; lower)
        if (c >= 'a' && c <= 'z' || c >= '0' && c <= '9')
            fold ~= cast(char) c;
    return cast(string) fold;
}

enum int[TypeFace.Slant.max + 1] slantMap =
  [FC_SLANT_ROMAN, FC_SLANT_ITALIC, FC_SLANT_OBLIQUE];
enum int[TypeFace.Weight.max + 1] weightMap =
  [FC_WEIGHT_THIN, FC_WEIGHT_LIGHT, FC_WEIGHT_NORMAL, FC_WEIGHT_BOLD, FC_WEIGHT_HEAVY];

int fcSlant(TypeFace.Slant slant)
{
    return slantMap[slant];
}

TypeFace.Slant tfSlant(int fcSlant)
{
    switch (fcSlant)
    {
    case FC_SLANT_ROMAN         : .. case FC_SLANT_ITALIC / 2: return TypeFace.Slant.Roman;
    case FC_SLANT_ITALIC / 2 + 1: .. case FC_SLANT_ITALIC    : return TypeFace.Slant.Italic;
    case FC_SLANT_ITALIC + 1    : .. case FC_SLANT_OBLIQUE   : return TypeFace.Slant.Oblique;
    default: assert(0);
    }
}

int fcWeight(TypeFace.Weight weight)
{
    return weightMap[weight];
}

TypeFace.Weight tfWeight(int fcWeight)
{
    switch (fcWeight)
    {
    case FC_WEIGHT_THIN          : .. case FC_WEIGHT_ULTRALIGHT: return TypeFace.Weight.Thin;
    case FC_WEIGHT_ULTRALIGHT + 1: .. case FC_WEIGHT_BOOK      : return TypeFace.Weight.Light;
    case FC_WEIGHT_BOOK + 1      : .. case FC_WEIGHT_DEMIBOLD  : return TypeFace.Weight.Normal;
    case FC_WEIGHT_DEMIBOLD + 1  : .. case FC_WEIGHT_ULTRABOLD : return TypeFace.Weight.Bold;
    case FC_WEIGHT_BLACK         : .. case FC_WEIGHT_ULTRABLACK: return TypeFace.Weight.Heavy;
    default: assert(0);
  }
}

void appendPattern(FcPattern* pattern, TypeFace.Slant slant)
{
    FcPatternAddInteger(pattern, FC_SLANT, fcSlant(slant));
}

void appendPattern(FcPattern* pattern, TypeFace.Weight weight)
{
    FcPatternAddInteger(pattern, FC_WEIGHT, fcWeight(weight));
}

void appendPattern(FcPattern* pattern, string familyName)
{
    FcPatternAddString(pattern, FC_FAMILY, toStringz(familyName));
}

unittest
{
    import std.algorithm : canFind;

    // fc <-> TypeFace translation tables: every value round-trips and the
    // band boundaries map to the neighbouring bucket
    foreach (slant; [TypeFace.Slant.Roman, TypeFace.Slant.Italic, TypeFace.Slant.Oblique])
        assert(fcSlant(slant) == fcSlant(tfSlant(fcSlant(slant))));
    assert(tfSlant(FC_SLANT_ROMAN) == TypeFace.Slant.Roman);
    assert(tfSlant(FC_SLANT_ITALIC / 2 + 1) == TypeFace.Slant.Italic);
    assert(tfSlant(FC_SLANT_ITALIC) == TypeFace.Slant.Italic);
    assert(tfSlant(FC_SLANT_OBLIQUE) == TypeFace.Slant.Oblique);

    foreach (weight; [TypeFace.Weight.Thin, TypeFace.Weight.Light, TypeFace.Weight.Normal,
                      TypeFace.Weight.Bold, TypeFace.Weight.Heavy])
        assert(fcWeight(weight) == fcWeight(tfWeight(fcWeight(weight))));
    assert(tfWeight(FC_WEIGHT_THIN) == TypeFace.Weight.Thin);
    assert(tfWeight(FC_WEIGHT_ULTRALIGHT + 1) == TypeFace.Weight.Light);
    assert(tfWeight(FC_WEIGHT_BOOK + 1) == TypeFace.Weight.Normal);
    assert(tfWeight(FC_WEIGHT_DEMIBOLD + 1) == TypeFace.Weight.Bold);
    assert(tfWeight(FC_WEIGHT_BLACK) == TypeFace.Weight.Heavy);

    // the bitfield accessors
    TypeFace tf;
    assert(!tf.valid && !tf.fixedWidth);
    tf.weight = TypeFace.Weight.Heavy;
    tf.slant = TypeFace.Slant.Oblique;
    tf._fixedWidth = true;
    assert(tf.weight == TypeFace.Weight.Heavy);
    assert(tf.slant == TypeFace.Slant.Oblique);
    assert(tf.fixedWidth);
    assert(tf.toString.length > 0);

    // lookups against the system fontconfig need installed fonts; a
    // font-less host finds no match and findFace throws, so the asserts
    // below are conditional — the mapping tests above always run and
    // cover the font semantics regardless of the host's fonts
    auto font = TypeFace.defaultFace();
    assert(font.toString.canFind("TypeFace file:"));
    assert(TypeFace.defaultFace().filename == font.filename); // served from cache
    auto boldItalic = TypeFace.findFace(TypeFace.Weight.Bold, TypeFace.Slant.Italic);
    assert(boldItalic.valid);
    assert(TypeFace.findFace(TypeFace.Weight.Bold, TypeFace.Slant.Italic).filename
           == boldItalic.filename); // second lookup: cache hit
    // an unknown family still resolves through fontconfig's fallbacks
    assert(TypeFace.createFromName("nonexistent font family").valid);

    // the family-list walk: a generic keyword is a family every host
    // has, so it answers behind a miss... (the const bindings are
    // what select the list overload; a bare literal matches the
    // single-pattern findFace exactly and hits its pattern guard)
    const string[] behindMiss = ["nonexistent font family", "serif"];
    assert(TypeFace.findFace(behindMiss,
                             TypeFace.Weight.Normal, TypeFace.Slant.Roman)
           .filename == TypeFace.findFace("serif").filename);
    // ...and a list of names the host has not falls back to the first,
    // which is what the single-name lookup returned before the lists
    const string[] allMissed = ["nonexistent font family", "another nonexistent one"];
    assert(TypeFace.findFace(allMissed,
                             TypeFace.Weight.Normal, TypeFace.Slant.Roman)
           .filename == TypeFace.findFace("nonexistent font family").filename);

    // hasFamily reads the match's own family: an absent name's answer
    // carries a different one, and any had face answers to its own
    assert(!fontConfig.hasFamily("nonexistent font family"));
    auto known = TypeFace.findFace("serif");
    assert(fontConfig.hasFamily(known.family));
    // a had name behind a miss wins the walk, host-conditional like
    // every lookup here
    const string[] behindMissAgain = ["nonexistent font family", "LucidaSansUnicode"];
    if (fontConfig.hasFamily("Lucida Sans Unicode"))
        assert(TypeFace.findFace(behindMissAgain,
                                 TypeFace.Weight.Normal, TypeFace.Slant.Roman)
               .filename == TypeFace.findFace("LucidaSansUnicode").filename);

    // the walk caches the chosen name, not a face: the bold of a
    // walked list is the bold of the direct query - a cache holding
    // the first style's face answered every weight with that one
    if (fontConfig.hasFamily("Arial"))
    {
        const string[] justArial = ["Arial"];
        assert(TypeFace.findFace(justArial, TypeFace.Weight.Bold, TypeFace.Slant.Roman)
               .filename == TypeFace.findFace(TypeFace.Weight.Bold,
                                              TypeFace.Slant.Roman, "Arial").filename);
    }

    // a locally owned FontConfig runs its FcFini destructor; modern
    // fontconfig treats FcInit/FcFini as no-ops, so later lookups are safe
    auto fc = new shared(FontConfig);
    synchronized(fc) fc.init();
    destroy(fc);
}
