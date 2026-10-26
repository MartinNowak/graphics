module graphics.core.testing;

// Helpers shared by the unittest blocks in this package. version(unittest)
// keeps everything here out of regular library builds entirely (GDC has
// defined the unittest version identifier for -unittest builds since
// well before this repo's baseline); coverage.sh leaves this module out
// of the coverage report as well.
version (unittest):

import graphics.core.pmcolor, graphics.core.paint, graphics.core.path;
import guip.bitmap, guip.color, guip.point;

/// A w×h ARGB_8888 bitmap, erased to bg (black by default).
Bitmap blackBitmap(int w, int h)
{
    auto bm = Bitmap(Bitmap.Config.ARGB_8888, w, h);
    bm.eraseColor(Color.Black);
    return bm;
}

/// The pixel at (x, y) as a PMColor.
PMColor pixel(in Bitmap bm, int x, int y)
{
    return bm.getLine!PMColor(y)[x];
}

/// True when any pixel of the bitmap has ink (a set color channel). Alpha is
/// ignored so an erased opaque background doesn't count as ink. Handy for
/// "something was drawn" assertions where the exact shape isn't checked.
bool inked(in Bitmap bm)
{
    foreach (y; 0 .. bm.height)
        foreach (px; bm.getLine!PMColor(y))
            if (px.r > 0 || px.g > 0 || px.b > 0)
                return true;
    return false;
}

/// A paint with a solid color. The shader is explicitly nulled because GDC
/// leaves uninitialized struct fields with NaN garbage.
Paint solidPaint(Color c)
{
    Paint p;
    p.shader = null;
    p.color = c;
    return p;
}

/// Absolute closeness for floats: |a - b| <= tol.
bool near(T)(T a, T b, T tol)
{
    immutable d = a > b ? a - b : b - a;
    return d <= tol;
}

/// Point closeness: both coordinates within tol.
bool nearP(T)(Point!T a, Point!T b, T tol)
{
    return near(a.x, b.x, tol) && near(a.y, b.y, tol);
}

/// Path through the given points: moveTo the first one, lineTo through the rest.
Path polyline(FPoint[] pts...)
{
    Path p;
    p.moveTo(pts[0]);
    foreach (pt; pts[1 .. $])
        p.lineTo(pt);
    return p;
}

unittest
{
    // sanity: the helpers themselves
    auto bm = blackBitmap(2, 2);
    assert(pixel(bm, 1, 1) == PMColor(Color.Black));
    assert(!bm.inked);
    bm.eraseColor(Color.Blue);
    assert(bm.inked);

    auto p = solidPaint(Color.Red);
    assert(p.color == Color.Red && p.shader is null);

    assert(near(1.0f, 1.001f, 1e-2f) && !near(1.0f, 1.1f, 1e-2f));
    assert(nearP(FPoint(1, 2), FPoint(1.001f, 2), 1e-2f));

    auto pl = polyline(FPoint(0, 0), FPoint(1, 0), FPoint(1, 1));
    assert(pl.verbs == [Path.Verb.Move, Path.Verb.Line, Path.Verb.Line]);
    assert(pl.points == [FPoint(0, 0), FPoint(1, 0), FPoint(1, 1)]);
}
