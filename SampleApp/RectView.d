module RectView;

import skia.core.canvas;
import skia.core.color;
import skia.core.rect;
import skia.views.view;

debug private import std.stdio : writeln;

class RectView : View
{
  const Color color;
  this(uint w, uint h, Color color) {
    this.color = color;
    this.setSize(w, h);
    this._flags.visible = true;
    this._flags.enabled = true;
  }

  override void onDraw(Canvas canvas) {
    canvas.drawColor(color);
  }
}