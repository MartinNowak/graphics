module skia.core.blitter_detail.blit_row;

private {
  import std.array;
  import std.range : popFront, front, empty;
  import skia.core.color;
  import skia.core.blitter_detail.blit_row_factory;
}

static const BlitRowProc32 defaultProcs32[4] = [
    &S32_Opaque_BlitRow32,
    &S32_Blend_BlitRow32,
    &S32A_Opaque_BlitRow32,
    &S32A_Blend_BlitRow32,
];

BlitRowProc32 BlitRowFactory32(uint flags32) {
  assert(flags32 <= (BlitRowFlags32.GlobalAlpha | BlitRowFlags32.SrcPixelAlpha));
  return defaultProcs32[flags32];
}

static void Color32(Range)(Range range, PMColor pmColor) {
  if (pmColor.a == 255) {
    while (!range.empty) {
      range.front = pmColor;
      range.popFront;
    }
  } else {
    auto scale = invAlphaScale(pmColor.a);
    while (!range.empty) {
      range.front = range.front.mulAlpha(scale) + pmColor;
      range.popFront;
    }
  }
}

void S32_Opaque_BlitRow32(PMColor[] dst, const(PMColor)[] src, ubyte alpha) {
  assert(alpha == 255);
  dst[0 .. src.length] = src[];
}

void S32_Blend_BlitRow32(PMColor[] dst, const (PMColor)[] src, ubyte alpha) {
  assert(alpha <= 255);
  if (!src.empty) {
    uint srcScale = alphaScale(alpha);
    uint dstScale = invAlphaScale(alpha);
    do {
      dst.front = src.front.mulAlpha(srcScale) + dst.front.mulAlpha(dstScale);
      src.popFront;
      dst.popFront;
    } while (!src.empty);
  }
}

void S32A_Opaque_BlitRow32(PMColor[] dst, const (PMColor)[] src, ubyte alpha) {
  assert(255 == alpha);
  while (!src.empty) {
    if (src.front.a == 255)
      dst.front = src.front;
    else
      dst.front = src.front.mulAlpha(alphaScale(src.front.a))
        + dst.front.mulAlpha(invAlphaScale(src.front.a));
    src.popFront;
    dst.popFront;
  }
}

void S32A_Blend_BlitRow32(PMColor[] dst, const (PMColor)[] src, ubyte alpha) {
  auto srcScale = alphaScale(alpha);

  while (!src.empty) {
    auto dstScale = invAlphaScale(alphaMul(src.front.a, srcScale));
    dst.front = dst.front.mulAlpha(dstScale) + src.front.mulAlpha(srcScale);
    src.popFront;
    dst.popFront;
  }
}
