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
