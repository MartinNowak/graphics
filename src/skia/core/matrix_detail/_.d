module skia.core.matrix_detail._;

/**
 * Optimized functions
 */
version(NO_SSE) {
  import skia.core.matrix_detail.map_points : mapPtsFunc;
} else {
  import skia.core.matrix_detail.map_points_sse : mapPtsFunc;
}
