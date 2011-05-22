module skia.views.cell;

import skia.views.view2, skia.core.canvas, skia.core.paint;
import guip.color, guip.event, guip.point, guip.rect, guip.size, layout.hint;
import std.conv : to;

class CellView : ParentView {

  this(View child) {
    super(child);
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (toChildPos(e.pos))
      child.onButton(e, childRect.size);
  }
  override void onMouse(MouseEvent e, ISize size) {
    if (toChildPos(e.pos))
      child.onMouse(e, childRect.size);
  }
  override void onKey(KeyEvent e, ISize size) {
    if (toChildPos(e.pos))
      child.onKey(e, childRect.size);
  }

  override void onResize(ResizeEvent e) {
    auto margin = to!int(lookupAttr("margin"));
    auto padding = to!int(lookupAttr("padding"));
    auto border = to!int(lookupAttr("border-width"));
    childRect = IRect(e.area.size).inset(margin + padding + border, margin + padding + border);
    e.area = childRect;
    child.onResize(e);
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    auto sc = canvas.save();
    scope(exit) { canvas.restoreCount(sc); }


    if (!childRect.contains(area)) {
      auto margin = to!int(lookupAttr("margin"));
      auto frame = IRect(size).inset(margin, margin);

      canvas.clipRect(frame);
      canvas.drawColor(color(lookupAttr("background-color")));

      auto borderColor = color(lookupAttr("border-color"));
      if (!hasFocus)
        borderColor.a = borderColor.a / 2;
      scope auto framePaint = new Paint(borderColor);
      framePaint.fillStyle = Paint.Fill.Stroke;
      auto border = to!float(lookupAttr("border-width"));
      framePaint.strokeWidth = border;
      canvas.drawRect(fRect(frame).inset(border * 0.5, border * 0.5), framePaint);
    }

    if (childRect.intersect(area)) {
      canvas.clipRect(childRect);
      canvas.translate(childRect.pos.x, childRect.pos.y);
      area.pos = area.pos - childRect.pos;
      child.onDraw(canvas, area, childRect.size);
    }
  }

  override void onState(StateEvent e, ISize size) {
    if (auto fe = e.peek!FocusEvent()) {
      auto changed = hasFocus ^ fe.focus;
      hasFocus = fe.focus;
      if (changed)
        requestRedraw(IRect(size), this.child);
    }
  }

  bool toChildPos(ref IPoint pos) {
    if (childRect.contains(pos)) {
      pos = pos - childRect.pos;
      return true;
    }
    return false;
  }

  IRect childRect;
  bool hasFocus;
}
