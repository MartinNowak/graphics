module freetype.outline;

import freetype.freetype;

extern(C):

alias int function(const FT_Vector* to, void* user) FT_Outline_MoveToFunc;
alias int function(const FT_Vector* to, void* user) FT_Outline_LineToFunc;

alias int function(const FT_Vector* control,
                   const FT_Vector* to,
                   void* user) FT_Outline_ConicToFunc;

alias int function(const FT_Vector*  control1,
                   const FT_Vector*  control2,
                   const FT_Vector*  to,
                   void* user) FT_Outline_CubicToFunc;

struct FT_Outline_Funcs
{
  FT_Outline_MoveToFunc   move_to;
  FT_Outline_LineToFunc   line_to;
  FT_Outline_ConicToFunc  conic_to;
  FT_Outline_CubicToFunc  cubic_to;

  int                     shift;
  FT_Pos                  delta;
};

FT_Error FT_Outline_Decompose(FT_Outline* outline,
                              const FT_Outline_Funcs* func_interface,
                              void* user);
