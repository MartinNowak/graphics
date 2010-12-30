module X11.Xlib;

public import X11.X;

extern(C):

struct Display {}

alias size_t XID;
alias XID Window;
alias XID Drawable;
alias XID Pixmap;
alias XID Font;

enum Bool : int { False = 0, True = 1 }
static if (size_t.sizeof == 4) {
  alias int Long;
} else {
static assert(size_t.sizeof == 8);
  alias long Long;
}
alias size_t Time;
alias uint Atom;
alias int Status;
alias byte* XPointer;

/*
 * Data structure for setting graphics context.
 */
struct XGCValues {
  int _function;		/* logical operation */
  size_t plane_mask; /* plane mask */
  size_t foreground; /* foreground pixel */
  size_t background; /* background pixel */
  int line_width;		/* line width */
  int line_style;	 	/* LineSolid, LineOnOffDash, LineDoubleDash */
  int cap_style;	  	/* CapNotLast, CapButt,
				   CapRound, CapProjecting */
  int join_style;	 	/* JoinMiter, JoinRound, JoinBevel */
  int fill_style;	 	/* FillSolid, FillTiled,
				   FillStippled, FillOpaeueStippled */
  int fill_rule;	  	/* EvenOddRule, WindingRule */
  int arc_mode;		/* ArcChord, ArcPieSlice */
  Pixmap tile;		/* tile pixmap for tiling operations */
  Pixmap stipple;		/* stipple 1 plane pixmap for stipping */
  int ts_x_origin;	/* offset for tile or stipple operations */
  int ts_y_origin;
  Font font;	        /* default text font for text operations */
  int subwindow_mode;     /* ClipByChildren, IncludeInferiors */
  Bool graphics_exposures;/* boolean, should exposures be generated */
  int clip_x_origin;	/* origin for clipping */
  int clip_y_origin;
  Pixmap clip_mask;	/* bitmap clipping; other calls for rects */
  int dash_offset;	/* patterned/dashed line information */
  byte dashes;
};

/*
 * Data structure for "image" data, used by image manipulation routines.
 */
struct XImage {
  int width, height;		/* size of image */
  int xoffset;		/* number of pixels offset in X direction */
  int format;			/* XYBitmap, XYPixmap, ZPixmap */
  byte* data;			/* pointer to image data */
  int byte_order;		/* data byte order, LSBFirst, MSBFirst */
  int bitmap_unit;		/* quant. of scanline 8, 16, 32 */
  int bitmap_bit_order;	/* LSBFirst, MSBFirst */
  int bitmap_pad;		/* 8, 16, 32 either XY or ZPixmap */
  int depth;			/* depth of image */
  int bytes_per_line;		/* accelarator to next line */
  int bits_per_pixel;		/* bits per pixel (ZPixmap) */
  size_t red_mask;	/* bits in z arrangment */
  size_t green_mask;
  size_t blue_mask;
  XPointer obdata;		/* hook for the object routines to hang on */
  struct funcs {		/* image manipulation routines */
    XImage* function(Display*, Visual*, uint depth,  int format,
                     int offset, byte* data, uint width, uint height, int bitmap_pad,
                     int bytes_per_line) create_image;
    int function(XImage*) destroy_image;
    size_t function(XImage*, int, int) get_pixel;
    int function(XImage*, int, int, size_t) put_pixel;
    XImage* function(XImage*, int, int, uint, uint) sub_image;
    int function(XImage *, Long) add_pixel;
  };
  funcs f;
};

struct XExposeEvent {
  int type;
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display* display;	/* Display the event was read from */
  Window window;
  int x, y;
  int width, height;
  int count;		/* if non-zero, at least this many more */
};

struct XVisibilityEvent {
  int type;
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display *display;	/* Display the event was read from */
  Window window;
  int state;		/* Visibility state */
};

struct XButtonEvent {
  int type;		/* of event */
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display *display;	/* Display the event was read from */
  Window window;	        /* "event" window it is reported relative to */
  Window root;	        /* root window that the event occurred on */
  Window subwindow;	/* child window */
  Time time;		/* milliseconds */
  int x, y;		/* pointer x, y coordinates in event window */
  int x_root, y_root;	/* coordinates relative to root */
  uint state;	/* key or button mask */
  uint button;	/* detail */
  Bool same_screen;	/* same screen flag */
};

