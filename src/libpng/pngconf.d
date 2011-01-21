module libpng.pngconf;

alias uint png_uint_32;
alias int png_int_32;
alias ushort png_uint_16;
alias short png_int_16;
alias ubyte png_byte;
alias size_t png_size_t;

/* Typedef for floating-point numbers that are converted
   to fixed-point with a multiple of 100,000, e.g., int_gamma */
typedef png_int_32 png_fixed_point;

/* Add typedefs for pointers */
alias void* png_voidp;
alias png_uint_32* png_uint_32p;
alias png_int_32* png_int_32p;
alias png_uint_16* png_uint_16p;
alias png_int_16* png_int_16p;
alias const char* png_const_charp;
alias char* png_charp;
alias png_fixed_point* png_fixed_point_p;
alias png_byte* png_bytep;

alias double* png_doublep;

/* Pointers to pointers; i.e. arrays */
alias png_byte** png_bytepp;
alias png_uint_32** png_uint_32pp;
alias png_int_32** png_int_32pp;
alias png_uint_16** png_uint_16pp;
alias png_int_16** png_int_16pp;
alias const char** png_const_charpp;
alias char** png_charpp;
alias png_fixed_point** png_fixed_point_pp;
alias double** png_doublepp;

/* Pointers to pointers to pointers; i.e., pointer to array */
alias char*** png_charppp;
