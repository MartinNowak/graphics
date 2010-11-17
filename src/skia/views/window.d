module skia.views.window;

import skia.core.bitmap;
import skia.core.rect;

class Window{
public:
  this() {
    mConfig = Config.kARGB_8888_Config;
    mBitmap = new Bitmap();
  }

  const(Bitmap) getBitmap() const
  { return mBitmap; }
  
  bool Update(IRect updateArea = IRect())
  { return false; }

  void Resize(uint width, uint height)
  {
    mBitmap.SetConfig(mConfig, width, height);
  }

  void Resize(uint width, uint height, Config config)
  {
    mConfig = config;
    this.Resize(width, height);
  }

  void SetConfig(Config config)
  { 
    this.Resize(mBitmap.width, mBitmap.height, config);
  }

  Config mConfig;
  Bitmap mBitmap;
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
    Win.HWND mhWindow;

    this (Win.HWND hWindow) {
      mhWindow = hWindow;
    }

    Win.HWND getHWND() const { return mhWindow; }

    bool WindowProc(const ref MsgParameter m)
    {
      switch(m.mMsg) {
      case Win.WM_SIZE:
	this.Resize(m.mLParam & 0xFFFF, m.mLParam >> 16);
	break;
      case Win.WM_PAINT: {
	Win.PAINTSTRUCT ps;
	Win.HDC hdc = Win.BeginPaint(mhWindow, &ps);
	this.DoPaint(hdc);
	Win.EndPaint(mhWindow, &ps);
	return true;
      }
      default:
	break;
      }
      return false;
    }

    void DoPaint(Win.HDC hdc) {
      this.Update();
      BlitBitmap(mBitmap, hdc);
    }
  }

  Win.BITMAPINFO BitmapInfo(const ref Bitmap bitmap) {
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

  void BlitBitmap(ref Bitmap bitmap, Win.HDC hdc) {
    auto bmi = BitmapInfo(bitmap);
    Win.SetDIBitsToDevice(
      hdc,
      0, 0,
      bitmap.width, bitmap.height,
      0, 0,
      0, bitmap.height,
      bitmap.GetPixels(),
      &bmi,
      Win.DIB_RGB_COLORS);
  }

}