struct XKeyEvent {
  int type;		/* of event */
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display *display;	/* Display the event was read from */
  Window window;	        /* "event" window it is reported relative to */
  Window root;	        /* root window that the event occurred on */
  Window subwindow;	/* child window */
  Time time;		/* milliseconds */
  int x, y;		/* pointer x, y coordinates in event window */
  int x_root, y_root;	/* coordinates relative to root */
  uint state;	/* key or button mask */
  uint keycode;	/* detail */
  Bool same_screen;	/* same screen flag */
};

struct XResizeRequestEvent {
  int type;
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display* display;	/* Display the event was read from */
  Window window;
  int width, height;
};

struct XConfigureEvent {
  int type;
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display *display;	/* Display the event was read from */
  Window event;
  Window window;
  int x, y;
  int width, height;
  int border_width;
  Window above;
  Bool override_redirect;
};

struct XClientMessageEvent {
  int type;
  size_t serial;	/* # of last request processed by server */
  Bool send_event;	/* true if this came from a SendEvent request */
  Display *display;	/* Display the event was read from */
  Window window;
  Atom message_type;
  int format;
  union _data {
    byte b[20];
    short s[10];
    Long l[5];
  };
  _data data;
};

struct XErrorEvent {
  int type;
  Display *display;	/* Display the event was read from */
  XID resourceid;		/* resource id */
  size_t serial;	/* serial number of failed request */
  ubyte error_code;	/* error code of failed request */
  ubyte request_code;	/* Major op-code of failed request */
  ubyte minor_code;	/* Minor op-code of failed request */
};

union XEvent {
  int type;
  //XAnyEvent xany;
  XKeyEvent xkey;
  XButtonEvent xbutton;
  //XMotionEvent xmotion;
  //XCrossingEvent xcrossing;
  //XFocusChangeEvent xfocus;
  XExposeEvent xexpose;
  //XGraphicsExposeEvent xgraphicsexpose;
  //XNoExposeEvent xnoexpose;
  XVisibilityEvent xvisibility;
  //XCreateWindowEvent xcreatewindow;
  //XDestroyWindowEvent xdestroywindow;
  //XUnmapEvent xunmap;
  //XMapEvent xmap;
  //XMapRequestEvent xmaprequest;
  //XReparentEvent xreparent;
  XConfigureEvent xconfigure;
  //XGravityEvent xgravity;
  //XResizeRequestEvent xresizerequest;
  //XConfigureRequestEvent xconfigurerequest;
  //XCirculateEvent xcirculate;
  //XCirculateRequestEvent xcirculaterequest;
  //XPropertyEvent xproperty;
  //XSelectionClearEvent xselectionclear;
  //XSelectionRequestEvent xselectionrequest;
  //XSelectionEvent xselection;
  //XColormapEvent xcolormap;
  XClientMessageEvent xclient;
  //XMappingEvent xmapping;
  XErrorEvent xerror;
  //XKeymapEvent xkeymap;
  //XGenericEvent xgeneric;
  //XGenericEventCookie xcookie;
  Long pad[24];
};


struct _XPrivate {}
struct _XrmHashBucketRec {}
struct XExtData {}

