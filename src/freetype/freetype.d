module freetype.freetype;

pragma(lib, "freetype");

struct FT_LIBRARY_;
alias FT_LIBRARY_* FT_Library;

alias int FT_Error;

alias FT_FaceRec*  FT_Face;

static if (size_t.sizeof == 4) {
  alias int FT_Long;
  alias int FT_F26Dot6;
  alias int FT_Pos;
  alias int FT_Fixed;
} else {
  static assert(size_t.sizeof == 8);
  alias long FT_Long;
  alias long FT_F26Dot6;
  alias long FT_Pos;
  alias long FT_Fixed;
}

alias short FT_Short;
alias ushort FT_UShort;
alias size_t FT_ULong;
alias uint FT_UInt;
alias int FT_Int;
alias int FT_Int32;
alias char FT_String;

extern(C):

FT_Error FT_Init_FreeType(FT_Library *alibrary);
FT_Error FT_Done_FreeType(FT_Library library);
FT_Error FT_New_Face(FT_Library library, const (char*)  filepathname, FT_Long face_index, FT_Face* aface );
FT_Error FT_Done_Face(FT_Face face);
FT_Error FT_Set_Char_Size(FT_Face     face,
                    FT_F26Dot6  char_width,
                    FT_F26Dot6  char_height,
                    FT_UInt     horz_resolution,
                    FT_UInt     vert_resolution );
FT_Error FT_Set_Pixel_Sizes(FT_Face face, FT_UInt pixel_width, FT_UInt pixel_height );
FT_UInt FT_Get_Char_Index( FT_Face   face,
                   FT_ULong  charcode );
FT_Error FT_Load_Glyph( FT_Face   face,
                 FT_UInt   glyph_index,
                 FT_Int32  load_flags );

FT_Error FT_Load_Char( FT_Face   face,
              FT_ULong  char_code,
              FT_Int32  load_flags );

FT_Error FT_Render_Glyph(FT_GlyphSlot    slot,
                         FT_Render_Mode render_mode );

FT_Error FT_Get_Kerning(FT_Face face, FT_UInt left_glyph, FT_UInt right_glyph,
                        FT_Kerning_Mode kern_mode, FT_Vector *akerning);

enum FT_LOAD : uint
{
  DEFAULT = 0x0,
  NO_SCALE = 0x1,
  NO_HINTING = 0x2,
  RENDER = 0x4,
  NO_BITMAP = 0x8,
  VERTICAL_LAYOUT = 0x10,
  FORCE_AUTOHINT = 0x20,
  CROP_BITMAP = 0x40,
  PEDANTIC = 0x80,
  IGNORE_GLOBAL_ADVANCE_WIDTH = 0x200,
  NO_RECURSE = 0x400,
  IGNORE_TRANSFORM = 0x800,
  MONOCHROME = 0x1000,
  LINEAR_DESIGN = 0x2000,
  NO_AUTOHINT = 0x8000U
}

struct FT_FaceRec
{
  FT_Long           num_faces;
  FT_Long           face_index;

  FT_Long           face_flags;
  FT_Long           style_flags;

  FT_Long           num_glyphs;

  FT_String*        family_name;
  FT_String*        style_name;

  FT_Int            num_fixed_sizes;
  FT_Bitmap_Size*   available_sizes;

  FT_Int            num_charmaps;
  FT_CharMap*       charmaps;

  FT_Generic        generic;

  /*# The following member variables (down to `underline_thickness') */
  /*# are only relevant to scalable outlines; cf. @FT_Bitmap_Size    */
  /*# for bitmap fonts.                                              */
  FT_BBox           bbox;

  FT_UShort         units_per_EM;
  FT_Short          ascender;
  FT_Short          descender;
  FT_Short          height;

  FT_Short          max_advance_width;
  FT_Short          max_advance_height;

  FT_Short          underline_position;
  FT_Short          underline_thickness;

  FT_GlyphSlot      glyph;
  FT_Size           size;
  FT_CharMap        charmap;

  /*@private begin */

  FT_Driver         driver;
  FT_Memory         memory;
  FT_Stream         stream;

  FT_ListRec        sizes_list;

  FT_Generic        autohint;
  void*             extensions;

  FT_Face_Internal  internal;

  /*@private end */

};

enum FT_Face_Flag {
  SCALABLE=          ( 1L <<  0 ),
  FIXED_SIZES=       ( 1L <<  1 ),
  FIXED_WIDTH=       ( 1L <<  2 ),
  SFNT=              ( 1L <<  3 ),
  HORIZONTAL=        ( 1L <<  4 ),
  VERTICAL=          ( 1L <<  5 ),
  KERNING=           ( 1L <<  6 ),
  FAST_GLYPHS=       ( 1L <<  7 ),
  MULTIPLE_MASTERS=  ( 1L <<  8 ),
  GLYPH_NAMES=       ( 1L <<  9 ),
  EXTERNAL_STREAM=   ( 1L << 10 ),
  HINTER=            ( 1L << 11 ),
  CID_KEYED=         ( 1L << 12 ),
  TRICKY=            ( 1L << 13 ),
}

struct FT_Bitmap_Size
{
  FT_Short  height;
  FT_Short  width;

  FT_Pos    size;

  FT_Pos    x_ppem;
  FT_Pos    y_ppem;

} ;

