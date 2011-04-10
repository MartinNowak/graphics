module skia.views.cached;

import skia.views.view2, skia.core.canvas, skia.core.paint;
import guip._;

class CachedView : ParentView {
  this(View child) {
    super(child);
  }

  override void onButton(ButtonEvent e, ISize size) {
    assert(clean(size));
    super.onButton(e, size);
    update();
  }
  override void onMouse(MouseEvent e, ISize size) {
    assert(clean(size));
    super.onMouse(e, size);
    update();
  }
  override void onKey(KeyEvent e, ISize size) {
    assert(clean(size));
    super.onKey(e, size);
    update();
  }

  override void onResize(ResizeEvent e) {
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
    super.requestResize(size, this);
  }
  override void requestRedraw(IRect area, View child) {
    assert(child == this.child);
    dirty.join(area);
  }

  void update() {
    if (!dirty.empty) {
      scope auto canvas = new Canvas(bmp);
      auto save = dirty;
      dirty = IRect();
      child.onDraw(canvas, save, bmp.size);
    }
  }

  bool clean(ISize size) const {
    return size == bmp.size && dirty.empty;
  }

  Bitmap bmp;
  IRect dirty;
}
