module libpng.png;

public import libpng.pngconf;
private import core.stdc.time;

version = PNG_SEQUENTIAL_READ_SUPPORTED;
version = PNG_FLOATING_POINT_SUPPORTED;
version = PNG_INFO_IMAGE_SUPPORTED;
version = PNG_READ_FILLER_SUPPORTED;

extern(C):

enum PNG_LIBPNG_VER_STRING = "1.4.3";

/* This is used for the transformation routines, as some of them
 * change these values for the row.  It also should enable using
 * the routines for other purposes.
 */
struct png_row_info
{
   png_uint_32 width; /* width of row */
   png_size_t rowbytes; /* number of bytes in row */
   png_byte color_type; /* color type of row */
   png_byte bit_depth; /* bit depth of row */
   png_byte channels; /* number of channels (1, 2, 3, or 4) */
   png_byte pixel_depth; /* bits per pixel (depth * channels) */
};

alias png_row_info* png_row_infop;
alias png_row_info** png_row_infopp;

/* These are the function types for the I/O functions and for the functions
 * that allow the user to override the default I/O functions with his or her
 * own.  The png_error_ptr type should match that of user-supplied warning
 * and error functions, while the png_rw_ptr type should match that of the
 * user read/write data functions.
 */
struct png_struct {}; // opaque
alias png_struct* png_structp;
alias png_struct** png_structpp;

alias void function(png_structp, png_const_charp) png_error_ptr;
alias void function(png_structp, png_bytep, png_size_t) png_rw_ptr;
alias void function(png_structp) png_flush_ptr;
alias void function(png_structp, png_uint_32, int) png_read_status_ptr;
alias void function(png_structp, png_uint_32, int) png_write_status_ptr;

/* since > 0.95 there are functions to get infos from png_info_struct therefor handled opaque */
struct png_info {};
alias png_info* png_infop;
alias png_info** png_infopp;

/* functions */

/* Tell lib we have already handled the first <num_bytes> magic bytes.
 * Handling more than 8 bytes from the beginning of the file is an error.
 */
void png_set_sig_bytes(png_structp png_ptr, int num_bytes);

/* Check sig[start] through sig[start + num_to_check - 1] to see if it's a
 * PNG file.  Returns zero if the supplied bytes match the 8-byte PNG
 * signature, and non-zero otherwise.  Having num_to_check == 0 or
 * start > 7 will always fail (ie return non-zero).
 */
int png_sig_cmp(png_bytep sig, png_size_t start, png_size_t num_to_check);

/* png_access_version_number() returns version of the libpng12 library available at run-time. */
png_uint_32 png_access_version_number();

/* Allocate and initialize png_ptr struct for reading, and any other memory. */
png_structp png_create_read_struct(png_const_charp user_png_ver, png_voidp error_ptr,
                                   png_error_ptr error_fn, png_error_ptr warn_fn);
png_structp png_create_write_struct(png_const_charp user_png_ver, png_voidp error_ptr,
                                    png_error_ptr error_fn, png_error_ptr warn_fn);
/* Allocate and initialize the info structure */
png_infop png_create_info_struct(png_structp png_ptr);

void png_destroy_info_struct(png_structp png_ptr, png_infopp info_ptr_ptr);
void png_destroy_read_struct(png_structpp png_ptr_ptr, png_infopp info_ptr_ptr,
                             png_infopp end_info_ptr_ptr);
void png_destroy_write_struct(png_structpp png_ptr_ptr, png_infopp info_ptr_ptr);

/* Replace the default data input function with a user supplied one. */
void png_set_read_fn(png_structp png_ptr,
                     png_voidp io_ptr, png_rw_ptr read_data_fn);

/* Return the user pointer associated with the I/O functions */
png_voidp png_get_io_ptr(png_structp png_ptr);

version (PNG_SEQUENTIAL_READ_SUPPORTED) {
  /* Read the information before the actual image data. */
  void png_read_info(png_structp png_ptr, png_infop info_ptr);
}

/++
 + Access functions for png_info
 +/

/* Returns image width in pixels. */
png_uint_32 png_get_image_width(png_structp png_ptr, png_infop info_ptr);