struct _XDisplay
{
  XExtData *ext_data;	/* hook for extension to hang data */
  _XPrivate *private1;
  int fd;			/* Network socket. */
  int private2;
  int proto_major_version;/* major version of server's X protocol */
  int proto_minor_version;/* minor version of servers X protocol */
  char *vendor;		/* vendor of the server hardware */
  XID private3;
  XID private4;
  XID private5;
  int private6;
  alias XID function(_XDisplay*) resource_alloc_func;
  resource_alloc_func resource_alloc;
  int byte_order;		/* screen byte order, LSBFirst, MSBFirst */
  int bitmap_unit;	/* padding and data requirements */
  int bitmap_pad;		/* padding requirements on bitmaps */
  int bitmap_bit_order;	/* LeastSignificant or MostSignificant */
  int nformats;		/* number of pixmap formats in list */
  ScreenFormat *pixmap_format;	/* pixmap format list */
  int private8;
  int release;		/* release of the server */
  _XPrivate* private9;
  _XPrivate* private10;
  int qlen;		/* Length of input event queue */
  size_t last_request_read; /* seq number of last event read */
  size_t request;	/* sequence number of last request. */
  XPointer private11;
  XPointer private12;
  XPointer private13;
  XPointer private14;
  uint max_request_size; /* maximum number 32 bit words in request*/
  _XrmHashBucketRec *db;
  alias int function(_XDisplay*) private15_func;
  private15_func private15;
  char *display_name;	/* "host:display" string used on this connect*/
  int default_screen;	/* default screen for operations */
  int nscreens;		/* number of screens on this server*/
  Screen *screens;	/* pointer to list of screens */
  size_t motion_buffer;	/* size of motion buffer */
  size_t private16;
  int min_keycode;	/* minimum defined keycode */
  int max_keycode;	/* maximum defined keycode */
  XPointer private17;
  XPointer private18;
  int private19;
  char *xdefaults;	/* contents of defaults from server */
}
alias _XDisplay* _XPrivDisplay;

struct ScreenFormat{
  XExtData *ext_data;	/* hook for extension to hang data */
  int depth;		/* depth of this image format */
  int bits_per_pixel;	/* bits/pixel at this depth */
  int scanline_pad;	/* scanline must padded to this multiple */
};

struct Depth {
  int depth;		/* this depth (Z) of the depth */
  int nvisuals;		/* number of Visual types at this depth */
  Visual *visuals;	/* list of visuals possible at this depth */
};

alias size_t VisualID;

struct Visual {
  XExtData *ext_data;	/* hook for extension to hang data */
  VisualID visualid;	/* visual id of this visual */
  int c_class;		/* class of screen (monochrome, etc.) */
  size_t red_mask, green_mask, blue_mask;	/* mask values */
  int bits_per_rgb;	/* log base 2 of distinct color values */
  int map_entries;	/* color map entries */
};

alias XID GContext;

struct _XGC {};
alias _XGC* GC;
alias XID Colormap;

struct Screen {
  XExtData *ext_data;	/* hook for extension to hang data */
  _XDisplay *display;/* back pointer to display structure */
  Window root;		/* Root window id. */
  int width, height;	/* width and height of screen */
  int mwidth, mheight;	/* width and height of  in millimeters */
  int ndepths;		/* number of depths possible */
  Depth *depths;		/* list of allowable depths on the screen */
  int root_depth;		/* bits per pixel */
  Visual *root_visual;	/* root visual */
  GC default_gc;		/* GC for the root root visual */
  Colormap cmap;		/* default color map */
  size_t white_pixel;
  size_t black_pixel;	/* White and Black pixel values */
  int max_maps, min_maps;	/* max and min color maps */
  int backing_store;	/* Never, WhenMapped, Always */
  Bool save_unders;
  long root_input_mask;	/* initial root input mask */
};


int XDefaultDepth(Display*, int screen);
int XDefaultDepthOfScreen(Screen*);
int XDefaultScreen(Display* dpy);

Screen* XScreenOfDisplay(Display* dpy, int scr);
Window XRootWindow(Display* dpy, int scr);
size_t XBlackPixel(Display* dpy, int scr);
size_t XWhitePixel(Display* dpy, int scr);
Visual* XDefaultVisual(Display* dpy, int scr);

////////////////////////////////////////////////////////////////////////////////

XErrorHandler XSetErrorHandler (XErrorHandler);
alias int function(Display*, XErrorEvent*) XErrorHandler;

XIOErrorHandler XSetIOErrorHandler (XIOErrorHandler);
alias int function(Display*) XIOErrorHandler;

Display* XOpenDisplay(const(char*) display_name);
void XDestroyWindow(Display* display, Window win);

Atom XInternAtom(Display*, const(char*), Bool);

GC XCreateGC(Display*, Drawable, size_t valuemask, XGCValues*);

