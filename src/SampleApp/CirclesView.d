module circlesview;

private {
  debug private import std.stdio : writeln;
  import std.algorithm : min;
  import std.math : PI;

  import skia.core.canvas;
  import skia.core.color : Black, Red;
  import skia.core.paint;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.size;
  import skia.views.view;
}


class CirclesView : View
{
  Paint paint, framePaint;
  const float cRad;
  this(float cRad = 5.0f) {
    this.cRad = cRad;
    this._flags.visible = true;
    this._flags.enabled = true;
    this.paint = new Paint(Black);
    this.framePaint = new Paint(Red);
    this.framePaint.fillStyle = Paint.Fill.Stroke;
  }

  override void onDraw(Canvas canvas) {
    //auto frame = this.bounds;
    //canvas.drawRect(frame, framePaint);
    canvas.translate(this.bounds.centerX, this.bounds.centerY);

    const auto dist = to!int(min(this.bounds.centerX, this.bounds.centerY)
                             - 2 * this.cRad);
    auto steps = min(this.width, this.height) * PI / (3*this.cRad);
    auto degInc = 360 / steps;

    scope auto paint = new Paint(Black);
    paint.antiAlias = true;

    auto scaled = 1.0f;
    auto const scaleFac = 0.9945;
    do {
      canvas.drawCircle(IPoint(0, -dist), this.cRad, paint);
      canvas.scale(scaleFac, scaleFac);
      scaled *= scaleFac;
      canvas.rotate(degInc, this.x + 100, this.y + 100);
    } while(scaled > 1e-2f);
  }
}

