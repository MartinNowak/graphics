module skia.math.rounding;

private {
  import std.math : trunc, NaN;
  import skia.math.clamp : checkedTo, fitsIntoRange;
}

version(NO_SSE) {
  alias stdMathTruncate truncate;

} else {
  alias SSETruncate truncate;
}

int stdMathTruncate(float f) {
  return checkedTo!int(trunc(f));
}
int SSETruncate(float f) {
  // assert(fitsIntoRange(f, int.min, int.max));
  asm {
    cvttss2si EAX, f;
  }
}


unittest {
  assert(stdMathTruncate(1.2) == 1);
  assert(stdMathTruncate(1.8) == 1);
  assert(SSETruncate(1.2) == 1);
  assert(SSETruncate(1.8) == 1);
}
