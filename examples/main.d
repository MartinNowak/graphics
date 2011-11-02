module examples.main;

import std.datetime, std.stdio;
import examples.circles, examples.zrusin_path;

void main()
{
    size_t cnt = 2;

    StopWatch sw;

    sw.start;
    foreach(_; 0 .. cnt)
        circles("circles.png");
    sw.stop;
    writeln("circles ", sw.peek.msecs * 1.0 / cnt);
    sw.reset;
    sw.start;
    foreach(_; 0 .. cnt)
        zrusin_path("zrusin.png");
    sw.stop;
    writeln("zrusin ", sw.peek.msecs * 1.0 / cnt);
}
