module skia.core.matrix_detail._;

version(NO_SSE) {
  import skia.core.matrix_detail.map_points : mapPtsFunc;
  import skia.core.matrix_detail.multiply : multiplyMatrices;
} else {
  import skia.core.matrix_detail.map_points_sse : mapPtsFunc;
  import skia.core.matrix_detail.multiply_sse : multiplyMatrices;
}
