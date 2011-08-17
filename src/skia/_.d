module skia._;

public {
  import skia.core.canvas, skia.core.paint, skia.core.path;
}
import guip._; // to build guip

pragma(importpath, "guip=https://raw.github.com/dawgfoto/guip/master/src/guip");
pragma(importpath, "qcheck=https://raw.github.com/dawgfoto/qcheck/master/src/qcheck");
pragma(importpath, "freetype=https://raw.github.com/dawgfoto/bindings/master/freetype");
pragma(importpath, "fontconfig=https://raw.github.com/dawgfoto/bindings/master/fontconfig");

pragma(build, skia);
