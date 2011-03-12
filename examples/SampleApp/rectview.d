module SampleApp.rectview;

private {
  debug private import std.stdio : writeln;

  import guip.size;
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
  this(IPoint loc=IPoint(), ISize size=ISize(), Color color=Orange) {
    this.paint = new Paint(color);
    this.paint.fillStyle = Paint.Fill.Stroke;
    this.paint.antiAlias = true;
    this.setLoc(loc);
    this.setSize(size);
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    scope auto paintLine = new Paint(Green.a = 60);
    paintLine.fillStyle = Paint.Fill.Stroke;
    paintLine.strokeWidth = 5;
    auto area = this.bounds.inset(10, 10);
    canvas.drawRoundRect(area, 30, 30, paintLine);

    paintLine.fillStyle = Paint.Fill.Fill;
    paintLine.color = Blue.a = 20;
    area = area.inset(10, 10);
    canvas.drawRoundRect(area, 30, 30, paintLine);
  }
}
