module SampleApp.circlesview;

private {
  debug private import std.stdio : writeln;
  import std.algorithm : min, max;
  import std.conv : to;
  import std.math : PI, cos, sin;

  import skia.core.canvas;
  import skia.core.pmcolor : Black, Red, Green, Cyan;
  import skia.core.paint;
  import skia.effect.dashpatheffect;
  import guip.event, guip.point, guip.rect, guip.size;
  import skia.views.view2;
  import layout.hint;
}


class CirclesView : View
{
  const float cRad;
  this(float cRad = 10.0f) {
    this.cRad = cRad;
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    /*
    auto matrix = canvas.getMatrix();
    matrix[2][0] = 0.05f;
    canvas.setMatrix(matrix);
    */
    auto bounds = IRect(size);

    canvas.translate(fPoint(bounds.center));
    const auto dist = to!int(max(bounds.centerX, bounds.centerY)
                             - 2 * this.cRad);
    auto steps = 2 * PI * dist / (3*this.cRad);
    auto degInc = 2 * PI / steps;

    auto cyan = Cyan; cyan.a = 180; cyan.g = 100;
    scope auto paintC = new Paint(cyan);
    paintC.antiAlias = true;
    paintC.fillStyle = Paint.Fill.Stroke;
    paintC.strokeWidth = 0.2;
    paintC.pathEffect = new DashPathEffect([2.f, 1.f]);

    scope auto paintR = new Paint(Red);
    paintR.antiAlias = true;

    auto scaled = 1.0f;
    auto const scaleFac = 0.998;
    auto center = FPoint(0, dist);

    double[2][2] rot;
    rot[0][0] = cos(degInc);
    rot[0][1] = -sin(degInc);
    rot[1][0] = -rot[0][1];
    rot[1][1] = rot[0][0];
    do {
      canvas.drawCircle(center, this.cRad * scaled, paintC);
      canvas.drawCircle(center, 0.2*this.cRad * scaled, paintR);

      center = FPoint(
          center.x * rot[0][0] + center.y * rot[0][1],
          center.x * rot[1][0] + center.y * rot[1][1]);

      center.setLength(dist * scaled);

      scaled *= scaleFac;
    } while(scaled > 1e-1f);
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(1200, 0.2), Hint(1200, 0.2));
  }
}

