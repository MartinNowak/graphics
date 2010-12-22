module sineview;

private {
  debug private import std.stdio : writeln;
  import std.math : floor;
  import std.conv : to;

  import skia.core.canvas;
  import skia.core.color;
  import skia.core.path;
  import skia.core.paint;
  import skia.core.point;
  import skia.core.rect;
  import skia.core.size;
  import skia.views.view;
}


class SineView : View
{
  this() {
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    scope auto paintBG = new Paint(White);
    auto y = to!int(this.height * 0.3);
    auto bg = IRect(0, y, this.width, this.height - y);
    canvas.drawRect(bg, paintBG);

    auto path = Path();
    auto cy = this.bounds.centerY;
    auto dx = this.width * 0.16;
    auto dy = this.height * 0.35;
    auto count = to!uint(floor(this.width  / dx));
    auto rem = (this.width - (count * dx)) * 0.5;
    auto x = rem;
    path.moveTo(FPoint(x, cy));
    while (count--) {
      path.quadTo(FPoint(x+0.25*dx, cy-dy), FPoint(x+0.5*dx, cy));
      path.quadTo(FPoint(x+0.75*dx, cy+dy), FPoint(x+dx, cy));
      x += dx;
    }
    path.moveTo(FPoint(x + rem, cy+0.5*dy));
    path.lineTo(FPoint(0, cy-0.5*dy));
    scope auto paint = new Paint(Red.a=120);
    canvas.drawPath(path, paint);
  }
}

