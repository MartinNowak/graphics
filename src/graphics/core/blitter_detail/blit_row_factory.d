module graphics.core.blitter_detail.blit_row_factory;

import graphics.core.pmcolor;

version(NO_SSE) {
  public import graphics.core.blitter_detail.blit_row;
} else {
  public import graphics.core.blitter_detail.blit_row_sse;
}

/** Function pointer that blends 32bit colors onto a 32bit destination.
    @param dst  array of dst 32bit colors
    @param src  array of src 32bit colors (w/ or w/o alpha)
    @param count number of colors to blend
    @param alpha global alpha to be applied to all src colors
*/
alias void function(PMColor[] dst, const (PMColor)[] src, ubyte alpha) BlitRowProc32;

enum BlitRowFlags32 {
  GlobalAlpha     = 1 << 0,
  SrcPixelAlpha   = 1 << 1,
};

static const BlitRowProc32[4] defaultProcs32 = [
    &S32_Opaque_BlitRow32,
    &S32_Blend_BlitRow32,
    &S32A_Opaque_BlitRow32,
    &S32A_Blend_BlitRow32,
];

BlitRowProc32 blitRowFactory32(uint flags32) {
  assert(flags32 <= (BlitRowFlags32.GlobalAlpha | BlitRowFlags32.SrcPixelAlpha));
  return defaultProcs32[flags32];
}
