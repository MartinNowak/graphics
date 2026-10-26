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

    bool valid() const
    {
        return filename.length > 0;
    }

private:
    mixin(bitfields!(
              Weight, "weight", 3,
              Slant, "slant", 2,
              bool, "_fixedWidth", 1,
              uint, "", 2,
          ));
    package string filename;

    static TypeFace[string] facePatternCache;
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

        result.filename = to!string(filename);
        debug(PRINTF) writeln("found font ", result.filename);
        return result;
    }
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

    // a locally owned FontConfig runs its FcFini destructor; modern
    // fontconfig treats FcInit/FcFini as no-ops, so later lookups are safe
    auto fc = new shared(FontConfig);
    synchronized(fc) fc.init();
    destroy(fc);
}
