module examples.circles;

import graphics._, guip._, graphics.core.matrix, graphics.effect.patheffects, graphics.core.shader;
import std.math;

void circles(string fpath)
{
    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, 800, 800);
    scope auto canvas = new Canvas(bmp);
    scope auto paint = new Paint(Color.Black);
    paint.fillStyle = Paint.Fill.Stroke;
    paint.strokeWidth = 1;
    paint.pathEffect = new DashPathEffect([2.0f, 1.0f]);

    canvas.drawColor(Color.White);

    canvas.translate(IPoint(400, 400));

    auto crad = 10.0f;
    auto rad = 400.0f - crad;
    auto angle = 360 * 4 * crad / (2 * PI * rad);
    auto arrow = FPoint(rad, 0);
    foreach(_; 0 .. 3_000)
    {
        canvas.drawCircle(arrow, crad, paint);
        canvas.scale(0.999, 0.999);
        canvas.rotate(angle);
    }

    bmp.save(fpath);
}
