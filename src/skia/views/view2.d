module skia.views.view2;

import skia.core.canvas;
import guip.event, guip.point, guip.rect, guip.size;

/**
   View base class with do nothing implementation.
 */
class View {
  // user events
  void onButton(ButtonEvent e, ISize size) {}
  void onMouse(MouseEvent e, ISize size) {}
  void onKey(KeyEvent e, ISize size) {}

  // system events
  void onResize(ResizeEvent e) {}
  void onState(StateEvent e, ISize size) {}
  void onDraw(Canvas canvas, IRect area, ISize size) {}

  // system up handlers
  void requestResize(ISize size, View child) {
    requestResize(size);
  }
  final void requestResize(ISize size) {
    if(parent !is null)
      parent.requestResize(size, this);
  }

  void requestRedraw(IRect area, View child) {
    requestRedraw(area);
  }
  final void requestRedraw(IRect area) {
    if(parent !is null)
      parent.requestRedraw(area, this);
  }

  void requestState(bool visible, View child) {
    requestState(visible);
  }
  final void requestState(bool visible) {
    if(parent !is null)
      parent.requestState(visible, this);
  }

  View parent;
}

/**
   View with a single child view.
 */
class ParentView : View {
  this(View child)
  in {
    assert(child !is null);
    assert(child.parent is null);
  }
  body {
    this.child = child;
    this.child.parent = this;
  }

  // user events
  override void onButton(ButtonEvent e, ISize size) { child.onButton(e, size); }
  override void onMouse(MouseEvent e, ISize size) { child.onMouse(e, size); }
  override void onKey(KeyEvent e, ISize size) { child.onKey(e, size); }

  // system events
  override void onResize(ResizeEvent e) { child.onResize(e); }
  override void onDraw(Canvas canvas, IRect area, ISize size) { child.onDraw(canvas, area, size); }
  override void onState(StateEvent e, ISize size) { child.onState(e, size); }

  // system up handlers
  override void requestResize(ISize size, View child) {
    assert(child == this.child);
    super.requestResize(size, child);
  }
  override void requestRedraw(IRect area, View child) {
    assert(child == this.child);
    super.requestRedraw(area, child);
  }
  override void requestState(bool visible, View child) {
    assert(child == this.child);
    super.requestState(visible, child);
  }

  View child;
}
