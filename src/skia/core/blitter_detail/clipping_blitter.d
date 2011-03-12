module skia.core.blitter_detail.clipping_blitter;

private {
  import guip.bitmap;
  import skia.core.blitter;
  import guip.rect;
  import skia.math.clamp;
}

class RectBlitter : Blitter {
  Blitter blitter;
  IRect clip;

  this(Blitter blitter, in IRect clip) {
    this.blitter = blitter;
    this.clip = clip;
  }

  void blitFH(float y, float xStart, float xEnd)
  {
    if (!fitsIntoRange!("[)")(y, this.clip.top, this.clip.bottom))
      return;

    xStart = clampToRange(xStart, this.clip.left, this.clip.right);
    xEnd = clampToRange(xEnd, this.clip.left, this.clip.right);

    if (xStart < xEnd)
      this.blitter.blitFH(y, xStart, xEnd);
  }

  override void blitMask(float x, float y, in Bitmap mask) {
    assert(0, "unimplemented");
  }
}
