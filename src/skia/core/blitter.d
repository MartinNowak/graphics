module skia.core.blitter;

debug = WHITEBOX;
debug import std.stdio : writefln, writef;

import skia.core.region;
import skia.core.rect;

class Blitter
{
  final void blitRegion(in Region clip) {
    clip.forEach(&this.blitRect);
  }

  final void blitRect(in IRect rect) {
    this.blitRect(rect.x, rect.y, rect.width, rect.height);
  }
  final void blitRect(int x, int y, int width, int height) {
    while (--height >= 0)
      this.blitH(x, y++, width);
  }
  abstract void blitH(int x, int y, uint width);

  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented property "~m);
  }
}
