module WinMain;

//import SkOsWindow;
private {
  import core.runtime;
  import std.algorithm : max;
  import Win = std.c.windows.windows;
  import std.conv;
  import std.stdio;
  import std.string : rjustify;

  import skia.core.color;
  import skia.core.point;
  import skia.core.size;
  import skia.views.window;
  import skia.views.view;
  import rectview;
  import circlesview;

  import quickcheck.unittestrunner;
}

private const auto KWindowClassName = "DawgWndClass";
private const auto KWindowTitle = "DawgWindow";

/*
extern (C) void gc_init();
extern (C) void gc_term();
extern (C) void _minit();
extern (C) void _moduleCtor();
extern (C) bool runModuleUnitTests();
*/
extern (C) bool rt_init(ExceptionHandler dg = null);
extern (C) bool rt_term(ExceptionHandler dg = null);

////////////////////////////////////////////////////////////////////////////////
// global window class instance
////////////////////////////////////////////////////////////////////////////////

OsWindow gWindow;

////////////////////////////////////////////////////////////////////////////////
// windows application entry
////////////////////////////////////////////////////////////////////////////////

extern (Windows)
int WinMain(Win.HINSTANCE hInstance, Win.HINSTANCE hPrevInstance,
	    Win.LPSTR lpCmdLine, int nCmdShow)
{
  void TraceException(Throwable e) {
    writeln("Exception while initializing runtime ", e);
  }
  // Win.AttachConsole(Win.ATTACH_PARENT_PROCESS);
  if (!rt_init(&TraceException))
    return 1;

  int result;
  try
  {
    InitWindow(hInstance, nCmdShow);
    result = RunMainLoop();
  }
  catch (Object o)
  {
    Win.MessageBoxA(null, cast(char*)o.toString(), "Error",
		    Win.MB_OK | Win.MB_ICONEXCLAMATION);
    result = 1;
  }

  if (!rt_term(&TraceException))
    return 1;
  return result;
}

////////////////////////////////////////////////////////////////////////////////
// window event handler
////////////////////////////////////////////////////////////////////////////////

extern (Windows)
int WindowProc(Win.HWND hWindow, uint msg,
	       Win.WPARAM wParam, Win.LPARAM lParam)
{
  switch (msg) {
  case Win.WM_DESTROY:
    Win.PostQuitMessage(0);
    break;
  default:
    if (gWindow && gWindow.windowProc(MsgParameter(hWindow, msg, wParam, lParam))) {
      return 0;
    } else {
      return Win.DefWindowProcA(hWindow, msg, wParam, lParam);
    }
  }
  return 0;
}


////////////////////////////////////////////////////////////////////////////////
// event loop
////////////////////////////////////////////////////////////////////////////////

int RunMainLoop()
{
  Win.MSG msg;

  while(Win.GetMessageA(&msg, cast(Win.HWND) null, 0, 0))
  {
    Win.TranslateMessage(&msg);
    Win.DispatchMessageA(&msg);
  }

  return cast(int)msg.wParam;;
}

////////////////////////////////////////////////////////////////////////////////
// window initialisation
////////////////////////////////////////////////////////////////////////////////

void InitWindow(Win.HINSTANCE hInstance, int nCmdShow)
{
  auto hWindow = MakeWindow(hInstance);
  gWindow = new OsWindow(hWindow);
  //  gWindow.attachChildTo!FrontPos(
  //    new RectView(IPoint(100, 100), ISize(200, 200), Orange));
  gWindow.attachChildTo!FrontPos(new CirclesView());

  Win.ShowWindow(hWindow, nCmdShow);
  Win.UpdateWindow(hWindow);
}

Win.HWND MakeWindow(Win.HINSTANCE hInstance)
{
  Win.WNDCLASSEXA wcex;

  wcex.cbClsExtra = 0;
  wcex.cbSize = Win.WNDCLASSEXA.sizeof;
  wcex.cbWndExtra = 0;
  wcex.hCursor = Win.LoadCursorA(cast(Win.HINSTANCE) null, Win.IDC_ARROW);
  wcex.hIcon = Win.LoadIconA(cast(Win.HINSTANCE) null, Win.IDI_APPLICATION);
  wcex.hIconSm = Win.LoadIconA(cast(Win.HINSTANCE) null, Win.IDI_APPLICATION);
  wcex.hInstance = hInstance;
  wcex.hbrBackground = cast(Win.HBRUSH)(Win.COLOR_WINDOW + 1);
  wcex.lpfnWndProc = &WindowProc;
  wcex.lpszClassName = KWindowClassName;
  wcex.lpszMenuName = null;
  wcex.style = 0;

  auto a = Win.RegisterClassExA(&wcex);
  assert(a);

  auto hWnd = Win.CreateWindowA(KWindowClassName, KWindowTitle,
				Win.WS_OVERLAPPEDWINDOW,
				Win.CW_USEDEFAULT, 0,
				Win.CW_USEDEFAULT, 0,
				null, null, // Parent, Menu
				hInstance, null);
  assert(hWnd);
  return hWnd;
}
