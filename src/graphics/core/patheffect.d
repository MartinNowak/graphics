module graphics.core.patheffect;

import std.algorithm, std.math;
import guip.point, guip.rect;
import graphics.core.path, graphics.core.stroke, graphics.core.stroke_detail.capper, graphics.core.stroke_detail.joiner,
    graphics.core.path_detail.path_measure;
public import graphics.core.stroke_detail.capper : CapStyle;
public import graphics.core.stroke_detail.joiner : JoinStyle;

Path strokePath
(in Path path, float width, CapStyle caps=CapStyle.Butt, JoinStyle joins=JoinStyle.Miter)
{
    auto stroker = Stroke(width, caps, joins);
    return stroker.strokePath(path);
}

Path dashPath(in Path path, in float[] intervals)
{
    immutable intervalLength = reduce!"a+b"(0.0f, intervals);

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

Path dotPath(in Path path, float dotsize)
{
    return dotPath(path, dotsize, 2 * dotsize);
}

Path dotPath(in Path path, float dotsize, float dotdist)
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

unittest
{
    import std.math : abs;
    import std.conv : text;

    Path line;
    line.moveTo(FPoint(10, 10));
    line.lineTo(FPoint(90, 10));

    // stroking a horizontal line widens the bounds by half the width
    auto s = strokePath(line, 4);
    assert(!s.empty);
    assert(abs(s.bounds.left  - 10) < 1e-2);
    assert(abs(s.bounds.right - 90) < 1e-2);
    assert(abs(s.bounds.top   -  8) < 1e-2);
    assert(abs(s.bounds.bottom- 12) < 1e-2);

    // round caps extend further along the line direction
    auto sr = strokePath(line, 4, CapStyle.Round);
    assert(sr.bounds.left < s.bounds.left);
    assert(sr.bounds.right > s.bounds.right);

    // square caps extend by the stroke radius past the endpoints
    auto sq = strokePath(line, 4, CapStyle.Square);
    assert(abs(sq.bounds.left - 8) < 1e-2 && abs(sq.bounds.right - 92) < 1e-2);

    // an L-shaped polyline strokes fine with each join style
    Path l;
    l.moveTo(FPoint(10, 10));
    l.lineTo(FPoint(50, 10));
    l.lineTo(FPoint(50, 50));
    foreach (j; [JoinStyle.Miter, JoinStyle.Round, JoinStyle.Bevel])
    {
        auto ls = strokePath(l, 6, CapStyle.Butt, j);
        assert(!ls.empty);
        assert(ls.bounds.width >= 43 && ls.bounds.height >= 43);
    }

    // dashes: [2,2] along an 80-long line gives 20 on-intervals
    auto d = dashPath(line, [2.0f, 2.0f]);
    size_t moves;
    foreach (v; d.verbs)
        if (v == Path.Verb.Move)
            ++moves;
    assert(moves == 20, text(moves));

    // dots every 20 units along the 80-unit line: 0, 20, 40, 60
    auto dots = dotPath(line, 2, 20);
    moves = 0;
    foreach (v; dots.verbs)
        if (v == Path.Verb.Move)
            ++moves;
    assert(moves == 4, text(moves));
    dots = dotPath(line, 2);   // dotdist = 2*dotsize -> 20 dots
    assert(!dots.empty);
}
