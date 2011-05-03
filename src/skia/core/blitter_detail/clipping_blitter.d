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

  override void blitH(int y, int xstart, int xend)
  {
    if (!fitsIntoRange!("[)")(y, this.clip.top, this.clip.bottom))
      return;

    xstart = clampToRange(xstart, this.clip.left, this.clip.right);
    xend = clampToRange(xend, this.clip.left, this.clip.right);

    if (xstart < xend)
      this.blitter.blitH(y, xstart, xend);
  }

  override void blitAlphaH(int y, int xstart, int xend, ubyte alpha)
  {
    if (!fitsIntoRange!("[)")(y, this.clip.top, this.clip.bottom))
      return;

    xstart = clampToRange(xstart, this.clip.left, this.clip.right);
    xend = clampToRange(xend, this.clip.left, this.clip.right);

    if (xstart < xend)
      this.blitter.blitAlphaH(y, xstart, xend, alpha);
  }

  override void blitMask(int x, int y, in Bitmap mask) {
    assert(0, "unimplemented");
  }
}
