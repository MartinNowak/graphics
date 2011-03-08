module skia.core.blitter_detail.blit_aa_span;

private {
  import std.algorithm : indexOf, max;
  import std.range;

  import skia.math.clamp : checkedTo;
  import skia.core.color;
  import skia.core.blitter_detail._;
}

void BlitAASpan(R1, R2)(R1 output, R2 aa, Color color) {
  auto colA = color.a;
  while (!aa.empty) {
    auto curA = aa.front;
    //    auto len = indexOf!("a != b")(aa, curA);
    //    auto equalCnt = max(len - 1, 1);
    auto equalCnt = 1;

    if (curA)  {
      ubyte resA = alphaMul(colA, alphaScale(curA));
      Color32(output[0 .. equalCnt], PMColor(color.a = resA));
    }
    aa.popFrontN(equalCnt);
    output.popFrontN(equalCnt);
  }
}