Window XCreateSimpleWindow(
  Display*		/* display */,
  Window		/* parent */,
  int			/* x */,
  int			/* y */,
  uint	/* width */,
  uint	/* height */,
  uint	/* border_width */,
  size_t	/* border */,
  size_t	/* background */
);

int XStoreName(
  Display*		/* display */,
  Window		/* w */,
  const(char*)	/* window_name */
);
int XSelectInput(
  Display*		/* display */,
  Window		/* w */,
  long		/* event_mask */
);

int XMapWindow(
  Display*		/* display */,
  Window		/* w */
);

int XNextEvent(
  Display*		/* display */,
  XEvent*		/* event_return */
);

int XCloseDisplay(
  Display*		/* display */
);

void XFlushGC(Display*, GC);
void XLockDisplay(Display*);
void XUnlockDisplay(Display*);

////////////////////////////////////////////////////////////////////////////////

Status XSetWMProtocols(Display*, Window, Atom*, int count);

Status XInitImage(XImage* image);
XImage* XCreateImage(Display* display, Visual* visual, uint depth, int format, int offset,
                    byte* data, uint width, uint height, int bitmap_pad, int bytes_per_line);
int XPutImage(Display*, Drawable, GC, XImage*,
              int src_x, int src_y, int dest_x, int dest_y, uint width, uint height);

int XClearArea(
  Display*		/* display */,
  Window		/* w */,
  int			/* x */,
  int			/* y */,
  uint	/* width */,
  uint	/* height */,
  Bool		/* exposures */
);

int XClearWindow(
  Display*		/* display */,
  Window		/* w */
);


/*****************************************************************
 * RESERVED RESOURCE AND CONSTANT DEFINITIONS
 *****************************************************************/

enum None =                 0;	/* universal null resource or null atom */

enum ParentRelative =       1;	/* background pixmap in CreateWindow
				    and ChangeWindowAttributes */

enum CopyFromParent =       0;	/* border pixmap in CreateWindow
				       and ChangeWindowAttributes
				   special VisualID and special window
				       class passed to CreateWindow */

enum PointerWindow =        0;	/* destination window in SendEvent */
enum InputFocus =           1;	/* destination window in SendEvent */

enum PointerRoot =          1;	/* focus window in SetInputFocus */

enum AnyPropertyType =      0;	/* special Atom, passed to GetProperty */

enum AnyKey =		    0;	/* special Key Code, passed to GrabKey */

enum AnyButton =            0;	/* special Button Code, passed to GrabButton */

enum AllTemporary =         0;	/* special Resource ID passed to KillClient */

enum CurrentTime =          0;	/* special Time */

enum NoSymbol =	     0;	/* special KeySym */

/*****************************************************************
 * EVENT DEFINITIONS
 *****************************************************************/

/* Input Event Masks. Used as event-mask window attribute and as arguments
   to Grab requests.  Not to be confused with event names.  */

enum NoEventMask =			0;
enum KeyPressMask =			(1<<0);
enum KeyReleaseMask =			(1<<1);
enum ButtonPressMask =			(1<<2);
enum ButtonReleaseMask =		(1<<3);
enum EnterWindowMask =			(1<<4);
enum LeaveWindowMask =			(1<<5);
enum PointerMotionMask =		(1<<6);
enum PointerMotionHintMask =		(1<<7);
enum Button1MotionMask =		(1<<8);
enum Button2MotionMask =		(1<<9);
enum Button3MotionMask =		(1<<10);
enum Button4MotionMask =		(1<<11);
enum Button5MotionMask =		(1<<12);
enum ButtonMotionMask =		        (1<<13);
enum KeymapStateMask =			(1<<14);
enum ExposureMask =			(1<<15);
enum VisibilityChangeMask =		(1<<16);
enum StructureNotifyMask =		(1<<17);
enum ResizeRedirectMask =		(1<<18);
enum SubstructureNotifyMask =		(1<<19);
enum SubstructureRedirectMask =	        (1<<20);
enum FocusChangeMask =			(1<<21);
enum PropertyChangeMask =		(1<<22);
enum ColormapChangeMask =		(1<<23);
enum OwnerGrabButtonMask =		(1<<24);

