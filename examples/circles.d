import graphics._, guip._, graphics.core.matrix, graphics.effect.patheffects, graphics.core.shader;
import std.datetime, std.math, std.stdio;

void paint(Canvas canvas)
{
    scope auto paintC = new Paint(Color.Black);
    paintC.fillStyle = Paint.Fill.Stroke;
    paintC.strokeWidth = 1;
    paintC.pathEffect = new DashPathEffect([2.0f, 1.0f]);

    canvas.drawColor(Color.White);
    canvas.translate(IPoint(400, 400));

    auto crad = 10.0f;
    auto rad = 400.0f - crad;
    auto angle = 360 * 4 * crad / (2 * PI * rad);
    auto arrow = FPoint(rad, 0);
    foreach(_; 0 .. 3_000)
    {
        canvas.drawCircle(arrow, crad, paintC);
        canvas.scale(0.999, 0.999);
        canvas.rotate(angle);
    }
}

void render()
{
    auto bmp = Bitmap(Bitmap.Config.ARGB_8888, 800, 800);
    scope auto canvas = new Canvas(bmp);
    paint(canvas);
    bmp.save("out.png");
}

void main()
{
    auto sw = StopWatch(AutoStart.yes);
    render();
    sw.stop;
    writeln(sw.peek.msecs);
}
