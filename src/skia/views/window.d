module skia.views.window;

import Win = std.c.windows.windows;
import skia.core.bitmap;
import skia.core.canvas;
import skia.core.color : WarmGray;
import skia.core.draw;
import skia.core.paint : Paint;
import skia.core.rect;
import skia.core.region;
import skia.views.view;

//debug=PRINTF;
debug private import std.stdio : writeln, printf;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

class Window : View
{
  @property Bitmap bitmap;
  Config config;
  Region dirtyRegion;
public:
  this() {
    this.config = Config.ARGB_8888;
    this.bitmap = new Bitmap();
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  bool update(IRect* updateArea = null)
  {
    if (!this.dirtyRegion.empty)
    {
      scope auto canvas = new Canvas(this.bitmap);
      canvas.clipRegion(this.dirtyRegion);

      if (updateArea)
	*updateArea = this.dirtyRegion.bounds;
      this.dirtyRegion.setEmpty();

      this.draw(canvas);

      return true;
    }
    return false;
  }

  override void onDraw(Canvas canvas) {
    scope auto paint = new Paint(WarmGray);
    canvas.drawPaint(paint);
  }

  void resize(uint width, uint height)
  {
    this.bitmap.setConfig(this.config, width, height);
    this.setSize(width, height);
    this.dirtyRegion = IRect(width, height);
  }

  void resize(uint width, uint height, Config config)
  {
    this.config = config;
    this.resize(width, height);
  }

  void setConfig(Config config)
  {
    this.resize(this.bitmap.width, this.bitmap.height, this.config);
  }
};

version(Windows)
{
  import Win = std.c.windows.windows;


  struct MsgParameter
  {
    this(Win.HWND hWindow, uint msg,
	 Win.WPARAM wParam, Win.LPARAM lParam) {
      mhWindow = hWindow;
      mMsg = msg;
      mWParam = wParam;
      mLParam = lParam;
    }

    Win.HWND mhWindow;
    uint mMsg;
    Win.WPARAM mWParam;
    Win.LPARAM mLParam;
  };

  class OsWindow : Window {
    Win.HWND hWindow;

    this (Win.HWND hWindow) {
      this.hWindow = hWindow;
    }

    Win.HWND getHWND() const { return this.hWindow; }

    bool windowProc(const ref MsgParameter m)
    {
      switch(m.mMsg) {
      case Win.WM_SIZE:
	this.resize(m.mLParam & 0xFFFF, m.mLParam >> 16);
	break;
      case Win.WM_PAINT: {
	Win.PAINTSTRUCT ps;
	Win.HDC hdc = Win.BeginPaint(this.hWindow, &ps);
	this.doPaint(hdc);
	Win.EndPaint(this.hWindow, &ps);
	return true;
      }
      default:
	break;
      }
      return false;
    }

    void doPaint(Win.HDC hdc) {
      this.update();
      blitBitmap(this.bitmap, hdc);
    }
  }

  Win.BITMAPINFO BitmapInfo(in Bitmap bitmap) {
    Win.BITMAPINFO bmi;
    bmi.bmiHeader.biSize        = Win.BITMAPINFOHEADER.sizeof;
    bmi.bmiHeader.biWidth       = bitmap.width;
    bmi.bmiHeader.biHeight      = -bitmap.height;
    bmi.bmiHeader.biPlanes      = 1;
    bmi.bmiHeader.biBitCount    = 32;
    bmi.bmiHeader.biCompression = Win.BI_RGB;
    bmi.bmiHeader.biSizeImage   = 0;
    return bmi;
  }

  void blitBitmap(ref Bitmap bitmap, Win.HDC hdc) {
    auto bmi = BitmapInfo(bitmap);
    Win.SetDIBitsToDevice(
      hdc,
      0, 0,
      bitmap.width, bitmap.height,
      0, 0,
      0, bitmap.height,
      bitmap.getPixels(),
      &bmi,
      Win.DIB_RGB_COLORS);
  }

}

