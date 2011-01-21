module SampleApp.X11Main;

private {
  import std.stdio;
  import std.c.stdlib : exit;
  import X11 = X11.Xlib;

  import skia.views.view;
  import skia.views.window;

  // Set's default fpu exceptions on
  import skia.math.fpu;
  import SampleApp.bitmapview;
  import SampleApp.circlesview;
  import SampleApp.quadview;
  import SampleApp.cubicview;
  import SampleApp.sineview;
  import SampleApp.rectview;
  import SampleApp.textview;
  import qcheck.unittestrunner;
}

//debug=PRINTF;

////////////////////////////////////////////////////////////////////////////////
// global window class instance
////////////////////////////////////////////////////////////////////////////////

OsWindow gWindow;
X11.Atom gDeleteWindowAtom;
////////////////////////////////////////////////////////////////////////////////
// application entry
////////////////////////////////////////////////////////////////////////////////

int main() {
  int result;
  scope auto errorHandler = new ErrorHandler();
  auto dpy = InitWindow();
  RunMainLoop(dpy);
  DestroyWindow(dpy);
  return result;
}

////////////////////////////////////////////////////////////////////////////////
// event loop
////////////////////////////////////////////////////////////////////////////////

int RunMainLoop(X11.Display* dpy) {
  X11.XEvent e;

 loop: while(true) {
    X11.XNextEvent(dpy, &e);
    debug(PRINTF) writeln("EventType", e.type);

    switch (e.type) {
    case X11.ClientMessage:
      if(cast(X11.Atom)e.xclient.data.l[0] == gDeleteWindowAtom) {
        break loop;
      }
      break;

    default:
        if (gWindow) {
          if (!gWindow.windowProc(e))
            return 1;
        }
    }
  }
  return 0;
}

//------------------------------------------------------------------------------

X11.Display* InitWindow() {

  X11.Display* dpy = X11.XOpenDisplay(null);
  if(!dpy) {
    throw new Exception("ERROR: Could not open display\n");
  }
  auto win = MakeWindow(dpy);

  gWindow = new OsWindow(dpy, win);
  //  gWindow.attachChildTo!FrontPos(new SineView());
  //  gWindow.attachChildTo!FrontPos(new CirclesView());
  gWindow.attachChildTo!FrontPos(new RectView());
  //  gWindow.attachChildTo!FrontPos(new QuadView());
  gWindow.attachChildTo!FrontPos(new CubicView());
  gWindow.attachChildTo!FrontPos(new TextView());
  gWindow.attachChildTo!FrontPos(new BitmapView());

  X11.XMapWindow(dpy, win);
  return dpy;
}


//------------------------------------------------------------------------------

X11.Window MakeWindow(X11.Display* dpy) {
  auto scr = X11.XDefaultScreen(dpy);
  auto rootwin = X11.XRootWindow(dpy, scr);

  const uint SizeX = 500;
  const uint SizeY = 500;
  auto win = X11.XCreateSimpleWindow(dpy, rootwin, 1, 1, SizeX, SizeY, 0,
                                     X11.XBlackPixel(dpy, scr), X11.XBlackPixel(dpy, scr));
  X11.XStoreName(dpy, win, "MyWindow");

  gDeleteWindowAtom = X11.XInternAtom(dpy, "WM_DELETE_WINDOW", X11.Bool.False);
  X11.XSetWMProtocols(dpy, win, &gDeleteWindowAtom, 1); // [].length == 1

  enum WantedEvents =
    X11.ExposureMask |
    X11.ButtonPressMask |
    X11.ButtonReleaseMask |
    X11.KeyPressMask |
    X11.KeyReleaseMask |
    X11.StructureNotifyMask |
    X11.VisibilityChangeMask;

  X11.XSelectInput(dpy, win, WantedEvents);
  return win;
}


//------------------------------------------------------------------------------

void DestroyWindow(X11.Display* dpy) {
  delete gWindow;
  X11.XCloseDisplay(dpy);
}


////////////////////////////////////////////////////////////////////////////////

class ErrorHandler {
  static X11.XErrorHandler errorHandler;
  static X11.XIOErrorHandler ioErrorHandler;
  this() {
    errorHandler = X11.XSetErrorHandler(&XErrorHandler);
    ioErrorHandler = X11.XSetIOErrorHandler(&XIOErrorHandler);
  }

  ~this() {
    errorHandler = X11.XSetErrorHandler(errorHandler);
    ioErrorHandler = X11.XSetIOErrorHandler(ioErrorHandler);
    assert(errorHandler == &XErrorHandler);
    assert(ioErrorHandler == &XIOErrorHandler);
  }

  extern(C) static int XErrorHandler(X11.Display* dpy, X11.XErrorEvent* e) {
    writefln("XError code:%s", e.error_code);
    return ErrorHandler.errorHandler(dpy, e);
  }

  extern(C) static int XIOErrorHandler(X11.Display* dpy) {
    writefln("XIOError display:%s", dpy);
    auto res = ErrorHandler.ioErrorHandler(dpy);
    writefln("former routine ret:%s", res);
    exit(1);
    assert(0);
    //    return ErrorHandler.ioErrorHandler(dpy);
  }
}
