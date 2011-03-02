module SampleApp.X11Main;

private {
  import std.stdio;
  import std.c.stdlib : exit;
  static import cstdio = core.stdc.stdio;
  import xlib = xlib.xlib;

  import skia.views.view;
  import skia.views.window;

  // Set's default fpu exceptions on
  //  import skia.math.fpu;
  import SampleApp.bitmapview;
  import SampleApp.circlesview;
  import SampleApp.quadview;
  import SampleApp.cubicview;
  import SampleApp.sineview;
  import SampleApp.rectview;
  import SampleApp.textview;
  import qcheck.unittestrunner;
}

// debug=PRINTF;

////////////////////////////////////////////////////////////////////////////////
// global window class instance
////////////////////////////////////////////////////////////////////////////////

OsWindow gWindow;
xlib.Atom[string] gAtoms;

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

int RunMainLoop(xlib.Display* dpy) {
  xlib.XEvent e;

 msg_loop: while(true) {
    xlib.XNextEvent(dpy, &e);
    debug(PRINTF) cstdio.fprintf(cstdio.stderr, "EventType %u\n", e.type);

    switch (e.type) {
    case xlib.ClientMessage:
      if (e.xclient.message_type == gAtoms["WM_PROTOCOLS"]) {
        if (e.xclient.data.l[0] == gAtoms["WM_DELETE_WINDOW"])
          break msg_loop;
        else if (e.xclient.data.l[0] == gAtoms["NET_WM_PING"]) {
          // TODO: xlib.XSendMessage(rootwindow ...)
        }
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

xlib.Display* InitWindow() {

  xlib.Display* dpy = xlib.XOpenDisplay(null);
  if(!dpy) {
    throw new Exception("ERROR: Could not open display\n");
  }
  auto win = MakeWindow(dpy);

  gWindow = new OsWindow(dpy, win);
  gWindow.attachChildTo!FrontPos(new SineView());
  // gWindow.attachChildTo!FrontPos(new CirclesView());
  gWindow.attachChildTo!FrontPos(new RectView());
  //  gWindow.attachChildTo!FrontPos(new QuadView());
  gWindow.attachChildTo!FrontPos(new CubicView());
  gWindow.attachChildTo!FrontPos(new TextView());
  gWindow.attachChildTo!FrontPos(new BitmapView());

  xlib.XMapWindow(dpy, win);
  return dpy;
}


//------------------------------------------------------------------------------

xlib.Atom getAtom(xlib.Display* dpy, string name) {
  auto atom = xlib.XInternAtom(dpy, name.ptr, xlib.Bool.False);
  debug(PRINTF) writefln("getAtom %s %s", name, atom);
  gAtoms[name] = atom;
  return atom;
}


//------------------------------------------------------------------------------

void registerAtoms(xlib.Display* dpy, xlib.Window win) {
  auto atoms = gAtoms.values;
  auto status = xlib.XSetWMProtocols(dpy, win, atoms.ptr, cast(int)atoms.length);
  assert(status == 1);
}


//------------------------------------------------------------------------------

xlib.Window MakeWindow(xlib.Display* dpy) {
  auto scr = xlib.XDefaultScreen(dpy);
  auto rootwin = xlib.XRootWindow(dpy, scr);

  const uint SizeX = 500;
  const uint SizeY = 500;
  auto win = xlib.XCreateSimpleWindow(dpy, rootwin, 1, 1, SizeX, SizeY, 0,
                                     xlib.XBlackPixel(dpy, scr), xlib.XBlackPixel(dpy, scr));
  xlib.XStoreName(dpy, win, "MyWindow");

  getAtom(dpy, "WM_PROTOCOLS");
  getAtom(dpy, "WM_DELETE_WINDOW");
  //  getAtom(dpy, "WM_TAKE_FOCUS");
  getAtom(dpy, "NET_WM_PING");
  registerAtoms(dpy, win);

  enum WantedEvents =
    xlib.ExposureMask |
    xlib.ButtonPressMask |
    xlib.ButtonReleaseMask |
    xlib.PointerMotionMask |
    //    xlib.PointerMotionHintMask |
    xlib.KeyPressMask |
    xlib.KeyReleaseMask |
    xlib.StructureNotifyMask |
    xlib.VisibilityChangeMask;

  xlib.XSelectInput(dpy, win, WantedEvents);
  return win;
}


//------------------------------------------------------------------------------

void DestroyWindow(xlib.Display* dpy) {
  xlib.XUnmapWindow(dpy, gWindow.win);
  delete gWindow;
  xlib.XCloseDisplay(dpy);
}


////////////////////////////////////////////////////////////////////////////////

class ErrorHandler {
  static xlib.XErrorHandler errorHandler;
  static xlib.XIOErrorHandler ioErrorHandler;
  this() {
    errorHandler = xlib.XSetErrorHandler(&XErrorHandler);
    ioErrorHandler = xlib.XSetIOErrorHandler(&XIOErrorHandler);
  }

  ~this() {
    errorHandler = xlib.XSetErrorHandler(errorHandler);
    ioErrorHandler = xlib.XSetIOErrorHandler(ioErrorHandler);
    assert(errorHandler == &XErrorHandler);
    assert(ioErrorHandler == &XIOErrorHandler);
  }

  extern(C) static int XErrorHandler(xlib.Display* dpy, xlib.XErrorEvent* e) {
    writefln("XError code:%s", e.error_code);
    return ErrorHandler.errorHandler(dpy, e);
  }

  extern(C) static int XIOErrorHandler(xlib.Display* dpy) {
    writefln("XIOError display:%s", dpy);
    auto res = ErrorHandler.ioErrorHandler(dpy);
    writefln("former routine ret:%s", res);
    exit(1);
    assert(0);
    //    return ErrorHandler.ioErrorHandler(dpy);
  }
}
