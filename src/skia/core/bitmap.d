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
   stub ColorTable
*/
class ColorTable
{
  enum
  {
    kColorsAreOpaque_Flag,
  }
  ubyte flags;
}

/**
   Bitmap
 */
class Bitmap {
  @property uint width;
  @property uint height;
  Config config;
  ubyte flags;
  ColorTable colorTable;
  Color[] buffer;

  void setConfig(Config config, uint width, uint height) {
    this.width = width;
    this.height = height;
    this.config = config;
    buffer.length = RowBytes(config, width) * height;
  }

  void* getPixels() {
    assert(buffer);
    return buffer.ptr;
  }

  @property void opaque(bool isOpaque) {
    if (isOpaque) {
      flags |= Flags.kImageIsOpaque_Flag;
    }
    else {
      flags &= ~Flags.kImageIsOpaque_Flag;
    }
  }

  @property bool opaque() const {
    final switch (this.config) {
        case Config.kNo_Config:
            return true;

        case Config.kA1_Config:
        case Config.kA8_Config:
        case Config.kARGB_4444_Config:
        case Config.kARGB_8888_Config:
            return (this.flags & Flags.kImageIsOpaque_Flag) != 0;

        case Config.kIndex8_Config:
        case Config.kRLE_Index8_Config: {
	  // if lockPixels failed, we may not have a ctable ptr
	  return this.colorTable &&
	    ((this.colorTable.flags
	     & ColorTable.kColorsAreOpaque_Flag) != 0);
	}

        case Config.kRGB_565_Config:
            return true;
    }
  }

  void eraseColor(Color c) {
    if (0 == this.width || 0 == this.height
	|| this.config == Config.kNo_Config
	|| this.config == Config.kIndex8_Config)
      return;
    
    assert(this.config == Config.kARGB_8888_Config);
    this.buffer[] = c;
    // this.notifyPixelChanged();
  }

private:
  
  enum Flags
  {
    kImageIsOpaque_Flag = 0x01,
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
