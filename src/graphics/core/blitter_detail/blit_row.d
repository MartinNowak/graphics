module graphics.core.blitter_detail.blit_row;

import std.array;
import std.range : popFront, front, empty, isRandomAccessRange;
import graphics.core.pmcolor;
import graphics.core.blitter_detail.blit_row_factory;

static void Color32(Range)(Range range, PMColor pmColor) {
  if (pmColor.a == 255) {
    foreach (ref px; range)
      px = pmColor;
  } else {
    auto scale = invAlphaScale(pmColor.a);
    foreach (ref px; range)
      px = alphaMul(px, scale) + pmColor;
  }
}

void S32_Opaque_BlitRow32(PMColor[] dst, const(PMColor)[] src, ubyte alpha) {
  assert(alpha == 255);
  dst[0 .. src.length] = src[];
}

void S32_Blend_BlitRow32(PMColor[] dst, const (PMColor)[] src, ubyte alpha) {
  if (!src.empty) {
    uint srcScale = alphaScale(alpha);
    uint dstScale = invAlphaScale(alpha);
    do {
      dst.front = alphaMul(src.front, srcScale) + alphaMul(dst.front, dstScale);
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
      dst.front = alphaMul(src.front, alphaScale(src.front.a))
        + alphaMul(dst.front, invAlphaScale(src.front.a));
    src.popFront;
    dst.popFront;
  }
}

void S32A_Blend_BlitRow32(PMColor[] dst, const (PMColor)[] src, ubyte alpha) {
  auto srcScale = alphaScale(alpha);

  while (!src.empty) {
    auto dstScale = invAlphaScale(alphaMul(src.front.a, srcScale));
    dst.front = alphaMul(dst.front, dstScale) + alphaMul(src.front, srcScale);
    src.popFront;
    dst.popFront;
  }
}
