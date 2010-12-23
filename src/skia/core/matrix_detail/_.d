module skia.core.matrix_detail._;

/**
 * Optimized functions
 */
version(NO_SSE) {
  import skia.core.matrix_detail.map_points : mapPtsFunc;
  alias float[3][3] MatrixStorage;
} else {
  import skia.core.matrix_detail.map_points_sse : mapPtsFunc;
  //! Only needed for SSE matrix multiplication
  //! alias float[4][3] MatrixStorage;
  alias float[3][3] MatrixStorage;
}

/**
 * Common functions
 */
//! The SSE version is slower
import skia.core.matrix_detail.multiply : multiplyMatrices;
