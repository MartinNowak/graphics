module SampleApp.bitmapview;

private {
  debug private import std.stdio : writeln;
  import std.math : floor;
  import std.conv : to;
  import std.stream;

  import skia.core.bitmap;
  import skia.core.canvas;
  import skia.core.color;
  import skia.core.path;
  import skia.core.paint;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.size;
  import skia.views.view;

  import libpng.png;
}


class BitmapView : View
{
  Bitmap bitmap;
  this() {
    this._flags.visible = true;
    this._flags.enabled = true;
    this.bitmap = decodeBitmapPNG("logo.png");
  }

  override void onSizeChange() {
    this.size = bitmap.size;
    //    this.bitmap.setConfig(Bitmap.Config.ARGB_8888, this.width, this.height);
    //    this.bitmap.eraseColor(PMColor(Green));
  }
  override void onDraw(Canvas canvas) {
    scope auto paint = new Paint(Black);
    canvas.drawBitmap(this.bitmap, FPoint(0, 0), paint);
  }
  override void onButtonPress(IPoint pt) {
    this.loc = pt;
  }
}

extern(C) void readDataFromStream(png_structp png_ptr, png_bytep buffer,
                                  png_size_t size) {
  auto stream = cast(InputStream*)png_get_io_ptr(png_ptr);
  assert(stream !is null);
  stream.readExact(cast(void*)buffer, size);
}

enum PNGSIGSIZE = 4;

Bitmap decodeBitmapPNG(string fileName) {
  InputStream stream = new File(fileName);
  ubyte[PNGSIGSIZE] hdr;

  /*
  stream.readExact(cast(void*)hdr, PNGSIGSIZE);
  writeln(stream.available);
  auto isPng = png_sig_cmp(cast(png_bytep)hdr, 0, PNGSIGSIZE);
  assert(isPng == 0);
  */
  auto png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING.ptr, null, null, null);
  assert(png_ptr);

  auto info_ptr = png_create_info_struct(png_ptr);
  assert(info_ptr);

  //  png_set_sig_bytes(png_ptr, PNGSIGSIZE);

  png_set_read_fn(png_ptr, &stream, &readDataFromStream);
  auto transforms =  PNG_Transform.Expand | PNG_Transform.BGR;

  png_set_add_alpha(png_ptr, 0xff, PNG_Filler.After);
  png_read_png(png_ptr, info_ptr, transforms, null);
  auto rows = cast(PMColor**)png_get_rows(png_ptr, info_ptr);
  debug writefln("ct:%s ilt:%s filt:%s", png_get_color_type(png_ptr, info_ptr),
           png_get_interlace_type(png_ptr, info_ptr),
           png_get_y_offset_microns(png_ptr, info_ptr));;


  auto h = png_get_image_height(png_ptr, info_ptr);
  auto w = png_get_image_width(png_ptr, info_ptr);
  auto bitmap = Bitmap(Bitmap.Config.ARGB_8888, w, h);
  for (auto row = 0; row < h; ++row) {
    auto dst = bitmap.getRange(0, w, row);
    dst[] = rows[row][0 .. w];
  }
  png_destroy_read_struct(&png_ptr, &info_ptr, null);
  return bitmap;
}
