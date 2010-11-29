module skia.core.scan;

import skia.core.blitter;
import skia.core.path;
import skia.core.region;
import skia.core.rect;
import skia.core.regionpath;

static void fillPath(Blitter)(in Path path, in Region clip, Blitter blitter)
{
  if (clip.empty) {
    return;
  }

  if (path.bounds.empty) {
    if (path.inverseFillType) {
      blitter.blitRegion(clip);
    }
    return;
  }

  if (!clip.bounds.intersects(path.bounds))
    return;

  // TODO chose SkRgnBlitter, SkRectBlitter
  if (path.inverseFillType) {
    blitAboveAndBelow(blitter, path.bounds, clip);
  }
  else {
    //    fillPath(path, clipper.getClipRect(), blitter, ir.top, ir.bottom, 0, clip);
  }
}

void blitAboveAndBelow(Blitter blitter, in IRect ir, in Region clip) {}

unittest
{
  auto path = Path();
  path.toggleInverseFillType();
  auto clip = Region(IRect(100, 100));
  scope auto blitter = new RgnBuilder();

  fillPath(path, clip, blitter);
  assert(blitter.computeRunCount() > 0);
}
