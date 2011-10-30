module graphics.core.scan;

import std.algorithm, std.math, std.range;
import graphics.core.blitter, graphics.core.blitter_detail.clipping_blitter,
    graphics.core.path, graphics.core.wavelet.raster,
    graphics.math._;
import guip.rect, guip.point;


// debug=WALK_EDGES; // verbose tracing for walk_edges
debug(WALK_EDGES) import std.stdio;

void fillIRect(Blitter)(IRect rect, in IRect clip, Blitter blitter) {
  if (rect.empty)
    return;

  if (rect.intersect(clip))
    blitter.blitRect(rect);
  else
    assert(0);
}

enum AAScale = 4;
enum AAStep = 1.0f / AAScale;

void antiFillPath(in Path path, in IRect clip,
                  Blitter blitter) {
  return fillPathImpl!AAScale(path, clip, blitter);
}
void fillPath(in Path path, in IRect clip,
              Blitter blitter) {
  return fillPathImpl!1(path, clip, blitter);
}

void fillPathImpl(size_t Scale)
(in Path path, in IRect clip, Blitter blitter) {
  if (clip.empty) {
    return;
  }

  auto ir = path.ibounds;

  if (ir.empty) {
    if (path.inverseFillType) {
      blitter.blitRect(clip);
    }
    return;
  }

  blitter = getClippingBlitter(blitter, clip, ir);

  if (!(blitter is null)) {
    if (path.inverseFillType) {
      blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      graphics.core.wavelet.raster.blitEdges(path, clip, blitter, ir.top, ir.bottom);
    }
  }
}

Blitter getClippingBlitter(Blitter blitter, in IRect clip, in IRect ir) {
  if (!clip.intersects(ir))
    return null;

  if (clip.left >= ir.left || clip.right <= ir.right) // TODO: maybe use > <
    return new RectBlitter(blitter, clip);
  else
    return blitter;
}

void blitAboveAndBelow(Blitter blitter, in IRect ir, in IRect clip) {}

version(unittest) {
  private import guip.point;
}


void antiHairPath(in Path path, in IRect clip,
                  Blitter blitter) {
  return hairPathImpl(path, clip, blitter, AAScale);
}
void hairPath(in Path path, in IRect clip,
              Blitter blitter) {
  return hairPathImpl(path, clip, blitter, 1);
}

void hairPathImpl(in Path path, in IRect clip,
                     Blitter blitter, int stepScale) {
  if (path.empty) {
    return;
  }

  auto ir = path.ibounds.inset(-1, -1);

  blitter = getClippingBlitter(blitter, clip, ir);

  if (blitter) {
    // TODO chose SkRgnBlitter, SkRectBlitter
    if (path.inverseFillType) {
      // inverse and stroke ?
      // blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      assert(0, "unimplemented");
    }
  }
}
