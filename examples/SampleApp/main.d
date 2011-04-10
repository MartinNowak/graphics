module SampleApp.main;

private {
  import skia.core.canvas, skia.views.view2, skia.views.cached;
  import appf.appf, appf.window;
  import guip.color, guip.event, guip.point, guip.rect, guip.size;
//  import SampleApp.bitmapview;
  import SampleApp.circlesview;
//  import SampleApp.quadview;
//  import SampleApp.cubicview;
//  import SampleApp.sineview;
//  import SampleApp.rectview;
//  import SampleApp.textview;
  import test.utrunner;
}

int main() {
  auto app = new AppF();
  auto handler = new Handler(new WindowView(new CirclesView));
  auto win1 = app.makeWindow(IRect(IPoint(40, 40), ISize(200, 200)), handler);
  win1.name("Window1");
  win1.show();
  return app.loop();
}


class Handler : WindowHandler {
  WindowView root;
  ISize size;

  this(WindowView root) {
    this.root = root;
  }

  override void onEvent(Event e, Window win) {
    root.win = win;
    visitEvent(e, this);
  }

  void visit(ButtonEvent e) { root.onButton(e, size); }
  void visit(MouseEvent e) { root.onMouse(e, size); }
  void visit(KeyEvent e) { root.onKey(e, size); }

  void visit(ResizeEvent e) {
    size = e.area.size;
    root.onResize(e);
  }
  void visit(RedrawEvent e) {
    root.win.blitToWindow(root.bmp, e.area.pos, e.area.pos, e.area.size);
  }
  void visit(StateEvent e) {
    root.onState(e, size);
  }
}

class WindowView : CachedView {
  Window win;
  this(View child) {
    super(child);
  }

  override IRect update() {
    auto upd = super.update();
    if (!upd.empty)
      win.blitToWindow(bmp, upd.pos, upd.pos, upd.size);
    return upd;
  }

  override void requestResize(ISize size, View child) {
    if (win !is null)
      win.resize(size);
  }
}

class Simple : View {
  override void onButton(ButtonEvent e, ISize size) {
    if (e.button.left && e.isdown)
      requestResize(size * 2);
    else if (e.button.right && e.isdown)
      requestResize(size / 2);
  }

  override void onMouse(MouseEvent e, ISize size) {
    requestRedraw(IRect(e.pos, ISize(2, 2)));
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    canvas.clipRect(area);
    if (area.size == size)
      canvas.drawColor(WarmGray);
    else
      canvas.drawColor(Yellow);
  }
}
