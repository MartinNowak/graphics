module skia.core.bitmap;

import skia.core.rect : IRect;
import skia.core.color;


debug=PRINTF;
debug(PRINTF) import std.stdio : writeln, printf;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

enum Config {
  kNo_Config,         //!< bitmap has not been configured
  kA1_Config,         //!< 1-bit per pixel, (0 is transparent, 1 is opaque)
  kA8_Config,         //!< 8-bits per pixel, with only alpha specified (0 is transparent, 0xFF is opaque)
  kIndex8_Config,     //!< 8-bits per pixel, using SkColorTable to specify the colors
  kRGB_565_Config,    //!< 16-bits per pixel, (see SkColorPriv.h for packing)
  kARGB_4444_Config,  //!< 16-bits per pixel, (see SkColorPriv.h for packing)
  kARGB_8888_Config,  //!< 32-bits per pixel, (see SkColorPriv.h for packing)
  kRLE_Index8_Config,
};

/**
   Bitmap
 */
class Bitmap {
  @property uint width;
  @property uint height;
  Config config;
  ubyte flags;
  Color[] buffer;

  void SetConfig(Config config, uint width, uint height) {
    this.width = width;
    this.height = height;
    this.config = config;
    buffer.length = RowBytes(config, width) * height;
  }

  void* GetPixels() {
    assert(buffer);
    return buffer.ptr;
  }
}

size_t RowBytes(Config c, int width) {
  assert(width > 0);
  return c == Config.kA1_Config ? (width + 7) >> 3 : width * BytesPerPixel(c);
}

uint BytesPerPixel(Config c) {
  final switch (c) {
  case Config.kNo_Config, Config.kA1_Config:
    return 0;
  case Config.kRLE_Index8_Config, Config.kA8_Config, Config.kIndex8_Config:
    return 1;
  case Config.kRGB_565_Config, Config.kARGB_4444_Config:
    return 2;
  case Config.kARGB_8888_Config:
    return 4;
  }
}
