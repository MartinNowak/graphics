module SampleApp.quadview;

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
  import guip.size;
  import skia.views.view;
}


class QuadView : View
{
  FPoint[3] controlPts;
  int dragIdx;
  this() {
    this._flags.visible = true;
    this._flags.enabled = true;
    this.dragIdx = -1;
  }

  override void onSizeChange() {
    auto bounds = this.bounds;
    bounds.inset(20, 20);
    this.controlPts = fRect(bounds).toQuad()[0..3];
  }

  override void onDraw(Canvas canvas) {
    scope auto paintCircle = new Paint(Green.a = 120);
    foreach(pt; this.controlPts) {
      canvas.drawCircle(pt, 15.0f, paintCircle);
    }
    Path path;
    path.moveTo(controlPts[0]);
    foreach(pt; this.controlPts[1..$]) {
      path.lineTo(pt);
    }
    scope auto paintLine = new Paint(Black.a = 80);
    paintLine.fillStyle = Paint.Fill.Stroke;
    paintLine.strokeWidth = 10;
    paintLine.joinStyle = Paint.Join.Round;
    paintLine.capStyle = Paint.Cap.Round;
    canvas.drawPath(path, paintLine);

    path.reset();
    path.moveTo(this.controlPts[0]);
    path.quadTo(this.controlPts[1], this.controlPts[2]);
    paintLine.color.a = 200;
    canvas.drawPath(path, paintLine);
  }

  override void onButtonPress(IPoint pt) {
    auto checkRect = FRect(20, 20);
    auto fpt = fPoint(pt);
    foreach(idx, ctrlPt; this.controlPts) {
      checkRect.center = ctrlPt;
      if (checkRect.contains(fpt))
        this.dragIdx = cast(int)idx;
    }
  }
  override void onButtonRelease(IPoint pt) {
    auto fpt = fPoint(pt);
    if (this.dragIdx >= 0 && this.controlPts[this.dragIdx] != fpt) {
        this.controlPts[this.dragIdx] = fpt;
        this.inval(this.bounds);
    }
    this.dragIdx = -1;
  }
}
