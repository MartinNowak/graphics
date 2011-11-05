module graphics.core.patheffect;

import std.algorithm, std.math;
import guip.point, guip.rect;
import graphics.core.path, graphics.core.stroke, graphics.core.stroke_detail.capper, graphics.core.stroke_detail.joiner,
    graphics.core.path_detail.path_measure;

// TODO: try to make pure
alias Path delegate(in Path path) /*pure*/ PathEffect;

PathEffect strokePath(float width, CapStyle caps=CapStyle.Butt, JoinStyle joins=JoinStyle.Miter)
{
    Path impl(in Path path) /*pure*/
    {
        auto stroker = Stroke(width, caps, joins);
        return stroker.strokePath(path);
    }
    return &impl;
}

PathEffect dashPath(immutable float[] intervals)
{
    immutable intervalLength = reduce!"a+b"(0.0f, intervals);

    Path impl(in Path path) /*pure*/
    {
        auto meas = PathMeasure(path);

        auto scale = intervalLength > meas.length
            ? meas.length / intervalLength
            : meas.length / (floor(meas.length / intervalLength) * intervalLength);

        Path result;
        for (auto dist = 0.0f; dist < meas.length;)
        {
            foreach(i, dash; intervals)
            {
                auto newDist = dist + dash * scale;
                if ((i & 0x1) == 0)
                    meas.appendRangeToPath(dist, newDist, result);
                dist = newDist;
            }
        }
        return result;
    }
    return &impl;
}

PathEffect dotPath(float dotsize)
{
    return dotPath(dotsize, 2 * dotsize);
}

PathEffect dotPath(float dotsize, float dotdist)
{
    Path impl(in Path path) /*pure*/
    {
        auto meas = PathMeasure(path);

        auto scaledDist = meas.length / floor(meas.length / dotdist);

        Path result;

        for (auto dist = 0.0f; dist < meas.length; dist += scaledDist)
        {
            auto pos = meas.getPosAtDistance(dist);
            auto diag = 0.5 * FVector(dotsize, dotsize);
            auto fr = FRect(pos - diag, pos + diag);
            result.addOval(fr);
        }
        return result;
    }
    return &impl;
}
