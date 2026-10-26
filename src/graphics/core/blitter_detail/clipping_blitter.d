module graphics.core.blitter_detail.clipping_blitter;

private {
  import guip.bitmap;
  import graphics.core.blitter;
  import guip.rect;
  import graphics.math.clamp;
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

unittest
{
    class Recorder : graphics.core.blitter.Blitter
    {
        int[] log;
        override void blitH(int y, int xstart, int xend) {
            log ~= [y, xstart, xend];
        }
        override void blitAlphaH(int y, int xstart, int xend, ubyte alpha) {
            log ~= [y, xstart, xend, alpha];
        }
        override void blitMask(int x, int y, in Bitmap mask) {}
    }

    auto rec = new Recorder;
    auto clip = new RectBlitter(rec, IRect(2, 2, 6, 6));

    // rows outside the vertical clip are dropped
    clip.blitH(1, 0, 10);
    clip.blitH(6, 0, 10); // bottom is exclusive
    assert(rec.log.length == 0);

    // horizontal span is clamped to the clip
    clip.blitH(4, 0, 10);
    assert(rec.log == [4, 2, 6]);

    // fully outside to the right -> nothing (both clamp to 6)
    rec.log = null;
    clip.blitH(4, 7, 9);
    assert(rec.log.length == 0);

    // partially inside to the left
    rec.log = null;
    clip.blitH(4, -5, 3);
    assert(rec.log == [4, 2, 3]);

    // same logic for the global-alpha variant
    rec.log = null;
    clip.blitAlphaH(3, 0, 10, 128);
    assert(rec.log == [3, 2, 6, 128]);
}
