module skia.core.blitter_detail.blit_row;

private {
  import std.range : popFront, front, empty;
  import skia.core.color;
}

static void Color32(Range)(Range range, PMColor pmColor) {
  if (pmColor.a == 255) {
    while (!range.empty) {
      range.front = pmColor;
      range.popFront;
    }
  } else {
    auto scale = Color.getInvAlphaFactor(pmColor.a);
    while (!range.empty) {
      range.front = range.front.mulAlpha(scale) + pmColor;
      range.popFront;
    }
  }
}

static void Color32(Range, Range2)(Range output, Range2 alpha, Color color) {
  auto colorA = color.a;
  while (!alpha.empty) {
    if (alpha.front > 0) {
      auto combA = (colorA + 1) * (alpha.front + 1) >> 8;
      auto srcA = Color.getAlphaFactor(combA);
      auto dstA = Color.getInvAlphaFactor(combA);
      output.front = output.front.mulAlpha(dstA) + color.mulAlpha(srcA);
    }
    output.popFront; alpha.popFront;
  }
}
