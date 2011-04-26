module skia.views.cached;

import std.algorithm : swap;
import skia.views.view2, skia.core.canvas, skia.core.paint;
import guip._;

class CachedView : ParentView {
  this(View child) {
    super(child);
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (!clean(size))
      return;
    super.onButton(e, size);
    update();
  }
  override void onMouse(MouseEvent e, ISize size) {
    if (!clean(size))
      return;
    super.onMouse(e, size);
    update();
  }
  override void onKey(KeyEvent e, ISize size) {
    if (!clean(size))
      return;
    super.onKey(e, size);
    update();
  }

  override void onResize(ResizeEvent e) {
    if (e.area.size == bmp.size)
      return;
    bmp.setConfig(Bitmap.Config.ARGB_8888, e.area.width, e.area.height);
    dirty = IRect(e.area.size);
    super.onResize(e);
    update();
  }
  override void onDraw(Canvas canvas, IRect area, ISize size) {
    assert(clean(size));
    assert(IRect(size).contains(area));
    canvas.clipRect(area);
    scope auto paint = new Paint(White);
    canvas.drawBitmap(bmp, paint);
  }

  override void requestResize(ISize size, View child) {
    assert(child == this.child);
    bmp.setConfig(Bitmap.Config.ARGB_8888, 0, 0);
    dirty = IRect();
    super.requestResize(size, child);
  }
  override void requestRedraw(IRect area, View child) {
    assert(child == this.child);
    dirty.join(area);
  }

  protected IRect update() {
    IRect updated;
    if (!dirty.empty) {
      scope auto canvas = new Canvas(bmp);
      auto bg = Color(lookupAttr("background-color"));
      swap(dirty, updated);
      canvas.clipRect(updated);
      canvas.drawColor(bg);
      child.onDraw(canvas, updated, bmp.size);
    }
    return updated;
  }

  bool clean(ISize size) const {
    return size == bmp.size && dirty.empty;
  }

  Bitmap bmp;
  IRect dirty;
}
