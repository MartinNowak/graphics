module skia.core.matrix_detail.multiply_sse;

private {
 import skia.core.matrix;
 import skia.math.m128;
 debug import std.stdio : writeln, writefln;
}

alias float[4][3] MatrixStorage;

//! This function is approx. 4 times as slow as the fpu version, so don't use it.
Matrix multiplyMatrices(in Matrix lhs, in Matrix rhs) {
  Matrix tmp;

  {
    auto pr0 = &rhs[0][0];
    auto pr1 = &rhs[1][0];
    auto pr2 = &rhs[2][0];
    asm {
      mov ECX, pr0;
      movups XMM0, [ECX];
      mov ECX, pr1;
      movups XMM1, [ECX];
      mov ECX, pr2;
      movups XMM2, [ECX];
    }
  }

  for(size_t row = 0; row < 3; ++row) {
    auto col0_wide = m128.fromOne(lhs[row][0]);
    auto col1_wide = m128.fromOne(lhs[row][1]);
    auto col2_wide = m128.fromOne(lhs[row][2]);
    auto pc0 = &col0_wide;
    auto pc1 = &col1_wide;
    auto pc2 = &col2_wide;
    asm {
      mov ECX, pc0;
      movups XMM3, [ECX];
      mov ECX, pc1;
      movups XMM4, [ECX];
      mov ECX, pc2;
      movups XMM5, [ECX];
      mulps XMM3, XMM0;
      mulps XMM4, XMM1;
      mulps XMM5, XMM2;
      addps XMM3, XMM4;
      addps XMM3, XMM5;
      movups [ECX], XMM3;
    }
    tmp[row][0] = col2_wide.floats[0];
    tmp[row][1] = col2_wide.floats[1];
    tmp[row][2] = col2_wide.floats[2];
  }
  return tmp;
}

unittest {
  Matrix m1;
  m1.reset();
  Matrix m2;
  m2.reset();
  auto m3 = multiplyMatrices(m1, m2);
  writeln(m3);
  assert(m3.typeMaskTrans == Matrix.Type.Identity);
}