struct FT_CharMapRec_;
alias FT_CharMapRec_*  FT_CharMap;

struct FT_DriverRec_;
alias FT_DriverRec_* FT_Driver;

struct FT_Memory_;
alias FT_Memory_* FT_Memory;

struct FT_Stream_;
alias FT_Stream_* FT_Stream;

struct FT_ListRec
{
  FT_ListNode  head;
  FT_ListNode  tail;
};

struct FT_ListNodeRec_;
alias FT_ListNodeRec_* FT_ListNode;

struct FT_Face_InternalRec_;
alias FT_Face_InternalRec_* FT_Face_Internal;

struct FT_BBox
{
  FT_Pos  xMin, yMin;
  FT_Pos  xMax, yMax;
};

struct  FT_Size_Metrics
{
  FT_UShort  x_ppem;      /* horizontal pixels per EM               */
  FT_UShort  y_ppem;      /* vertical pixels per EM                 */

  FT_Fixed   x_scale;     /* scaling values used to convert font    */
  FT_Fixed   y_scale;     /* units to 26.6 fractional pixels        */

  FT_Pos     ascender;    /* ascender in 26.6 frac. pixels          */
  FT_Pos     descender;   /* descender in 26.6 frac. pixels         */
  FT_Pos     height;      /* text height in 26.6 frac. pixels       */
  FT_Pos     max_advance; /* max horizontal advance, in 26.6 pixels */
};

struct FT_Size_InternalRec_;
alias FT_Size_InternalRec_*  FT_Size_Internal;

struct FT_SizeRec
{
  FT_Face           face;      /* parent face object              */
  FT_Generic        generic;   /* generic pointer for client uses */
  FT_Size_Metrics   metrics;   /* size metrics                    */
  FT_Size_Internal  internal;
};

alias FT_SizeRec* FT_Size;

struct FT_GlyphSlotRec
{
  FT_Library        library;
  FT_Face           face;
  FT_GlyphSlot      next;
  FT_UInt           reserved;       /* retained for binary compatibility */
  FT_Generic        generic;

  FT_Glyph_Metrics  metrics;
  FT_Fixed          linearHoriAdvance;
  FT_Fixed          linearVertAdvance;
  FT_Vector         advance;

  FT_Glyph_Format   format;

  FT_Bitmap         bitmap;
  FT_Int            bitmap_left;
  FT_Int            bitmap_top;

  FT_Outline        outline;

  FT_UInt           num_subglyphs;
  FT_SubGlyph       subglyphs;

  void*             control_data;
  long              control_len;

  FT_Pos            lsb_delta;
  FT_Pos            rsb_delta;

  void*             other;

  FT_Slot_Internal  internal;
};

alias FT_GlyphSlotRec* FT_GlyphSlot;

alias void function(void*  object) FT_Generic_Finalizer;
struct FT_Generic
{
  void*                 data;
  FT_Generic_Finalizer  finalizer;
};

struct FT_Glyph_Metrics
{
  FT_Pos  width;
  FT_Pos  height;

  FT_Pos  horiBearingX;
  FT_Pos  horiBearingY;
  FT_Pos  horiAdvance;

  FT_Pos  vertBearingX;
  FT_Pos  vertBearingY;
  FT_Pos  vertAdvance;
};

struct FT_Vector
{
  FT_Pos  x;
  FT_Pos  y;
};

template FourCC(char c1, char c2, char c3, char c4) {
  enum FourCC = c1 << 24 | c2 << 16 | c3 << 8 | c4;
}

enum  FT_Glyph_Format : uint
{
  None = 0,
  NONE = None,
  Composite = FourCC!('c', 'o', 'm', 'p'),
  COMPOSITE = Composite,
  Bitmap = FourCC!('b', 'i', 't', 's'),
  BITMAP = Bitmap,
  Outline = FourCC!('o', 'u', 't', 'l'),
  OUTLINE = Outline,
  Plotter = FourCC!('p', 'l', 'o', 't'),
  PLOTTER = Plotter,
}

struct FT_Bitmap
{
  int             rows;
  int             width;
  int             pitch;
  ubyte*  buffer;
  short           num_grays;
  char            pixel_mode;
  char            palette_mode;
  void*           palette;
}

struct  FT_Outline
{
  short       n_contours;      /* number of contours in glyph        */
  short       n_points;        /* number of points in the glyph      */

  FT_Vector*  points;          /* the outline's points               */
  char*       tags;            /* the points flags                   */
  short*      contours;        /* the contour end points             */

  int         flags;           /* outline masks                      */
}

struct FT_SubGlyphRec_;
alias FT_SubGlyphRec_*  FT_SubGlyph;

struct FT_Slot_InternalRec_;
alias FT_Slot_InternalRec_* FT_Slot_Internal;

enum  FT_Render_Mode : uint
{
  NORMAL = 0,
  Normal = NORMAL,
  LIGHT = 1,
  Light = LIGHT,
  MONO = 2,
  Mono = MONO,
  LCD = 3,
  LCD_V = 4,

  MAX = 5,
  Max = MAX,
};

enum FT_Kerning_Mode : FT_UInt
{
  DEFAULT  = 0,
  Default = DEFAULT,
  UNFITTED = 1,
  Unfitted = UNFITTED,
  UNSCALED = 2,
  Unscaled = UNSCALED,
}
