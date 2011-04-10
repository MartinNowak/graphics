module skia.views.layout;

import skia.views.view2, skia.core.canvas;
import layout.box, layout.hint, layout.item;
import guip.event, guip.point, guip.rect, guip.size;

alias Layout!(BoxLayout!(View, Orientation.Horizontal)) HBox;
alias Layout!(BoxLayout!(View, Orientation.Vertical)) VBox;

HBox hbox(View[] views) {
  return new HBox(views);
}

VBox vbox(View[] views) {
  return new VBox(views);
}

class Layout(Container) : View {
  this(View[] children) {
    items = Container(children);
  }
  // user events
  override void onButton(ButtonEvent e, ISize size) {
    auto it = items.itemByPos(e.pos);
    e.pos = it.toLocal(e.pos);
    it.node.onButton(e, it.size);
  }

  override void onMouse(MouseEvent e, ISize size) {
    auto it = items.itemByPos(e.pos);
    e.pos = it.toLocal(e.pos);
    it.node.onMouse(e, it.size);
  }

  override void onKey(KeyEvent e, ISize size) {
    auto it = items.itemByPos(e.pos);
    e.pos = it.toLocal(e.pos);
    it.node.onKey(e, it.size);
  }

  override SizeHint sizeHint() const { return items.sizeHint; }

  // system events
  override void onResize(ResizeEvent e) {
    items.resize(e.area.size);
    foreach(it; items)
      it.node.onResize(ResizeEvent(IRect(it.size)));
  }
  override void onState(StateEvent e, ISize size) {
    foreach(it; items)
      it.node.onState(e, it.size);
  }
  override void onDraw(Canvas canvas, IRect area, ISize size) {
    foreach(it; items) {
      auto sect = it.intersect(area);
      if (!sect.empty) {
        auto cnt = canvas.save();
        canvas.clipRect(it.area);
        canvas.translate(fPoint(it.pos));
        it.node.onDraw(canvas, it.toLocal(sect), it.size);
        canvas.restoreCount(cnt);
      }
    }
  }

  // system up handlers
  override void requestResize(ISize size, View child) {
    auto sh = sizeHint;
    super.requestResize(ISize(sh.w.pref, sh.h.pref));
  }

  override void requestRedraw(IRect area, View child) {
    auto it = findItem(child);
    super.requestRedraw(it.fromLocal(area));
  }

  override void requestState(bool visible, View child) {
    // TODO: need resize
    super.requestState(visible, child);
  }

private:

  LayoutItem!View findItem(View child) {
    foreach(it; items)
      if (it.node == child)
        return it;
    assert(0);
  }

  Container items;
}
