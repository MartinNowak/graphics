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
    canvas.translate(25, 25);
    scope auto paintRect = new Paint(Red);
    paintRect.antiAlias = true;
    canvas.drawRoundRect(IRect(100, 100), 5, 5, paintRect);

    scope auto paintCircle = new Paint(Color(0x808080FF));
    paintCircle.antiAlias = true;
    canvas.drawCircle(point(25, 25), 50, paintCircle);
  }
}
