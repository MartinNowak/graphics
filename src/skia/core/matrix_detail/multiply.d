module skia.core.matrix_detail.multiply;

private import skia.core.matrix;

Matrix multiplyMatrices(in Matrix lhs, in Matrix rhs) {
  Matrix tmp;
  for(size_t row = 0; row < 3; ++row) {
    for (size_t col = 0; col < 3; ++col) {
      tmp[row][col] =
        lhs[row][0] * rhs[0][col]
        + lhs[row][1] * rhs[1][col]
        + lhs[row][2] * rhs[2][col];
    }
  }
  return tmp;
}
