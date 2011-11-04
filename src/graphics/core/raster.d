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
{
    if (clip.empty)
    {
        return;
    }

    auto ir = path.ibounds;

    if (ir.empty)
    {
        if (path.inverseFillType)
        {
            blitter.blitRect(clip);
        }
        return;
    }

    blitter = getClippingBlitter(blitter, clip, ir);

    if (!(blitter is null))
    {
        if (path.inverseFillType)
        {
            blitAboveAndBelow(blitter, ir, clip);
        }
        else
        {
            graphics.core.wavelet.wavelet.blitEdges(path, clip, blitter, ir.top, ir.bottom);
        }
    }
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

void blitAboveAndBelow(Blitter blitter, in IRect ir, in IRect clip)
{
    assert(0, "unimplemented");
}

void hairPath(in Path path, in IRect clip, Blitter blitter)
{
    if (path.empty)
    {
        return;
    }

    auto ir = path.ibounds.inset(-1, -1);

    blitter = getClippingBlitter(blitter, clip, ir);

    if (blitter)
    {
        if (path.inverseFillType)
        {
            // inverse and stroke ?
            blitAboveAndBelow(blitter, ir, clip);
        }
        else
        {
            assert(0, "unimplemented");
        }
    }
}
