module skia.core.matrix_detail._;

version(NO_SSE) {
  import skia.core.matrix_detail.map_points : mapPtsFunc;
} else {
  import skia.core.matrix_detail.map_points_sse : mapPtsFunc;
}
