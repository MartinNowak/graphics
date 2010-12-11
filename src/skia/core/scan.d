module skia.core.scan;

private {
  import std.algorithm;
  import std.range : assumeSorted, retro;

  import skia.core.blitter;
  import skia.core.path;
  import skia.core.region;
  import skia.core.rect;
  import skia.core.regionpath;
  import skia.core.edgebuilder;
}

// debug=WALK_EDGES; // verbose tracing for walk_edges

static void fillIRect(Blitter)(IRect rect, in Region clip, Blitter blitter) {
  if (rect.empty)
    return;

  if (clip.isRect()) {
    if (rect.intersect(clip.bounds))
      blitter.blitRect(rect);
  } else {
    assert(false);
  }
}

static void fillPath(Blitter)(in Path path, in Region clip, Blitter blitter) {
  if (clip.empty) {
    return;
  }

  auto ir = path.ibounds;

  if (ir.empty) {
    if (path.inverseFillType) {
      blitter.blitRegion(clip);
    }
    return;
  }

  if (!clip.bounds.intersects(ir))
    return;

  // TODO chose SkRgnBlitter, SkRectBlitter
  if (path.inverseFillType) {
    blitAboveAndBelow(blitter, ir, clip);
  }
  else {
    fillPathEdges(path, clip.bounds, blitter, ir.top, ir.bottom, 0, clip);
  }
}

static void fillPathEdges(Blitter)(
  in Path path, in IRect clipRect,
  Blitter blitter,
  int yStart, int yEnd,
  int shiftEdgesUp, in Region clip) {

  // TODO: give clipper to buildEdges
  auto edges = buildEdges(path);
  yStart = max(yStart, clipRect.top);
  yEnd = min(yEnd, clipRect.bottom);

  // TODO: handle inverseFillType, path.FillType
  walkEdges(edges, path.fillType, blitter, yStart, yEnd);
}

static auto upperBoundY(R)(in R edges, int y) {
  for (i=0; i < edges.length; ++i) {
    if (edges[i].firstY > y)
      return i;
  }
}

Range truncateOutOfRange(Range)(Range edges, int yStart, int yEnd) {
  auto leftTrunc = find!("a.lastY > b")(edges, yStart);
  auto rightTrunc = find!("a.firstY <= b")(retro(leftTrunc), yEnd);
  return retro(rightTrunc);
}

version(unittest) {
  private import std.range : iota;
  struct TestElem
  {
    @property string toString() const {
      return to!string(y);
    }
    this(int y) {
      this.y = y;
    }
    @property int firstY () const {
      return y;
    }
    @property int lastY () const {
      return y;
    }
    int y;
  }
}
unittest {
  auto arr = assumeSorted!("a.firstY < b.firstY")(map!(TestElem)(iota(0,10,1)));
  auto exp = assumeSorted!("a.firstY < b.firstY")(map!(TestElem)(iota(4,6,1)));
  auto trunc = truncateOutOfRange(arr, 3, 5);
  assert(trunc.length == exp.length);
  assert(trunc[0] == exp[0]);
}

private enum yInc = 1;

static void walkEdges(Blitter, Range)(
  Range edges,
  Path.FillType fillType,
  ref Blitter blitter,
  int yStart, int yEnd)
{
  auto sortedEdges = truncateOutOfRange(
    sort!("a.firstY < b.firstY")(edges),
    yStart, yEnd);

  FEdge[] workingSet;
  const int windingMask = (fillType & 1) ? 1 : -1;
  auto curY = yStart;

  while (curY < yEnd) {
    debug(WALK_EDGES) writeln("curY:", curY, "WS: ",workingSet);

    workingSet ~= takeNextEdges(curY, sortedEdges);
    workingSet = updateWorkingSet(curY, workingSet);


    debug(WALK_EDGES) writeln("WSB: ", workingSet);

    blitLine(curY, blitter, workingSet, windingMask);

    curY += yInc;
  }

}

// TODO: handle the case where line end and another's line begin would
// join at e.g. (10.0, 10.0). Currently these are closed intervals in
// both directions and leeds to cancelation.
static auto takeNextEdges(Range)(int curY, ref Range sortedEdges) {
  auto newEdges = sortedEdges.lowerBoundPred!("a.firstY <= b")(curY);
  sortedEdges = sortedEdges[newEdges.length .. sortedEdges.length];
  return newEdges.release;
}

static R1 updateWorkingSet(R1)(int curY, R1 curWorkingSet)
{
  curWorkingSet = remove!((edg){return edg.lastY <= curY;})(curWorkingSet);

  foreach(ref edge; curWorkingSet) {
    edge.updateEdge(curY, yInc);
  }
  sort!("a.curX < b.curX")(curWorkingSet);
  return curWorkingSet;
}


static void blitLine(Blitter, Range)(
  int curY,
  Blitter blitter,
  Range edges,
  int windingMask)
{
  int w;
  auto inInterval = false;
  typeof(edges.front.curX) left;

  foreach(ref edge; edges) {
    w += edge.winding;
    if ((w & windingMask) == 0) {
      assert(inInterval);
      auto width = edge.curX - left;
      assert(width >= 0);
      if (width)
        blitter.blitFH(left, curY, width);
      inInterval = false;
    } else if (!inInterval) {
      left = edge.curX;
      inInterval = true;
    }
  }
}

void blitAboveAndBelow(Blitter blitter, in IRect ir, in Region clip) {}

unittest
{
  auto path = Path();
  path.toggleInverseFillType();
  auto clip = Region(IRect(100, 100));
  scope auto blitter = new RgnBuilder();

  fillPath(path, clip, blitter);
  blitter.done();

  assert(blitter.scanLines.bounds == IRect(100, 100));
}

version(unittest) {
  private import skia.core.point;
}
unittest
{
  auto path = Path();
  path.moveTo(point(0.0f, 0.0f));
  path.rLineTo(point(10.0f, 10.0f));
  path.cubicTo(point(30.0f, 20.0f), point(50.0f, 10.0f), point(60.0f, -10.0f));
  auto clip = Region(IRect(100, 100));
  scope auto blitter = new RgnBuilder();

  fillPath(path, clip, blitter);
  blitter.done();

  assert(blitter.scanLines.bounds == IRect(0, 0, 53, 14));
}
