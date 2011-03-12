module skia.core.bitmap;

private {
  import std.range : outputRangeObject;

  import skia.core.color;
  import skia.core.rect;
  import guip.size;
}


debug=PRINTF;
debug(PRINTF) import std.stdio : writeln, printf;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

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
struct Bitmap {
  enum Config {
    NoConfig,   //!< bitmap has not been configured
    A1,         //!< 1-bit per pixel, (0 is transparent, 1 is opaque)
    A8,         //!< 8-bits per pixel, with only alpha specified (0 is
              //!< transparent, 0xFF is opaque)
    Index8,     //!< 8-bits per pixel, using SkColorTable to specify the colors
    RGB_565,    //!< 16-bits per pixel, (see SkColorPriv.h for packing)
    ARGB_4444,  //!< 16-bits per pixel, (see SkColorPriv.h for packing)
    ARGB_8888,  //!< 32-bits per pixel, (see SkColorPriv.h for packing)
    RLE_Index8,
  };

  @property uint width;
  @property uint height;
  @property ISize size() const {
    return ISize(this.width, this.height);
  }
  @property IRect bounds() const {
    return IRect(this.size);
  }

  Bitmap.Config config;
  ubyte flags;
  ColorTable colorTable;
  ubyte[] _buffer;

  this(Config config, uint width, uint height) {
    this.setConfig(config, width, height);
  }

  void setConfig(Bitmap.Config config, uint width, uint height) {
    this.width = width;
    this.height = height;
    this.config = config;
    this._buffer.length = width * height * BytesPerPixel(config);
  }

  const(T)[] getRangeConst(T=PMColor)(uint xStart, uint xEnd, uint y) const {
    return (cast(Bitmap)this).getRange!(T)(xStart, xEnd, y);
  }

  T[] getRange(T=PMColor)(uint xStart, uint xEnd, uint y) {
    assert(xEnd - xStart <= this.width,
           "start:" ~ to!string(xStart) ~ "end: "~ to!string(xEnd) ~ "width:"~to!string(this.width));
    assert(y <= this.height, to!string(y));
    size_t yOff = y * this.width;
    return this.getBuffer!T()[yOff + xStart .. yOff + xEnd];
  }

  T[] getBuffer(T=PMColor)() {
    return cast(T[])this._buffer;
  }

  auto getLine(uint y) {
    return this.getRange(0u, this.width, y);
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
        case Bitmap.Config.NoConfig:
            return true;

        case Bitmap.Config.A1:
        case Bitmap.Config.A8:
        case Bitmap.Config.ARGB_4444:
        case Bitmap.Config.ARGB_8888:
            return (this.flags & Flags.kImageIsOpaque_Flag) != 0;

        case Bitmap.Config.Index8:
        case Bitmap.Config.RLE_Index8: {
	  // if lockPixels failed, we may not have a ctable ptr
	  return this.colorTable &&
	    ((this.colorTable.flags
	     & ColorTable.kColorsAreOpaque_Flag) != 0);
	}

        case Bitmap.Config.RGB_565:
            return true;
    }
  }

  void eraseColor(PMColor c) {
    if (0 == this.width || 0 == this.height
	|| this.config == Bitmap.Config.NoConfig
	|| this.config == Bitmap.Config.Index8)
      return;

    assert(this.config == Bitmap.Config.ARGB_8888);
    this.getBuffer!PMColor()[] = c;
    // this.notifyPixelChanged();
  }

private:

  enum Flags
  {
    kImageIsOpaque_Flag = 0x01,
  }
}


size_t RowBytes(Bitmap.Config c, int width) {
  assert(width > 0);
  return c == Bitmap.Config.A1 ? (width + 7) >> 3 : width * BytesPerPixel(c);
}

uint BytesPerPixel(Bitmap.Config c) {
  final switch (c) {
  case Bitmap.Config.NoConfig, Bitmap.Config.A1:
    return 0;
  case Bitmap.Config.RLE_Index8, Bitmap.Config.A8, Bitmap.Config.Index8:
    return 1;
  case Bitmap.Config.RGB_565, Bitmap.Config.ARGB_4444:
    return 2;
  case Bitmap.Config.ARGB_8888:
    return 4;
  }
}

