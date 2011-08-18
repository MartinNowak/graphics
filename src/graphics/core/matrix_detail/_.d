module graphics.core.matrix_detail._;

/**
 * Optimized functions
 */
version(NO_SSE) {
  import graphics.core.matrix_detail.map_points : mapPtsFunc;
} else {
  import graphics.core.matrix_detail.map_points_sse : mapPtsFunc;
}
