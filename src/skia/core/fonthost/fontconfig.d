module skia.core.fonthost.fontconfig;

import skia.core.typeface;
import std.conv, std.exception, std.string : toStringz;
import core.sync.mutex, core.atomic;
import fontconfig.fontconfig;

struct TypeFace {
  enum Style : ubyte {
    Normal = 0,
    Bold = (1<<0),
    Italic = (1<<1),
    // TODO: add more weight, slant options
    BoldItalic = Bold | Italic,
  }

  final @property Style style() const {
    return _style;
  }

  final @property bool fixedWidth() const {
    return _fixedWidth;
  }

  static TypeFace defaultFace(Style style) {
    return findFace(style);
  }
  static TypeFace createFromName(string familyName, Style style) {
    return findFace(familyName, style);
  }

private:
  Style _style;
  bool _fixedWidth;
  package string filename;
}

shared Mutex fcMtx;

void initFontConfig() {
  if (fcMtx is null) {
    auto mtx = new Mutex();
    mtx.lock();
    scope(exit) { mtx.unlock(); }
    if (cas(&fcMtx, cast(Mutex)null, mtx))
      FcInit();
  }
}


TypeFace findFace(Args...)(Args args) {
  initFontConfig();

  (cast(Mutex)fcMtx).lock();
  scope(exit) { (cast(Mutex)fcMtx).unlock(); }

  TypeFace result;
  FcPattern* pattern = FcPatternCreate();
  scope(exit) { FcPatternDestroy(pattern); }

  foreach(arg; args) {
    appendPattern(pattern, arg);
    static if (is(typeof(arg) == TypeFace.Style))
      result._style |= arg;
  }

  FcConfigSubstitute(null, pattern, FcMatchKind.Pattern);
  FcDefaultSubstitute(pattern);

  FcResult ignore;
  auto match = enforce(FcFontMatch(null, pattern, &ignore),
                       new Exception("No font found for pattern."));
  scope(exit) { FcPatternDestroy(match); }

  FcChar8* filename;
  if (FcPatternGetString(match, FC_FILE, 0, &filename) != FcResult.Match) {
    throw new Exception("No filename for found font.");
  }

  result.filename = to!string(filename);
  return result;
}

void appendPattern(FcPattern* pattern, TypeFace.Style style) {
  auto weight = (style & TypeFace.Style.Bold) ? FC_WEIGHT_BOLD : FC_WEIGHT_NORMAL;
  FcPatternAddInteger(pattern, FC_WEIGHT, weight);
  auto slant = (style & TypeFace.Style.Italic) ? FC_SLANT_ITALIC : FC_SLANT_ROMAN;
  FcPatternAddInteger(pattern, FC_SLANT, slant);
}

void appendPattern(FcPattern* pattern, string familyName) {
  FcPatternAddString(pattern, FC_FAMILY, toStringz(familyName));
}
