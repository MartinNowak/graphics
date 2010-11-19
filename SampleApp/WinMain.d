module WinMain;
import Win = std.c.windows.windows;
import std.c.stdio;

//import SkOsWindow;
private import std.conv;
private import skia.views.window;
private import core.runtime;
private import std.string : rjustify;
private import std.algorithm : max;

private const auto KWindowClassName = "DawgWndClass";
private const auto KWindowTitle = "DawgWindow";

extern (C) void gc_init();
extern (C) void gc_term();
extern (C) void _minit();
extern (C) void _moduleCtor();
extern (C) bool runModuleUnitTests();

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
  int result;
  
  gc_init();
  _minit();

  try
  {
    _moduleCtor();
    core.runtime.Runtime.moduleUnitTester = &unittestrunner;
    runModuleUnitTests();
    InitWindow(hInstance, nCmdShow);
    result = RunMainLoop();
  }
  catch (Object o)
  {
    Win.MessageBoxA(null, cast(char *) o.toString(), "Error",
		    Win.MB_OK | Win.MB_ICONEXCLAMATION);
    result = 0;
  }

  gc_term();
  return result;
}


bool unittestrunner()
{
  size_t failed = 0;
  foreach( m; ModuleInfo )
  {
    if( m )
    {
      auto fp = m.unitTest;
      if( fp )
      {
	auto msg = "Unittest: "~m.name;
	try
	{
	  fp();
	  msg ~= " OK".rjustify(max(0, 79 - msg.length));
	}
	catch( Throwable e )
	{
	  msg ~= " FAILED".rjustify(max(0, 79 - msg.length))
	    ~ "\n" ~ e.toString;
	  failed++;
	}
	debug writeln(msg);
      }
    }
  }
  return failed == 0;
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
    if (gWindow && gWindow.WindowProc(MsgParameter(hWindow, msg, wParam, lParam))) {
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
