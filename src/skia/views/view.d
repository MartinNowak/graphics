module skia.views.view;

private {
  import std.bitmanip : bitfields;
  import std.algorithm : remove;
  import std.functional : unaryFun;
  debug import std.stdio : writeln, writefln;

  import skia.core.canvas;
  import skia.core.rect;
  import guip.size;
  import skia.core.point;
}

////////////////////////////////////////////////////////////////////////////////

class DOM
{
  class Node
  {}
}

interface Layout
{
  final void layoutChildren(View parent) {
    assert(parent);
    if (parent.width > 0 && parent.height > 0) {
      this.onLayoutChildren(parent);
    }
  }
  final void inflate(DOM dom, DOM.Node node) {
    assert(dom && node);
    this.onInflate(dom, node);
  }

protected:
  void onLayoutChildren(View parent);
  void onInflate(DOM dom, DOM.Node node);
};

class SquashChildrenZLayout : Layout
{
  void onLayoutChildren(View parent) {
    foreach(child; parent.children) {
     child.loc = parent.loc;
     child.size = parent.size;
    }
  }
  void onInflate(DOM dom, DOM.Node node) {}
}
class VerticalSplit : Layout
{
  void onLayoutChildren(View parent) {
    auto Start = parent.loc;
    auto Shift = IPoint(0, cast(int)(parent.height / parent.children.length));
    auto size = parent.size;
    size.height = cast(int)(size.height / parent.children.length);
    foreach(child; parent.children) {
      child.loc = Start;
      child.size = size;
      Start = Start + Shift;
    }
  }
  void onInflate(DOM dom, DOM.Node node) {}
}
////////////////////////////////////////////////////////////////////////////////

public enum Position
{
  Front,
  Back,
};
public alias Position.Front FrontPos;
public alias Position.Back BackPos;

////////////////////////////////////////////////////////////////////////////////

class View
{
  public struct Flags
  {
    mixin(bitfields!(
	    bool, "visible", 1,
	    bool, "enabled", 1,
	    bool, "focusable", 1,
	    bool, "flexibleH", 1,
	    bool, "flexibleV", 1,
	    uint, "", 3)); // padding
  }

  View parent;
  View[] children;
  Layout _layout;
  IRect _bounds;
  Flags _flags;
  ViewID id;

  alias size_t ViewID;
  private static final obtainID() {
    static ViewID sViewID;
    return sViewID++;
  }
public:
  this(Flags flags = Flags.init) {
    this.id = obtainID();
    this.flags = flags;
  }

  this(IPoint loc, ISize size, Flags flags = Flags.init) {
    this(flags);
    this.setLoc(loc);
    this.setSize(size);
  }

  @property Flags flags() const {
    return this._flags;
  }

  @property void flags(Flags val) {
    if (this._flags.visible ^ val.visible)
      this.inval();

    this._flags = val;

    if (this._flags.visible ^ val.visible)
      this.inval();
  }

  @property IPoint loc() const {
    return IPoint(this.x, this.y);
  }
  @property void loc(IPoint loc) {
    this.setLoc(loc);
  }
  @property ISize size() const {
    return ISize(this.width, this.height);
  }
  @property void size(ISize size) {
    this.setSize(size);
  }

  void setSize(ISize size) {
    this.setSize(size.width, size.height);
  }
  void setSize(uint width, uint height) {
    if (this.width != width || this.height != height) {
      this.inval();

      this.width = width;
      this.height = height;

      this.inval();
      this.onSizeChange();
      this.invokeLayout();
    }
  }

  /****************************************
   * Set absolute position of view.
   * Invalidates old and new covered area.
   * Params:
   *     x = new x position
   *     y = new y position
   */
  void setLoc(IPoint pt) {
    if (this.loc != pt) {
      this.inval();
      this._bounds.position = pt;
      this.inval();
    }
  }
  void setLoc(uint x, uint y) {
    this.setLoc(IPoint(x, y));
  }

  /****************************************
   * Shift view by dx, dy.
   * Invalidates old and new covered area.
   * Params:
   *     dx = horizontal shift
   *     dy = vertical shift
   */
  void offset(uint dx, uint dy) {
    if (dx || dy)
      this.setLoc(this.x + dx, this.y + dy);
  }

  @property Layout layout() {
    return this._layout;
  }

  @property void layout(Layout layout) {
    this._layout = layout;
    this.invokeLayout();
  }

