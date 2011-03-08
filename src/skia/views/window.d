module skia.views.window;

private {
  import skia.core.bitmap;
  import skia.core.canvas;
  import skia.core.color : White, Black;
  import skia.core.draw;
  import skia.core.paint : Paint;
  import skia.core.rect;
  import skia.core.point;
  import skia.core.size;
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
  IRect dirtyRegion;
public:
  this() {
    this.config = Bitmap.Config.ARGB_8888;
    this._flags.visible = true;
    this._flags.enabled = true;
    this._layout = new SquashChildrenZLayout();
  }

  bool update(IRect* updateArea = null)
  {
    if (!this.dirtyRegion.empty)
    {
      scope auto canvas = new Canvas(this.bitmap);
      canvas.clipRect(this.dirtyRegion);

      if (updateArea != null)
        *updateArea = this.dirtyRegion;
      this.dirtyRegion.setEmpty();

      this.draw(canvas);

      return true;
    }
    return false;
  }

  override void onDraw(Canvas canvas) {
    scope auto paint = new Paint(White);
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
  import xlib = xlib.xlib;
  import xutil = xlib.xutil;

  class OsWindow : Window {
    xlib.Display* dpy;
    xlib.Window win;
    xlib.XImage* ximage;
    xlib.GC gc;

    this(xlib.Display* dpy, xlib.Window win) {
      this.dpy = dpy;
      this.win = win;
    }

    ~this() {
      // crashes ??
      // xutil.XDestroyImage(ximage);
      xlib.XDestroyWindow(this.dpy, this.win);
    }

    bool windowProc(xlib.XEvent e) {
      switch(e.type) {
      case xlib.Expose:
        if (e.xexpose.count < 1) {
          auto area = IRect(IPoint(e.xexpose.x, e.xexpose.y),
                            ISize(e.xexpose.width, e.xexpose.height));
          this.doPaint(area);
        }
        break;

      case xlib.ButtonPress:
        this.onButtonPress(IPoint(e.xbutton.x, e.xbutton.y));
        break;

      case xlib.ButtonRelease:
        this.onButtonRelease(IPoint(e.xbutton.x, e.xbutton.y));
        break;

      case xlib.MotionNotify:
        this.onPointerMove(IPoint(e.xmotion.x, e.xmotion.y));
        break;

      case xlib.VisibilityNotify:
        break;

      case xlib.ConfigureNotify:
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
        xlib.XGCValues gcv;
        this.gc = xlib.XCreateGC(this.dpy, this.win, 0, &gcv);
      }
      XImageFromBitmap();
      xlib.XPutImage(this.dpy, this.win, this.gc, this.ximage, 0, 0, 0, 0,
                    this.ximage.width, this.ximage.height);
    }

    void XImageFromBitmap() {
      auto screen = xlib.XDefaultScreen(this.dpy);
      auto visual = xlib.XDefaultVisual(this.dpy, screen);
      auto depth = xlib.XDefaultDepth(this.dpy, screen);
      assert(depth == 24);
      this.ximage =xlib.XCreateImage(this.dpy, visual,
                                    depth, xlib.ZPixmap, 0, cast(byte*)bitmap.getBuffer().ptr,
                                           bitmap.width, bitmap.height, 8, 0);
      assert(this.ximage);
    }

    bool handleInval(in IRect area) {
      //! TODO: correctly join
      this.dirtyRegion = area;
      xlib.XClearArea(this.dpy, this.win, area.x, area.y,
                     area.width, area.height, xlib.Bool.True);
      return true;
    }

}

} // version FreeBSD
