module SampleApp.cubicview;

debug import std.stdio;
import std.math : floor;
import std.conv : to;
import skia.core.canvas, skia.views.view2, skia.core.pmcolor, skia.core.path, skia.core.paint;
import guip.event, guip.point, guip.rect, guip.size, layout.hint;


class CubicView : View
{
  FPoint[4] controlPts;
  int dragIdx = -1;

  override void onResize(ResizeEvent e) {
    auto bounds = IRect(e.area.size).inset(40, 40);
    this.controlPts = fRect(bounds).toQuad();
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
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

  override void onButton(ButtonEvent e, ISize size) {
    if (e.isPress()) {
      auto checkRect = FRect(20, 20);
      auto fpt = fPoint(e.pos);
      foreach(idx, ctrlPt; this.controlPts) {
        checkRect.center = ctrlPt;
        if (checkRect.contains(fpt))
          this.dragIdx = cast(int)idx;
      }
    } else {
      this.moveControlPoint(fPoint(e.pos));
      this.dragIdx = -1;
    }
  }

  override void onMouse(MouseEvent e, ISize size) {
    this.moveControlPoint(fPoint(e.pos));
  }

  void moveControlPoint(FPoint fpt) {
    if (this.dragIdx != -1 && this.controlPts[this.dragIdx] != fpt) {
      auto dirty = FRect.calcBounds(this.controlPts).inset(-6, -6);

      this.controlPts[this.dragIdx] = fpt;

      dirty.join(FRect.calcBounds(this.controlPts).inset(-6, -6));
      this.requestRedraw(dirty.roundOut());
    }
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(600, 0.5), Hint(600, 0.5));
  }
}