  void onButtonPress(IPoint pt) {
    foreach(child; this.children) {
      child.onButtonPress(pt - child.loc);
    }
  }

  void onButtonRelease(IPoint pt) {
    foreach(child; this.children) {
      child.onButtonRelease(pt - child.loc);
    }
  }

  void onPointerMove(IPoint pt) {
    foreach(child; this.children) {
      child.onPointerMove(pt - child.loc);
    }
  }

  /****************************************
   * Called from view hierachy.
   * Params:
   *     canvas = Canvas to draw on.
   */
  final package void draw(ref Canvas canvas) {
    if (!this.empty && this._flags.visible)
    {
      if (canvas.quickReject(this._bounds, EdgeType.BW))
	return;

      auto count = canvas.save();
      scope(exit) canvas.restoreCount(count);

      canvas.clipRect(this._bounds);
      canvas.translate(this.x, this.y);

      /// drawSelf
      this.drawSelf(canvas);

      /// drawChildren
      this.drawChildren(canvas);
    }
  }

  /****************************************
   * Notifies parent and calls onDraw.
   */
  private final void drawSelf(ref Canvas canvas) {
      if (this.parent)
	parent.beforeChild(this, canvas);

      auto sc = canvas.save();
      this.onDraw(canvas);
      canvas.restoreCount(sc);

      if (this.parent)
	parent.afterChild(this, canvas);
  }

  /****************************************
   * Calls draw on each child view.
   */
  private final void drawChildren(ref Canvas canvas) {
    Canvas childCanvas = this.beforeChildren(canvas);
    foreach (ref child; this.children) {
      child.draw(childCanvas);
    }
    this.afterChildren(canvas);
  }

  /****************************************
   * Configuration point for subclasses

   * Params:
   *     canvas = Canvas to draw on.
   */
  abstract void onDraw(Canvas canvas);

  /****************************************
   * Configuration point for subclasses

   * Called right before this child's onDraw is called.
   * Params:
   *     child = the child that will be drawn.
   *     canvas = the canvas the child will draw to
   */
  void beforeChild(View child, Canvas canvas) {}

  /****************************************
   * Configuration point for subclasses

   * Called right after this child's onDraw is called.
   * Params:
   *     child = the child that has been drawn.
   *     canvas = the canvas the child will draw to
   */
  void afterChild(View child, Canvas canvas) {}

  /****************************************
   * Configuration point for subclasses

   * Params:
   *     canvas = Canvas this view draws on.
   * Returns:
   *     canvas children do draw on
   */
  Canvas beforeChildren(Canvas canvas) {
    return canvas;
  }

  /****************************************
   * Configuration point for subclasses.
   * Params:
   *     canvas = Canvas this view draws on.
   */
  void afterChildren(Canvas canvas) {
  }

  /****************************************
   * Invalidate area.

   * Params:
   *     OPT area = area to invalidate
   * Returns:
   *     actually invalidated area
   */
  IRect inval(in IRect area = IRect()) {
    if (!this._flags.visible)
      return area;

    IRect inval = this.bounds;

    if (area.empty || !inval.intersect(area))
      return area;

    View view = this;

    while (true)
    {
      if (view.handleInval(inval))
	break;

      if (!view.parent || !view.parent._flags.visible)
	break;
      inval.offset(this.x, this.y);
      if (!inval.intersect(view.parent.bounds))
	break;
      view = view.parent;
    }
    return inval;
  }

  /****************************************
   * Configuration point for subclasses

   * Params:
   *     area = area to be invalidate
   * Returns:
   *     return true breaks invalidation rising
   */
  bool handleInval(in IRect area) {
    return false;
  }


  /****************************************
   * Add children at visual front position.

   * template
   * Params:
   *     FrontOrBack = if true attach to front
   *                   if false attach to back

   * Params:
   *     child = child view to add will get removed from
   *     it's current parent view.

   * Returns:
   *     the child view
   */
  View attachChildTo(Position pos)(View child) {
    assert(child != this);

    if (!child || this.children.length > 0 && child == this.children[0])
      return child;

    child.detachFromParent_NoLayout();

    static if (pos == Position.Front)
      this.children ~= child;
    else if (pos == Position.Back)
      this.children = child ~ this.children;
    else assert(false);

    child.parent = this;
    child.inval();
    this.invokeLayout();
    return child;
  }

  void detachAllChildren() {
    foreach (child; this.children) {
      child.detachFromParent_NoLayout();
    }
  }

  private void removeChild(View child) {
    this.children = remove!((View a){ return a == child; })(this.children);
  }