/* Event names.  Used in "type" field in XEvent structures.  Not to be
confused with event masks above.  They start from 2 because 0 and 1
are reserved in the protocol for errors and replies. */

enum KeyPress =		        2;
enum KeyRelease =		3;
enum ButtonPress =		4;
enum ButtonRelease =		5;
enum MotionNotify =		6;
enum EnterNotify =		7;
enum LeaveNotify =		8;
enum FocusIn =			9;
enum FocusOut =		10;
enum KeymapNotify =		11;
enum Expose =			12;
enum GraphicsExpose =		13;
enum NoExpose =		14;
enum VisibilityNotify =	15;
enum CreateNotify =		16;
enum DestroyNotify =		17;
enum UnmapNotify =		18;
enum MapNotify =		19;
enum MapRequest =		20;
enum ReparentNotify =		21;
enum ConfigureNotify =		22;
enum ConfigureRequest =	23;
enum GravityNotify =		24;
enum ResizeRequest =		25;
enum CirculateNotify =		26;
enum CirculateRequest =	27;
enum PropertyNotify =		28;
enum SelectionClear =		29;
enum SelectionRequest =	30;
enum SelectionNotify =		31;
enum ColormapNotify =		32;
enum ClientMessage =		33;
enum MappingNotify =		34;
enum GenericEvent =		35;
enum LASTEvent =		36;	/* must be bigger than any event # */


/* Key masks. Used as modifiers to GrabButton and GrabKey, results of QueryPointer,
   state in various key-, mouse-, and button-related events. */

enum ShiftMask =		(1<<0);
enum LockMask =		(1<<1);
enum ControlMask =		(1<<2);
enum Mod1Mask =		(1<<3);
enum Mod2Mask =		(1<<4);
enum Mod3Mask =		(1<<5);
enum Mod4Mask =		(1<<6);
enum Mod5Mask =		(1<<7);

/* modifier names.  Used to build a SetModifierMapping request or
   to read a GetModifierMapping request.  These correspond to the
   masks defined above. */
enum ShiftMapIndex =		0;
enum LockMapIndex =		1;
enum ControlMapIndex =		2;
enum Mod1MapIndex =		3;
enum Mod2MapIndex =		4;
enum Mod3MapIndex =		5;
enum Mod4MapIndex =		6;
enum Mod5MapIndex =		7;


/* button masks.  Used in same manner as Key masks above. Not to be confused
   with button names below. */

enum Button1Mask =		(1<<8);
enum Button2Mask =		(1<<9);
enum Button3Mask =		(1<<10);
enum Button4Mask =		(1<<11);
enum Button5Mask =		(1<<12);

enum AnyModifier =		(1<<15);  /* used in GrabButton, GrabKey */


/* button names. Used as arguments to GrabButton and as detail in ButtonPress
   and ButtonRelease events.  Not to be confused with button masks above.
   Note that 0 is already defined above as "AnyButton".  */

enum Button1 =			1;
enum Button2 =			2;
enum Button3 =			3;
enum Button4 =			4;
enum Button5 =			5;

/* Notify modes */

enum NotifyNormal =		0;
enum NotifyGrab =		1;
enum NotifyUngrab =		2;
enum NotifyWhileGrabbed =	3;

enum NotifyHint =		1;	/* for MotionNotify events */

/* Notify detail */

enum NotifyAncestor =		0;
enum NotifyVirtual =		1;
enum NotifyInferior =		2;
enum NotifyNonlinear =		3;
enum NotifyNonlinearVirtual =	4;
enum NotifyPointer =		5;
enum NotifyPointerRoot =	6;
enum NotifyDetailNone =	7;

/* Visibility notify */

enum VisibilityUnobscured =		0;
enum VisibilityPartiallyObscured =	1;
enum VisibilityFullyObscured =		2;

/* Circulation request */

enum PlaceOnTop =		0;
enum PlaceOnBottom =		1;

/* protocol families */

enum FamilyInternet =		0;	/* IPv4 */
enum FamilyDECnet =		1;
enum FamilyChaos =		2;
enum FamilyInternet6 =		6;	/* IPv6 */

/* authentication families not tied to a specific protocol */
enum FamilyServerInterpreted = 5;

