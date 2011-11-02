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
              Weight, "weight", 2,
              Slant, "slant", 2,
              bool, "_fixedWidth", 1,
              uint, "", 3,
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

enum int slantMap[TypeFace.Slant.max + 1] =
  [FC_SLANT_ROMAN, FC_SLANT_ITALIC, FC_SLANT_OBLIQUE];
enum int weightMap[TypeFace.Weight.max + 1] =
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
