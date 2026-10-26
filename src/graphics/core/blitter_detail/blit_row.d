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

unittest
{
    // Color32: opaque overwrite
    PMColor[4] row;
    row[] = PMColor(Color.Black);
    Color32(row[], PMColor(Color.Red));
    foreach (px; row)
        assert(px == Color.Red);

    // Color32: translucent dst = dst * (255-a)/256 + src
    row[] = PMColor(Color.Red);
    Color32(row[], PMColor(color(128, 0, 255, 0)));
    // dst: r 255*128>>8=127, a 255*128>>8=127; src premul: g 128, a 128
    foreach (px; row) {
        assert(px.r == 127);
        assert(px.g == 128);
        assert(px.b == 0);
        assert(px.a == 255);
    }

    // S32_Opaque: straight copy
    PMColor[4] dst, src;
    dst[] = PMColor(Color.White);
    src[] = PMColor(Color.Blue);
    S32_Opaque_BlitRow32(dst, src, 255);
    foreach (px; dst)
        assert(px == Color.Blue);

    // S32_Blend: global alpha 128, opaque colors
    dst[] = PMColor(Color.White);
    src[] = PMColor(Color.Red);
    S32_Blend_BlitRow32(dst, src, 128);
    foreach (px; dst) {
        assert(px.r == 255); // 128 + 127
        assert(px.g == 127);
        assert(px.b == 127);
        assert(px.a == 255);
    }

    // S32_Blend: alpha 255 replaces
    dst[] = PMColor(Color.White);
    src[] = PMColor(Color.Green);
    S32_Blend_BlitRow32(dst, src, 255);
    foreach (px; dst)
        assert(px == Color.Green);

    // S32A_Opaque: per-pixel alpha; opaque and transparent pixels
    dst[] = PMColor(Color.White);
    src[0] = PMColor(Color.Black);
    src[1] = PMColor(color(0, 255, 255, 255));
    S32A_Opaque_BlitRow32(dst[0 .. 2], src[0 .. 2], 255);
    assert(dst[0] == Color.Black);
    assert(dst[1] == PMColor(Color.White)); // unchanged

    // S32A_Blend: global alpha with source pixel alpha
    dst[] = PMColor(Color.White);
    src[0] = PMColor(color(128, 255, 0, 0));
    S32A_Blend_BlitRow32(dst[0 .. 1], src[0 .. 1], 128);
    // srcScale=129 -> src premul r 128*129>>8=64, a 64
    // dstScale=invAlphaScale(64)=192 -> white premul *=192>>8 -> 191
    assert(dst[0].r == 64 + 191);
    assert(dst[0].g == 191);
    assert(dst[0].b == 191);
    assert(dst[0].a == 64 + 191);
}
