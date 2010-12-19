module rectview;

private {
  debug private import std.stdio : writeln;

  import skia.core.size;
  import skia.core.canvas;
  import skia.core.color;
  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;
  import skia.views.view;
}


class RectView : View
{
  Paint paint;
  this(IPoint loc, ISize size, Color color) {
    this.paint = new Paint(color);
    this.paint.fillStyle = Paint.Fill.Stroke;
    this.paint.antiAlias = true;
    this.setLoc(loc);
    this.setSize(size);
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    //    canvas.rotate(20);
    //    canvas.rotate(2, fPoint(this.bounds.center));
    canvas.rotate(5);
    scope auto paintRect = new Paint(Black.a = 200);
    paintRect.antiAlias = true;
    canvas.drawRoundRect(IRect(IPoint(), this.bounds.center), 40, 40, paintRect);

    auto color = Color(0x108080FF);
    color.a = 80;
    scope auto paintCircle = new Paint(color);
    paintCircle.antiAlias = true;
    canvas.drawCircle(this.bounds.center, 50, paintCircle);
  }
}
