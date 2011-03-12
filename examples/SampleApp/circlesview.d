module SampleApp.circlesview;

private {
  debug private import std.stdio : writeln;
  import std.algorithm : min, max;
  import std.conv : to;
  import std.math : PI;

  import skia.core.canvas;
  import skia.core.color : Black, Red, Green, Cyan;
  import skia.core.paint;
  import guip.point;
  import guip.rect;
  import guip.size;
  import skia.views.view;
}


class CirclesView : View
{
  const float cRad;
  this(float cRad = 10.0f) {
    this.cRad = cRad;
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    /*
    auto matrix = canvas.getMatrix();
    matrix[2][0] = 0.05f;
    canvas.setMatrix(matrix);
    */
    canvas.translate(fPoint(this.bounds.center));
    const auto dist = to!int(max(this.bounds.centerX, this.bounds.centerY)
                             - 2 * this.cRad);
    auto steps = 2 * PI * dist / (3*this.cRad);
    auto degInc = 360 / steps;

    auto cyan = Cyan; cyan.a = 100; cyan.g = 100;
    scope auto paintC = new Paint(Black);
    paintC.antiAlias = true;
    paintC.fillStyle = Paint.Fill.Stroke;
    paintC.strokeWidth = 0.1;
    scope auto paintR = new Paint(Red);
    paintR.antiAlias = true;

    auto scaled = 1.0f;
    auto const scaleFac = 0.998;
    do {
      canvas.drawCircle(IPoint(0, -dist), this.cRad, paintC);
      canvas.drawCircle(IPoint(0, -dist), 0.2*this.cRad, paintR);
      canvas.scale(scaleFac, scaleFac);
      scaled *= scaleFac;
      canvas.rotate(degInc, fPoint(this.loc + this.bounds.center));
      //      writefln("matrix:%s", canvas.curMatrix);
    } while(scaled > 1e-2f);
  }
}

