module skia.views.zoom;

import skia.views.view2;
import skia.core.canvas, skia.core.matrix;
import std.conv, std.math;
import guip.event, guip.point, guip.rect, guip.size;

class ZoomView : ParentView {
  enum Direction {
    Horizontal=0x1,
    Vertical=0x2,
    Both=0x3,
  }

  this(View child, Direction direction=Direction.Both) {
    super(child);
    this.direction = direction;
  }

  void addScale(IPoint center, float sc) {
    this.translation =
      this.translation * this.scaleVec(sc) +
      fPoint(center) * (FPoint(1, 1) - this.scaleVec(sc));
    this.scale *= sc;
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (e.button.right) {
      if (e.isPress) {
        this.zoomAnchor = e.pos;
      } else {
        this.addScale(this.zoomAnchor, this.pendingScale);
        this.pendingScale = 1.f;
        this.zoomAnchor = IPoint(0, 0);
      }
    } else if (e.button.wheelup) {
      this.addScale(e.pos, 1.1f);
    } else if (e.button.wheeldown) {
      this.addScale(e.pos, 1.0f / 1.1f);
    } else {
      e.pos = this.transform(e.pos).round();
      this.child.onButton(e, size);
      return;
    }
    this.View.requestRedraw(IRect(size));
  }

  override void onKey(KeyEvent e, ISize size) {
    if (e.isPress && e.key.num == 27) {
      this.scale = 1.f;
      this.pendingScale = 1.f;
      this.translation = IPoint(0, 0);
      this.View.requestRedraw(IRect(size));
    }
  }

  override void onMouse(MouseEvent e, ISize size) {
    if (!e.button.right) {
      e.pos = this.transform(e.pos).round();
      this.child.onMouse(e, size);
    } else {
      const disp = (10. * M_1_PI) * tanh(0.02 * (e.pos.x - this.zoomAnchor.x));
      this.pendingScale = pow(2, disp);
      this.View.requestRedraw(IRect(size));
    }
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    auto pendingTrans = fPoint(this.zoomAnchor) * (FPoint(1, 1) - this.scaleVec(this.pendingScale));
    canvas.translate(pendingTrans);
    canvas.scale(this.scaleVec(this.pendingScale));
    canvas.translate(this.translation);
    canvas.scale(this.scaleVec(this.scale));
    auto chcorners = area.corners;
    auto mapped = FRect(this.transform(chcorners[0]), this.transform(chcorners[1]));
    this.child.onDraw(canvas, mapped.roundOut(), size);
  }

  FVector scaleVec(float sc) {
    FVector result;
    result.x = (this.direction & 0x1) ? sc : 1.f;
    result.y = (this.direction & 0x2) ? sc : 1.f;
    return result;
  }

  FPoint transform(FPoint pt) {
    return (pt - this.translation) * this.scaleVec(this.scale);
  }

  FPoint transform(IPoint pt) {
    return this.transform(fPoint(pt));
  }

  FPoint transformInv(FPoint pt) {
    return pt / this.scaleVec(this.scale) + this.translation;
  }

  FPoint transformInv(IPoint pt) {
    return this.transformInv(fPoint(pt));
  }

  override void requestRedraw(IRect area, View child) {
    auto chcorners = area.corners;
    auto mapped = FRect(this.transformInv(chcorners[0]), this.transformInv(chcorners[1]));
    super.requestRedraw(mapped.roundOut(), child);
  }

  Direction direction;
  IPoint zoomAnchor;
  FPoint translation = FPoint(0, 0);
  float scale = 1.f;
  float pendingScale = 1.f;
}