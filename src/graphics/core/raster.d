module graphics.core.raster;

import std.algorithm, std.math, std.range;
import graphics.core.blitter, graphics.core.blitter_detail.clipping_blitter,
    graphics.core.path, graphics.core.wavelet.wavelet;
import guip.rect, guip.point;


void fillIRect(Blitter)(IRect rect, in IRect clip, Blitter blitter)
{
    if (rect.empty)
        return;

    rect.intersect(clip) || assert(0);
    blitter.blitRect(rect);
}

void fillPath(in Path path, in IRect clip, Blitter blitter)
in
{
    assert(!clip.empty && !path.empty);
}
body
{
    auto ir = path.ibounds;

    if ((blitter = getClippingBlitter(blitter, clip, ir)) !is null)
        blitEdges(path, clip, blitter, ir.top, ir.bottom);
}

Blitter getClippingBlitter(Blitter blitter, in IRect clip, in IRect ir)
{
    if (!clip.intersects(ir))
        return null;

    if (clip.left >= ir.left || clip.right <= ir.right) // TODO: maybe use > <
        return new RectBlitter(blitter, clip);
    else
        return blitter;
}