/* Returns image height in pixels. */
png_uint_32 png_get_image_height(png_structp png_ptr, png_infop info_ptr);

/* Returns image bit_depth. */
png_byte png_get_bit_depth(png_structp png_ptr, png_infop info_ptr);

/* Returns image color_type. */
png_byte png_get_color_type(png_structp png_ptr, png_infop info_ptr);

/* Returns image filter_type. */
png_byte png_get_filter_type(png_structp png_ptr, png_infop info_ptr);

/* Returns image interlace_type. */
png_byte png_get_interlace_type(png_structp png_ptr, png_infop info_ptr);

/* Returns image compression_type. */
png_byte png_get_compression_type(png_structp png_ptr, png_infop info_ptr);

/* Returns image resolution in pixels per meter, from pHYs chunk data. */
png_uint_32 png_get_pixels_per_meter(png_structp png_ptr, png_infop info_ptr);
png_uint_32 png_get_x_pixels_per_meter(png_structp png_ptr, png_infop info_ptr);
png_uint_32 png_get_y_pixels_per_meter(png_structp png_ptr, png_infop info_ptr);

/* Returns pixel aspect ratio, computed from pHYs chunk data.  */
version (PNG_FLOATING_POINT_SUPPORTED) {
  float png_get_pixel_aspect_ratio(png_structp png_ptr, png_infop info_ptr);
}

/* Returns image x, y offset in pixels or microns, from oFFs chunk data. */
png_int_32 png_get_x_offset_pixels(png_structp png_ptr, png_infop info_ptr);
png_int_32 png_get_y_offset_pixels(png_structp png_ptr, png_infop info_ptr);
png_int_32 png_get_x_offset_microns(png_structp png_ptr, png_infop info_ptr);
png_int_32 png_get_y_offset_microns(png_structp png_ptr, png_infop info_ptr);


version (PNG_INFO_IMAGE_SUPPORTED) {
  /* The "params" pointer is currently not used and is for future expansion. */
  void png_read_png(png_structp png_ptr, png_infop info_ptr,
                    int transforms, png_voidp params = null);
  void png_write_png(png_structp png_ptr, png_infop info_ptr,
                     int transforms, png_voidp params = null);

  /* Returns row_pointers, which is an array of pointers to scanlines that was
   * returned from png_read_png().
   */
  png_bytepp png_get_rows(png_structp png_ptr, png_infop info_ptr);

  /* Set row_pointers, which is an array of pointers to scanlines for use
   * by png_write_png().
   */
  void png_set_rows(png_structp png_ptr, png_infop info_ptr, png_bytepp row_pointers);
}

enum PNG_Transform {
  Identity = 0x0000,    /* read and write */
  Strip_16 = 0x0001,    /* read only */
  Strip_Alpha = 0x0002,    /* read only */
  Packing = 0x0004,    /* read and write */
  PackSwap = 0x0008,    /* read and write */
  Expand = 0x0010,    /* read only */
  Invert_Mono = 0x0020,    /* read and write */
  Shift = 0x0040,    /* read and write */
  BGR = 0x0080,    /* read and write */
  Swap_Alpha = 0x0100,    /* read and write */
  Swap_Endian = 0x0200,    /* read and write */
  Invert_Alpha = 0x0400,    /* read and write */
  Strip_Filler = 0x0800,    /* write only */
/* Added to libpng-1.2.34 */
  Strip_Filler_Before = Strip_Filler,
  Strip_Filler_After = 0x1000,
/* Added to libpng-1.4.0 */
  Gray_To_RGB = 0x2000,      /* read only */
}

version (PNG_READ_FILLER_SUPPORTED) /* || PNG_WRITE_FILLER_SUPPORTED*/{
  /* Add a filler byte to 8-bit Gray or 24-bit RGB images. */
  void png_set_filler(png_structp png_ptr, png_uint_32 filler, int flags);
  /* Add an alpha byte to 8-bit Gray or 24-bit RGB images. */
  void png_set_add_alpha(png_structp png_ptr, png_uint_32 filler, int flags);

  /* The values of the PNG_FILLER_ defines should NOT be changed */
  enum PNG_Filler {
    Before = 0,
    After = 1,
  }
}
