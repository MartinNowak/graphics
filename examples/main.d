module examples.main;

import std.algorithm, std.datetime, std.stdio, std.typecons;
import examples.circles, examples.zrusin_path;

Tuple!(ulong, ulong) measure()
{
    Tuple!(ulong, ulong) res;

    auto sw = StopWatch(AutoStart.yes);
    circles("circles.png");
    res[0] = sw.peek.usecs;

    sw.reset();
    zrusin_path("zrusin.png");
    res[1] = sw.peek.usecs;

    return res;
}

void main()
{
    auto mins = tuple(ulong.max, ulong.max);

    while (true)
    {
        auto vals = measure();
        vals[0] = min(vals[0], mins[0]);
        vals[1] = min(vals[1], mins[1]);
        if (vals != mins)
        {
            mins = vals;
            writef("\rcircles %s us, zrusing %s us", mins[]);
            stdout.flush();
        }
    }
}
