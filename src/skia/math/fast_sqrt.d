module skia.math.fast_sqrt;

private {
  import std.math : sqrt;
}

version(NO_SSE) {
  float fastSqrt(float n) {
    return sqrt(n);
  }
} else {
  float fastSqrt(float n)
  {
    assert(n >= 0);

    if (n == 0)
      return 0;

    asm {
      rsqrtss XMM0, n;
      mulss XMM0, n;
      movss n, XMM0;
    }

    return n;
  }
}

unittest {
  real errorSum = 0.0;
  size_t j;
  for (float i = 1.0/1000; i<=1000; i+=1.0/1000, ++j) {
    auto dev = fastSqrt(i) - sqrt(i);
    errorSum += dev * dev;
  }
  auto error = sqrt(errorSum / j);
  assert(error < 3e-3);
}