/* Property notification */

enum PropertyNewValue =	0;
enum PropertyDelete =		1;

/* Color Map notification */

enum ColormapUninstalled =	0;
enum ColormapInstalled =	1;

/* GrabPointer, GrabButton, GrabKeyboard, GrabKey Modes */

enum GrabModeSync =		0;
enum GrabModeAsync =		1;

/* GrabPointer, GrabKeyboard reply status */

enum GrabSuccess =		0;
enum AlreadyGrabbed =		1;
enum GrabInvalidTime =		2;
enum GrabNotViewable =		3;
enum GrabFrozen =		4;

/* AllowEvents modes */

enum AsyncPointer =		0;
enum SyncPointer =		1;
enum ReplayPointer =		2;
enum AsyncKeyboard =		3;
enum SyncKeyboard =		4;
enum ReplayKeyboard =		5;
enum AsyncBoth =		6;
enum SyncBoth =		7;

/* Used in SetInputFocus, GetInputFocus */

const int  RevertToNone = None;
const int RevertToPointerRoot = PointerRoot;
enum RevertToParent =		2;

/*****************************************************************
 * ERROR CODES
 *****************************************************************/

enum Success =		   0;	/* everything's okay */
enum BadRequest =	   1;	/* bad request code */
enum BadValue =	   2;	/* int parameter out of range */
enum BadWindow =	   3;	/* parameter not a Window */
enum BadPixmap =	   4;	/* parameter not a Pixmap */
enum BadAtom =		   5;	/* parameter not an Atom */
enum BadCursor =	   6;	/* parameter not a Cursor */
enum BadFont =		   7;	/* parameter not a Font */
enum BadMatch =	   8;	/* parameter mismatch */
enum BadDrawable =	   9;	/* parameter not a Pixmap or Window */
enum BadAccess =	  10;	/* depending on context:
				 - key/button already grabbed
				 - attempt to free an illegal
				   cmap entry
				- attempt to store into a read-only
				   color map entry.
 				- attempt to modify the access control
				   list from other than the local host.
				*/
enum BadAlloc =	  11;	/* insufficient resources */
enum BadColor =	  12;	/* no such colormap */
enum BadGC =		  13;	/* parameter not a GC */
enum BadIDChoice =	  14;	/* choice not in range or already used */
enum BadName =		  15;	/* font or color name doesn't exist */
enum BadLength =	  16;	/* Request length incorrect */
enum BadImplementation = 17;	/* server is defective */

enum FirstExtensionError =	128;
enum LastExtensionError =	255;

/*****************************************************************
 * WINDOW DEFINITIONS
 *****************************************************************/

/* Window classes used by CreateWindow */
/* Note that CopyFromParent is already defined as 0 above */

enum InputOutput =		1;
enum InputOnly =		2;

/* Window attributes for CreateWindow and ChangeWindowAttributes */

enum CWBackPixmap =		(1<<0);
enum CWBackPixel =		(1<<1);
enum CWBorderPixmap =		(1<<2);
enum CWBorderPixel =           (1<<3);
enum CWBitGravity =		(1<<4);
enum CWWinGravity =		(1<<5);
enum CWBackingStore =          (1<<6);
enum CWBackingPlanes =	        (1<<7);
enum CWBackingPixel =	        (1<<8);
enum CWOverrideRedirect =	(1<<9);
enum CWSaveUnder =		(1<<10);
enum CWEventMask =		(1<<11);
enum CWDontPropagate =	        (1<<12);
enum CWColormap =		(1<<13);
enum CWCursor =	        (1<<14);

/* ConfigureWindow structure */

enum CWX =			(1<<0);
enum CWY =			(1<<1);
enum CWWidth =			(1<<2);
enum CWHeight =		(1<<3);
enum CWBorderWidth =		(1<<4);
enum CWSibling =		(1<<5);
enum CWStackMode =		(1<<6);


/* Bit Gravity */

enum ForgetGravity =		0;
enum NorthWestGravity =	1;
enum NorthGravity =		2;
enum NorthEastGravity =	3;
enum WestGravity =		4;
enum CenterGravity =		5;
enum EastGravity =		6;
enum SouthWestGravity =	7;
enum SouthGravity =		8;
enum SouthEastGravity =	9;
enum StaticGravity =		10;

