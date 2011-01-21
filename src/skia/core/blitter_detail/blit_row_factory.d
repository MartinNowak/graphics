module skia.core.blitter_detail.blit_row_factory;

private {
  import skia.core.color;
}
version(NO_SSE) {
  public import skia.core.blitter_detail.blit_row;
} else {
  public import skia.core.blitter_detail.blit_row_sse;
}

/** Function pointer that blends 32bit colors onto a 32bit destination.
    @param dst  array of dst 32bit colors
    @param src  array of src 32bit colors (w/ or w/o alpha)
    @param count number of colors to blend
    @param alpha global alpha to be applied to all src colors
*/
alias const(void function(PMColor[] dst, const (PMColor)[] src, ubyte alpha)) BlitRowProc32;

enum BlitRowFlags32 {
  GlobalAlpha     = 1 << 0,
  SrcPixelAlpha   = 1 << 1,
};

