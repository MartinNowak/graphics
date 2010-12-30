module skia.views.window;

private {
  import skia.core.bitmap;
  import skia.core.canvas;
  import skia.core.color : White, Black, WarmGray;
  import skia.core.draw;
  import skia.core.paint : Paint;
  import skia.core.rect;
  import skia.core.point;
  import skia.core.size;
  import skia.core.region;
  import skia.views.view;

  //debug=PRINTF;
  debug private import std.stdio : writeln, printf;
}

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

class Window : View
{
  @property Bitmap bitmap;
  Bitmap.Config config;
  Region dirtyRegion;
public:
  this() {
    this.config = Bitmap.Config.ARGB_8888;
    this.bitmap = new Bitmap();
    this._flags.visible = true;
    this._flags.enabled = true;
    this._layout = new SquashChildrenZLayout();
  }

  bool update(IRect* updateArea = null)
  {
    if (!this.dirtyRegion.empty)
    {
      scope auto canvas = new Canvas(this.bitmap);
      canvas.clipRegion(this.dirtyRegion);

      if (updateArea != null)
        *updateArea = this.dirtyRegion.bounds;
      this.dirtyRegion.setEmpty();

      this.draw(canvas);

      return true;
    }
    return false;
  }

  override void onDraw(Canvas canvas) {
    scope auto paint = new Paint(WarmGray);
    paint.antiAlias = false;
    canvas.drawPaint(paint);
  }

  void resize(uint width, uint height)
  {
      if (width != this.bitmap.width || height != this.bitmap.height) {
          this.bitmap.setConfig(this.config, width, height);
          this.setSize(width, height);
          this.dirtyRegion = IRect(width, height);
      }
  }

  void resize(uint width, uint height, Bitmap.Config config)
  {
    this.config = config;
    this.resize(width, height);
  }

  void setConfig(Bitmap.Config config)
  {
    this.resize(this.bitmap.width, this.bitmap.height, config);
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

version(FreeBSD)
{
  import X11 = X11.Xlib;
  import Xutil = X11.Xutil;

  class OsWindow : Window {
    X11.Display* dpy;
    X11.Window win;
    X11.XImage* ximage;
    X11.GC gc;

    this(X11.Display* dpy, X11.Window win) {
      this.dpy = dpy;
      this.win = win;
    }

    ~this() {
      // crashes ??
      // Xutil.XDestroyImage(ximage);
      X11.XDestroyWindow(this.dpy, this.win);
    }

    bool windowProc(X11.XEvent e) {
      switch(e.type) {
      case X11.Expose:
        if (e.xexpose.count < 1) {
          auto area = IRect(IPoint(e.xexpose.x, e.xexpose.y),
                            ISize(e.xexpose.width, e.xexpose.height));
          this.doPaint(area);
        }
        break;

      case X11.ButtonPress:
        this.onButtonPress(IPoint(e.xbutton.x, e.xbutton.y));
        break;

      case X11.ButtonRelease:
        this.onButtonRelease(IPoint(e.xbutton.x, e.xbutton.y));
        break;

      case X11.ConfigureNotify:
        this.resize(e.xconfigure.width, e.xconfigure.height);
        break;

      default:
        break;
      }
      return true;
    }

    void doPaint(in IRect rect) {
      this.update();
      blitBitmap();
    }

    void blitBitmap() {
      if (this.gc is null) {
        X11.XGCValues gcv;
        this.gc = X11.XCreateGC(this.dpy, this.win, 0, &gcv);
      }
      XImageFromBitmap();
      X11.XPutImage(this.dpy, this.win, this.gc, this.ximage, 0, 0, 0, 0,
                    this.ximage.width, this.ximage.height);
    }

    void XImageFromBitmap() {
      auto screen = X11.XDefaultScreen(this.dpy);
      auto visual = X11.XDefaultVisual(this.dpy, screen);
      auto depth = X11.XDefaultDepth(this.dpy, screen);
      assert(depth == 24);
      this.ximage =X11.XCreateImage(this.dpy, visual,
                                           depth, X11.ZPixmap, 0, cast(byte*)bitmap.buffer.ptr,
                                           bitmap.width, bitmap.height, 8, 0);
      assert(this.ximage);
    }
}

} // version FreeBSD
