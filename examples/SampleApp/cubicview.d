module SampleApp.cubicview;

private {
  debug private import std.stdio;
  import std.math : floor;
  import std.conv : to;

  import skia.core.canvas;
  import skia.core.color;
  import skia.core.path;
  import skia.core.paint;
  import guip.point;
  import guip.rect;
  import guip.size;
  import skia.views.view;
}


class CubicView : View
{
  FPoint[4] controlPts;
  int dragIdx;
  this() {
    this._flags.visible = true;
    this._flags.enabled = true;
    this.dragIdx = -1;
    this.onSizeChange();
  }

  override void onSizeChange() {
    auto bounds = this.bounds.inset(40, 40);
    this.controlPts = fRect(bounds).toQuad();
  }

  override void onDraw(Canvas canvas) {
    scope auto paintCircle = new Paint(Black.a = 120);
    paintCircle.strokeWidth = 2;
    paintCircle.fillStyle = Paint.Fill.Stroke;
    foreach(pt; this.controlPts) {
      canvas.drawCircle(pt, 5.0f, paintCircle);
    }
    Path path;
    path.moveTo(controlPts[0]);
    foreach(pt; this.controlPts[1..$]) {
      path.lineTo(pt);
    }
    scope auto paintLine = new Paint(Orange.a = 80);
    paintLine.strokeWidth = 10;
    paintLine.antiAlias = true;
    paintLine.fillStyle = Paint.Fill.Stroke;
    paintLine.joinStyle = Paint.Join.Round;
    paintLine.capStyle = Paint.Cap.Round;
    canvas.drawPath(path, paintLine);

    path.reset();
    paintLine.fillStyle = Paint.Fill.Stroke;
    path.moveTo(this.controlPts[0]);
    path.cubicTo(this.controlPts[1], this.controlPts[2], this.controlPts[3]);
    paintLine.color = Black.a = 100;
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

  override void onPointerMove(IPoint pt) {
    this.moveControlPoint(fPoint(pt));
  }

  override void onButtonRelease(IPoint pt) {
    this.moveControlPoint(fPoint(pt));
    this.dragIdx = -1;
  }

  void moveControlPoint(FPoint fpt) {
    if (this.dragIdx != -1 && this.controlPts[this.dragIdx] != fpt) {
      auto dirty = FRect.calcBounds(this.controlPts).inset(-6, -6);

      this.controlPts[this.dragIdx] = fpt;

      dirty.join(FRect.calcBounds(this.controlPts).inset(-6, -6));
      this.inval(dirty.roundOut());
    }
  }
}
