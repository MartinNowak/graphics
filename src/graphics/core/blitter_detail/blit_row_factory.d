module graphics.core.blitter_detail.blit_row_factory;

import graphics.core.pmcolor;

public import graphics.core.blitter_detail.blit_row;

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

unittest
{
    // flags pick the right proc; distinguish by behaviour on a fully
    // transparent source pixel
    PMColor[2] dst, src;
    dst[] = PMColor(Color.White);
    src[0] = PMColor(Color(0)); // transparent
    src[1] = PMColor(Color.White);

    auto opaque = blitRowFactory32(0);
    opaque(dst[0 .. 1], src[0 .. 1], 255);
    assert(dst[0].argb == 0); // opaque path blindly copies

    dst[] = PMColor(Color.White);
    auto srcAlpha = blitRowFactory32(BlitRowFlags32.SrcPixelAlpha);
    srcAlpha(dst[0 .. 1], src[0 .. 1], 255);
    assert(dst[0] == PMColor(Color.White)); // per-pixel alpha keeps dst

    dst[] = PMColor(Color.White);
    src[0] = PMColor(Color.Red);
    auto ga = blitRowFactory32(BlitRowFlags32.GlobalAlpha);
    ga(dst[0 .. 1], src[0 .. 1], 128);
    assert(dst[0].r == 255 && dst[0].g == 127); // blended

    assert(blitRowFactory32(3) is defaultProcs32[3]);
    assert(defaultProcs32.length == 4);
}