/* Window gravity + bit gravity above */

enum UnmapGravity =		0;

/* Used in CreateWindow for backing-store hint */

enum NotUseful =               0;
enum WhenMapped =              1;
enum Always =                  2;

/* Used in GetWindowAttributes reply */

enum IsUnmapped =		0;
enum IsUnviewable =		1;
enum IsViewable =		2;

/* Used in ChangeSaveSet */

enum SetModeInsert =           0;
enum SetModeDelete =           1;

/* Used in ChangeCloseDownMode */

enum DestroyAll =              0;
enum RetainPermanent =         1;
enum RetainTemporary =         2;

/* Window stacking method (in configureWindow) */

enum Above =                   0;
enum Below =                   1;
enum TopIf =                   2;
enum BottomIf =                3;
enum Opposite =                4;

/* Circulation direction */

enum RaiseLowest =             0;
enum LowerHighest =            1;

/* Property modes */

enum PropModeReplace =         0;
enum PropModePrepend =         1;
enum PropModeAppend =          2;

/*****************************************************************
 * GRAPHICS DEFINITIONS
 *****************************************************************/

/* graphics functions, as in GC.alu */

enum GXclear =			0x0;		/* 0 */
enum GXand =			0x1;		/* src AND dst */
enum GXandReverse =		0x2;		/* src AND NOT dst */
enum GXcopy =			0x3;		/* src */
enum GXandInverted =		0x4;		/* NOT src AND dst */
enum GXnoop =			0x5;		/* dst */
enum GXxor =			0x6;		/* src XOR dst */
enum GXor =			0x7;		/* src OR dst */
enum GXnor =			0x8;		/* NOT src AND NOT dst */
enum GXequiv =			0x9;		/* NOT src XOR dst */
enum GXinvert =	        	0xa;		/* NOT dst */
enum GXorReverse =		0xb;		/* src OR NOT dst */
enum GXcopyInverted =		0xc;		/* NOT src */
enum GXorInverted =		0xd;		/* NOT src OR dst */
enum GXnand =			0xe;		/* NOT src OR NOT dst */
enum GXset =			0xf;		/* 1 */

/* LineStyle */

enum LineSolid =		0;
enum LineOnOffDash =		1;
enum LineDoubleDash =		2;

/* capStyle */

enum CapNotLast =		0;
enum CapButt =			1;
enum CapRound =		2;
enum CapProjecting =		3;

/* joinStyle */

enum JoinMiter =		0;
enum JoinRound =		1;
enum JoinBevel =		2;

/* fillStyle */

enum FillSolid =		0;
enum FillTiled =		1;
enum FillStippled =		2;
enum FillOpaqueStippled =	3;

/* fillRule */

enum EvenOddRule =		0;
enum WindingRule =		1;

/* subwindow mode */

enum ClipByChildren =		0;
enum IncludeInferiors =	1;

/* SetClipRectangles ordering */

enum Unsorted =		0;
enum YSorted =			1;
enum YXSorted =		2;
enum YXBanded =		3;

/* CoordinateMode for drawing routines */

enum CoordModeOrigin =		0;	/* relative to the origin */
enum CoordModePrevious =       1;	/* relative to previous point */

/* Polygon shapes */

enum Complex =			0;	/* paths may intersect */
enum Nonconvex =		1;	/* no paths intersect, but not convex */
enum Convex =			2;	/* wholly convex */

/* Arc modes for PolyFillArc */

enum ArcChord =		0;	/* join endpoints of arc */
enum ArcPieSlice =		1;	/* join endpoints to center of arc */

/* GC components: masks used in CreateGC, CopyGC, ChangeGC, OR'ed into
   GC.stateChanges */

