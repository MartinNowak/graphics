module examples.circles;

import graphics._, guip._, graphics.core.matrix, graphics.core.patheffect, graphics.core.shader;
import std.math;

void circles(string fpath)
{
    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, 800, 800);
    scope auto canvas = new Canvas(bmp);

    canvas.drawColor(Color.White);

    canvas.translate(IPoint(400, 400));

    enum crad = 10.f;
    enum rad = 400.f - crad;

    Path path;
    path.addOval(FRect(rad - crad, 0 - crad, rad + crad, 0 + crad));
    path = dashPath(path, [2.0f, 1.0f]);
    path = strokePath(path, 1.0f);

    auto angle = 360 * 4 * crad / (2 * PI * rad);
    foreach(_; 0 .. 3_000)
    {
        canvas.drawPath(path, Paint(Color.Black));
        canvas.scale(0.999, 0.999);
        canvas.rotate(angle);
    }

    bmp.save(fpath);
}
