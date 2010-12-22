module circlesview;

private {
  debug private import std.stdio : writeln;
  import std.algorithm : min;
  import std.math : PI;

  import skia.core.canvas;
  import skia.core.color : Black, Red, Green, Cyan;
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
  this(float cRad = 10.0f) {
    this.cRad = cRad;
    this._flags.visible = true;
    this._flags.enabled = true;
    this.paint = new Paint(Black);
    this.framePaint = new Paint(Red);
    this.framePaint.fillStyle = Paint.Fill.Stroke;
  }

  override void onDraw(Canvas canvas) {
    /*
    auto matrix = canvas.getMatrix();
    matrix[2][0] = 0.05f;
    canvas.setMatrix(matrix);
    */
    canvas.translate(this.bounds.centerX, this.bounds.centerY);
    const auto dist = to!int(min(this.bounds.centerX, this.bounds.centerY)
                             - 2 * this.cRad);
    auto steps = min(this.width, this.height) * PI / (3*this.cRad);
    auto degInc = 360 / steps;

    auto cyan = Cyan; cyan.a = 100; cyan.g = 100;
    scope auto paintC = new Paint(cyan);
    paintC.antiAlias = true;
    scope auto paintR = new Paint(Red);
    paintR.antiAlias = true;

    auto scaled = 1.0f;
    auto const scaleFac = 0.998;
    do {
      canvas.drawCircle(IPoint(0, -dist), 0.5*this.cRad, paintR);
      canvas.drawCircle(IPoint(0, -dist), this.cRad, paintC);
      canvas.scale(scaleFac, scaleFac);
      scaled *= scaleFac;
      canvas.rotate(degInc, fPoint(this.loc + this.bounds.center));
      //      writefln("matrix:%s", canvas.curMatrix);
    } while(scaled > 1e-2f);
  }
}

