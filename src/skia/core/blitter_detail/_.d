module skia.core.blitter_detail._;

version(NO_SSE) {
  import skia.core.blitter_detail.blit_row : Color32;
} else {
  import skia.core.blitter_detail.blit_row_sse : Color32;
}
import skia.core.blitter_detail.clipping_blitter;
