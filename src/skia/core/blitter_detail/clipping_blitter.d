module skia.core.blitter_detail.clipping_blitter;

private {
  import skia.core.blitter;
  import skia.core.region;
  import skia.core.rect;
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
    if (!fitsIntoRange!(float, "[)")(y, this.clip.top, this.clip.bottom))
      return;

    xStart = clampToRange!(float)(xStart, this.clip.left, this.clip.right);
    xEnd = clampToRange!(float)(xEnd, this.clip.left, this.clip.right);

    if (xStart < xEnd)
      this.blitter.blitFH(y, xStart, xEnd);
  }
}

class RegionBlitter : Blitter {
  Blitter blitter;
  Region clip;
  this(Blitter blitter, in Region clip) {
    this.blitter = blitter;
    this.clip = clip;
  }
  void blitFH(float y, float xStart, float xEnd)
  {
    //! TODO: regionblitter
    assert(0, "unimplemented");
  }
}
