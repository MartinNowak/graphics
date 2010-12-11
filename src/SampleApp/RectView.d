module RectView;

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
    this.setLoc(loc);
    this.setSize(size);
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    auto gray = DarkGray;
    gray.a = 50;
    scope auto paint2 = new Paint(gray);
    canvas.drawRoundRect(this.bounds, 30, 30, paint2);

    canvas.drawCircle(this.bounds.center, 80, paint);
  }
}