  void detachFromParent_NoLayout() {
    if (!this.parent)
      return;
    /**
    if (this.containsFocus)
      this.setFocus(null);
    */
    this.inval();
    assert(this.parent);
    this.parent.removeChild(this);
  }

  /****************************************
   * Configuration point called when size changed.
   */
  void onSizeChange() {}

  void invokeLayout() {
    if (this.layout) {
      this.layout.layoutChildren(this);
    }
  }

  debug(WHITEBOX) auto opDispatch(string m, Args...)(Args a) {
    throw new Exception("Unimplemented method "~m);
  }

  @property IRect bounds() const
  { return IRect(0, 0, this.width, this.height); }

protected:
  @property int x() const { return this._bounds.x; }
  @property void x(int x) { this._bounds.x = x; }
  @property int y() const { return this._bounds.y; }
  @property void y(int y) { this._bounds.y = y; }

  @property int width() const { return this._bounds.width; }
  @property void width(int width) { this._bounds.width = width; }
  @property int height() const { return this._bounds.height; }
  @property void height(int height) { this._bounds.height = height; }

  @property bool empty() const { return this._bounds.empty; }
}

version (unittest)
{
  static if (!is(Bitmap))
  {
    import skia.core.bitmap;
  }

  static if (!is(Canvas))
  {
    import skia.core.canvas;
  }

  class TestView : View
  {
    static uint[] draws;
    uint id;

    this(uint id) {
      this.id = id;
      this._flags.visible = true;
      this._flags.enabled = true;
      this.setSize(100, 100);
    }
    override void onDraw(Canvas canvas) { draws ~= this.id; }
  }

  class TestLayout : Layout
  {
    static uint[] layoutids;
    static uint[] viewids;
    uint id;

    this (uint id) {
      this.id = id;
    }

    void onLayoutChildren(View parent) {
      viewids ~= (cast(TestView)parent).id;
      layoutids ~= this.id;
    }
    void onInflate(DOM dom, DOM.Node node) {}
  };
}

unittest {
  testDrawOrder();
  testInvalidation();
  testLayout();
}

version (unittest):

void testDrawOrder() {
  struct TestFixture {
    Canvas canvas;

    void testDraw(View v, int[] exp) {
      if (!this.canvas) {
        auto bitmap = Bitmap(Bitmap.Config.ARGB_8888, 100, 100);
        this.canvas = new Canvas(bitmap);
      }
      v.draw(canvas);
      assert(TestView.draws == exp);
      TestView.draws.length = 0;
    }
  }
  auto f = TestFixture();

  auto v1 = new TestView(1);
  auto v2 = new TestView(2);
  auto v3 = new TestView(3);
  v1.attachChildTo!FrontPos(v2);
  v1.attachChildTo!FrontPos(v3);

  f.testDraw(v1, [1, 2, 3]);

  v1.detachAllChildren();
  f.testDraw(v1, [1]);

  v1.attachChildTo!BackPos(v2);
  v1.attachChildTo!BackPos(v3);

  f.testDraw(v1, [1, 3, 2]);

  v3.attachChildTo!FrontPos(new TestView(4));
  f.testDraw(v1, [1, 3, 4, 2]);

  v3.attachChildTo!BackPos(new TestView(5));
  f.testDraw(v1, [1, 3, 5, 4, 2]);
}

void testInvalidation() {
  auto v1 = new TestView(1);
  auto v2 = new TestView(2);
  auto v3 = new TestView(3);

  v1.attachChildTo!FrontPos(v2);
  v1.attachChildTo!FrontPos(v3);
  assert(v3.inval(IRect(1, 1)) == IRect(0, 0, 1, 1));
  v3.setLoc(10, 5);
  assert(v3.inval(IRect(1, 1)) == IRect(10, 5, 11, 6));
  assert(v2.inval(IRect(1, 1)) == IRect(0, 0, 1, 1));
}

void testLayout() {
  auto v1 = new TestView(1);
  auto v2 = new TestView(2);
  auto v3 = new TestView(3);

  v1.layout = new TestLayout(1);
  v3.layout = new TestLayout(3);

  assert(TestLayout.viewids == [1, 3]);
  assert(TestLayout.layoutids == [1, 3]);
  TestLayout.viewids.length = 0;
  TestLayout.layoutids.length = 0;

  v3.setSize(50, 50);
  assert(TestLayout.viewids == [3]);
  assert(TestLayout.layoutids == [3]);
}