enum GCFunction =              (1<<0);
enum GCPlaneMask =             (1<<1);
enum GCForeground =            (1<<2);
enum GCBackground =            (1<<3);
enum GCLineWidth =             (1<<4);
enum GCLineStyle =             (1<<5);
enum GCCapStyle =              (1<<6);
enum GCJoinStyle =		(1<<7);
enum GCFillStyle =		(1<<8);
enum GCFillRule =		(1<<9);
enum GCTile =			(1<<10);
enum GCStipple =		(1<<11);
enum GCTileStipXOrigin =	(1<<12);
enum GCTileStipYOrigin =	(1<<13);
enum GCFont = 			(1<<14);
enum GCSubwindowMode =		(1<<15);
enum GCGraphicsExposures =     (1<<16);
enum GCClipXOrigin =		(1<<17);
enum GCClipYOrigin =		(1<<18);
enum GCClipMask =		(1<<19);
enum GCDashOffset =		(1<<20);
enum GCDashList =		(1<<21);
enum GCArcMode =		(1<<22);

enum GCLastBit =		22;
/*****************************************************************
 * FONTS
 *****************************************************************/

/* used in QueryFont -- draw direction */

enum FontLeftToRight =		0;
enum FontRightToLeft =		1;

enum FontChange =		255;

/*****************************************************************
 *  IMAGING
 *****************************************************************/

/* ImageFormat -- PutImage, GetImage */

enum XYBitmap =		0;	/* depth 1, XYFormat */
enum XYPixmap =		1;	/* depth == drawable depth */
enum ZPixmap =			2;	/* depth == drawable depth */

/*****************************************************************
 *  COLOR MAP STUFF
 *****************************************************************/

/* For CreateColormap */

enum AllocNone =		0;	/* create map with no entries */
enum AllocAll =		1;	/* allocate entire map writeable */


/* Flags used in StoreNamedColor, StoreColors */

enum DoRed =			(1<<0);
enum DoGreen =			(1<<1);
enum DoBlue =			(1<<2);

/*****************************************************************
 * CURSOR STUFF
 *****************************************************************/

/* QueryBestSize Class */

enum CursorShape =		0;	/* largest size that can be displayed */
enum TileShape =		1;	/* size tiled fastest */
enum StippleShape =		2;	/* size stippled fastest */

/*****************************************************************
 * KEYBOARD/POINTER STUFF
 *****************************************************************/

enum AutoRepeatModeOff =	0;
enum AutoRepeatModeOn =	1;
enum AutoRepeatModeDefault =	2;

enum LedModeOff =		0;
enum LedModeOn =		1;

/* masks for ChangeKeyboardControl */

enum KBKeyClickPercent =	(1<<0);
enum KBBellPercent =		(1<<1);
enum KBBellPitch =		(1<<2);
enum KBBellDuration =		(1<<3);
enum KBLed =			(1<<4);
enum KBLedMode =		(1<<5);
enum KBKey =			(1<<6);
enum KBAutoRepeatMode =	(1<<7);

enum MappingSuccess =     	0;
enum MappingBusy =        	1;
enum MappingFailed =		2;

enum MappingModifier =		0;
enum MappingKeyboard =		1;
enum MappingPointer =		2;

/*****************************************************************
 * SCREEN SAVER STUFF
 *****************************************************************/

enum DontPreferBlanking =	0;
enum PreferBlanking =		1;
enum DefaultBlanking =		2;

enum DisableScreenSaver =	0;
enum DisableScreenInterval =	0;

enum DontAllowExposures =	0;
enum AllowExposures =		1;
enum DefaultExposures =	2;

/* for ForceScreenSaver */

enum ScreenSaverReset = 0;
enum ScreenSaverActive = 1;

/*****************************************************************
 * HOSTS AND CONNECTIONS
 *****************************************************************/

/* for ChangeHosts */

enum HostInsert =		0;
enum HostDelete =		1;

/* for ChangeAccessControl */

enum EnableAccess =		1;
enum DisableAccess =		0;

/* Display classes  used in opening the connection
 * Note that the statically allocated ones are even numbered and the
 * dynamically changeable ones are odd numbered */

enum StaticGray =		0;
enum GrayScale =		1;
enum StaticColor =		2;
enum PseudoColor =		3;
enum TrueColor =		4;
enum DirectColor =		5;


/* Byte order  used in imageByteOrder and bitmapBitOrder */

enum LSBFirst =		0;
enum MSBFirst =		1;

// EOF
