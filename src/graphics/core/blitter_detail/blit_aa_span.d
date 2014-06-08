module graphics.core.blitter_detail.blit_aa_span;

import std.range;

import graphics.math.clamp : checkedTo;
import graphics.core.pmcolor;
import graphics.core.blitter_detail;

void BlitAASpan(R1, R2)(R1 output, R2 aa, Color color) {
  auto colA = color.a;
  while (!aa.empty) {
    auto curA = aa.front;
    auto equalCnt = 1;

    if (curA)  {
      ubyte resA = alphaMul(colA, alphaScale(curA));
      Color32(output[0 .. equalCnt], PMColor(color.a = resA));
    }
    aa.popFrontN(equalCnt);
    output.popFrontN(equalCnt);
  }
}
