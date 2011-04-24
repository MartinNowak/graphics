module skia.core.fonthost._;

version (FreeBSD) {
  version = FreeType;
} else version (Linux) {
  version = FreeType;
} else version (Solaris) {
  version = FreeType;
} else version (Windows) {
  version = GDI;
} else version (OSX) {
  version = CoreText;
}

// match FreeType first so it can also be used on windows, osx
version (FreeType) {
  public import skia.core.fonthost.fontconfig;
  public import skia.core.fonthost.freetype;
} else version (GDI) {
  // TODO: gdi binding
  // public import skia.core.fonthost.gdi;
} else version(CoreText) {
  // TODO: coretext binding, atsui for 10.4 ?
  // public import skia.core.fonthost.coretext;
}
