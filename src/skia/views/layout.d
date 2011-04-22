module skia.views.layout;

import skia.views.view2, skia.core.canvas;
import layout.box, layout.flow, layout.hint, layout.item;
import guip.event, guip.point, guip.rect, guip.size;

alias Layout!(BoxLayout!(View, Orientation.Horizontal)) HBox;
alias Layout!(BoxLayout!(View, Orientation.Vertical)) VBox;

HBox hbox(View[] views) {
  return new HBox(views);
}

VBox vbox(View[] views) {
  return new VBox(views);
}

View varBox(View[] chs) {
  switch (chs.length) {
  case 2:
    return new Layout!(VarBoxLayout!(View, 2))(chs);
  case 3:
    return new Layout!(VarBoxLayout!(View, 3))(chs);
  case 4:
    return new Layout!(VarBoxLayout!(View, 4))(chs);
  default:
    assert(0);
  }
}

class Layout(Container) : View {
  this(View[] children) {
    items = Container(children);
    foreach(ch; children)
      ch.parent = this;
  }
  // user events
  override void onButton(ButtonEvent e, ISize size) {
    auto it = items.itemByPos(e.pos);
    switchFocus(it);
    if (!it.empty) {
      e.pos = it.toLocal(e.pos);
      it.node.onButton(e, it.size);
    }
  }

  override void onMouse(MouseEvent e, ISize size) {
    auto it = e.button.any ? findItem(focus) : items.itemByPos(e.pos);
    if (!it.empty) {
      e.pos = it.toLocal(e.pos);
      it.node.onMouse(e, it.size);
    }
  }

  override void onKey(KeyEvent e, ISize size) {
    auto it = findItem(focus);
    if (!it.empty) {
      e.pos = it.toLocal(e.pos);
      it.node.onKey(e, it.size);
    }
  }

  override SizeHint sizeHint() const { return items.sizeHint; }

  // system events
  override void onResize(ResizeEvent e) {
    items.resize(e.area.size);
    foreach(it; items)
      it.node.onResize(ResizeEvent(IRect(it.size)));
  }
  override void onState(StateEvent e, ISize size) {
    if (auto f = e.peek!FocusEvent) {
      if (!f.focus)
        deFocus();
      focus = null;
    } else if (auto v = e.peek!VisibilityEvent) {
      foreach(it; items)
        it.node.onState(e, it.size);
    } else {
      assert(0);
    }
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
    return LayoutItem!View();
  }

  void switchFocus(LayoutItem!View it) {
    if (focus == it.node)
      return;

    deFocus();
    focus = it.node;

    if (focus !is null) {
      auto ev = StateEvent();
      it.node.onState(StateEvent(FocusEvent(true)), it.size);
    }
  }

  void deFocus() {
    if (focus !is null) {
      auto old = findItem(focus);
      old.node.onState(StateEvent(FocusEvent(false)), old.size);
    }
  }

  Container items;
  View focus;
}
