module SampleApp.main;

private {
  import skia.core.canvas, skia.views.view2, skia.views.cached, skia.views.layout, skia.core.paint,
    skia.views.button, skia.views.cell, skia.views.zoom, skia.views.display, skia.views.select, skia.math.range,
    skia.core.fonthost._, skia.core.shader;
  import appf.appf, appf.window;
  import guip.bitmap, guip.color, guip.event, guip.point, guip.rect, guip.size;

//  not yet converted to View2
//  import SampleApp.bitmapview;
//  import SampleApp.quadview;
//  import SampleApp.sineview;
//  import SampleApp.rectview;

  import SampleApp.circlesview;
  import SampleApp.cubicview;
  import SampleApp.stroke;
  import SampleApp.svgview;
  import SampleApp.textview;
  import SampleApp.pointsview;
  import std.algorithm, std.array, std.conv, std.traits;
  import layout.hint, layout.nn;
  import test.utrunner;
  import std.concurrency;
}

int main(string[] args) {
  auto app = new AppF();
  auto handler = new Handler(new WindowView(thisTid(), buttons(args[1 .. $])));
  auto win1 = app.makeWindow(IRect(IPoint(40, 40), ISize(1000, 1000)), handler);
  win1.name("Window1");
  win1.show();
  while (app.dispatch(OnEmpty.Return)) {
    receiveTimeout(1,
      (shared BlitEvent e) {
        auto bmp = cast(Bitmap)e.bmp;
        IRect area = e.area;
        win1.blitToWindow(cast(Bitmap)e.bmp, area.pos, area.pos, area.size);
      },
      (ResizeEvent e) {
        win1.resize(e.area.size);
      });
  }
  return 0;
}

struct BlitEvent {
  Bitmap bmp;
  IRect area;
}

class Handler : WindowHandler {
  WindowView root;
  Window win;
  ISize size;

  this(WindowView root) {
    this.root = root;
  }

  override void onEvent(Event e, Window win) {
    this.win = win;
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
    win.blitToWindow(root.bmp, e.area.pos, e.area.pos, e.area.size);
  }
  void visit(StateEvent e) {
    root.onState(e, size);
  }
}

class WindowView : CachedView {
  Tid guiTid;

  this(Tid guiTid, View child) {
    this.guiTid = guiTid;
    super(child);
  }

  override IRect update() {
    auto upd = super.update();
    if (!upd.empty)
      guiTid.send(cast(shared)BlitEvent(bmp, upd));
    return upd;
  }

  override void requestResize(ISize size, View child) {
    guiTid.send(ResizeEvent(IRect(size)));
  }

  override string lookupAttr(string key) {
    enum over = [/*"background-color" : "0xFFAA4488"*/, "color" : "0xFF22AA33"];
    if (auto val = key in over)
      return *val;
    else
      return super.lookupAttr(key);
  }

  override void onKey(KeyEvent e, ISize size) {
    if (e.isPress && e.mod.ctrl && e.key.num == 39) {
      std.stdio.write("saving ");
      bmp.save("canvas.bmp");
      std.stdio.writeln("done");
    }
  }
}

View buttons(string[] args) {
  View[] chs;
  chs ~= new CellView(new Simple(White));
  chs ~= new CellView(new Simple(Red));
  chs ~= new CellView(new Simple(Green));
  chs ~= new CellView(new Simple(Blue));
  //  chs ~= new Simple(Orange);
  //  auto v = new TextView();
  //  auto v = new CirclesView();
  auto v = new ZoomView(new CubicView());
  //  auto v = new SvgView(args.empty ? null : args[0]);
  //  auto v = new StrokeView();
  //  auto v = new PointsView();
  return flexBox([v, flexBox(chs)]);
}

shared uint id;
class Simple : View {
  this(Color bg, SizeHint sh=SizeHint(Hint(50, 1.), Hint(50, 10.))) {
    this.bg = bg;
    this._sizeHint = sh;
    this.id = .id++;
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    scope auto paint = new Paint(bg);
    paint.antiAlias = false;
    paint.shader = new GradientShader([bg, bg.complement], [FPoint(0, 0), FPoint(size.width, size.height)]);
    paint.shader.matrix = canvas.curMatrix.inverted;

    canvas.drawPaint(paint);
    scope auto textPaint = new TextPaint(Black, TypeFace.findFace("DejaVu Sans"));
    canvas.drawText(to!string(this.id), fPoint(IRect(size).center), textPaint);
    canvas.drawText("ABA", FPoint(0, size.height), textPaint);
  }

  override SizeHint sizeHint() const {
    return _sizeHint;
  }

  Color bg;
  SizeHint _sizeHint;
  uint id;
}
