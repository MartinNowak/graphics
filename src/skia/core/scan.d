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
  debug import std.stdio;
}

// debug=WALK_EDGES; // verbose tracing for walk_edges

void fillIRect(Blitter)(IRect rect, in Region clip, Blitter blitter) {
  if (rect.empty)
    return;

  if (clip.isRect()) {
    if (rect.intersect(clip.bounds))
      blitter.blitRect(rect);
  } else {
    assert(false);
  }
}

enum AAScale = 2;
enum AAStep = 1.0f / AAScale;

void antiFillPath(Blitter)(in Path path, in Region clip,
                           Blitter blitter) {
  return fillPathImpl(path, clip, blitter, AAStep);
}
void fillPath(Blitter)(in Path path, in Region clip,
                       Blitter blitter) {
  return fillPathImpl(path, clip, blitter, 1.0f);
}
void fillPathImpl(Blitter, T)(in Path path, in Region clip,
                              Blitter blitter, T step) {
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
    blitEdges!(fillLine)(path, clip.bounds, blitter,
                         ir.top, ir.bottom, step, clip);
  }
}

private void blitEdges(alias blitLineFunc, Blitter)(
  in Path path, in IRect clipRect,
  Blitter blitter,
  float yStart, float yEnd,
  float step, in Region clip) {

  // TODO: give clipper to buildEdges
  auto edges = buildEdges(path);
  yStart = max(yStart, clipRect.top);
  yEnd = min(yEnd, clipRect.bottom);

  // TODO: handle inverseFillType, path.FillType
  walkEdges!(blitLineFunc)(edges, path.fillType, blitter, step, yStart, yEnd);
}

Range truncateOutOfRange(Range, T)(Range edges, T yStart, T yEnd) {
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

private void walkEdges(alias blitLineFunc, Blitter, Range)(
  Range edges,
  Path.FillType fillType,
  ref Blitter blitter,
  float step,
  float yStart, float yEnd)
{
  auto sortedEdges = truncateOutOfRange(
    sort!("a.firstY < b.firstY")(edges),
    yStart, yEnd);

  FEdge[] workingSet;
  // TODO: Allow non-zero winding rule.
  // const int windingMask = (fillType & 0x1) ? 1 : -1;
  const int windingMask = 1;
  auto curY = yStart;

  while (curY < yEnd) {
    debug(WALK_EDGES) writeln("curY:", curY, "WS: ",workingSet);

    workingSet ~= takeNextEdges(curY, sortedEdges);
    workingSet = updateWorkingSet(workingSet, curY, step);


    debug(WALK_EDGES) writeln("WSB: ", workingSet);

    blitLineFunc(curY, blitter, workingSet, windingMask);

    curY += step;
  }

}

// TODO: handle the case where line end and another's line begin would
// join at e.g. (10.0, 10.0). Currently these are closed intervals in
// both directions and leeds to cancelation.
static auto takeNextEdges(T, Range)(T curY, ref Range sortedEdges) {
  auto newEdges = sortedEdges.lowerBoundPred!("a.firstY <= b")(curY);
  sortedEdges = sortedEdges[newEdges.length .. sortedEdges.length];
  return newEdges.release;
}

static R1 updateWorkingSet(R1, T)(R1 curWorkingSet, T curY, T step)
{
  curWorkingSet = remove!((edg){return edg.lastY <= curY;})(curWorkingSet);

  foreach(ref edge; curWorkingSet) {
    edge.updateEdge(curY, step);
  }
  sort!("a.curX < b.curX")(curWorkingSet);
  return curWorkingSet;
}


static void fillLine(Blitter, Range, T)(
  T curY,
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
      assert(edge.curX >= left);
      if (edge.curX > left)
        blitter.blitFH(curY, left, edge.curX);
      inInterval = false;
    } else if (!inInterval) {
      left = edge.curX;
      inInterval = true;
    }
  }
}

static void dotLine(Blitter, Range, T)(
  T curY,
  Blitter blitter,
  Range edges,
  int windingMask)
{
  foreach(ref edge; edges) {
    blitter.blitFH(curY, edge.curX, edge.curX + 1.0f);
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


void antiHairPath(Blitter)(in Path path, in Region clip,
                           Blitter blitter) {
  return hairPathImpl(path, clip, blitter, AAStep);
}
void hairPath(Blitter)(in Path path, in Region clip,
                           Blitter blitter) {
  return hairPathImpl(path, clip, blitter, 1.0f);
}

void hairPathImpl(Blitter, T)(in Path path, in Region clip,
                              Blitter blitter, T step) {
  if (clip.empty) {
    return;
  }

  auto ir = path.ibounds;

  if (ir.empty) {
    if (path.inverseFillType) {
      // inverse and stroke ?
      // blitter.blitRegion(clip);
    }
    return;
  }

  if (!clip.bounds.intersects(ir))
    return;

  // TODO chose SkRgnBlitter, SkRectBlitter
  if (path.inverseFillType) {
    // inverse and stroke ?
    // blitAboveAndBelow(blitter, ir, clip);
  }
  else {
    blitEdges!(dotLine)(path, clip.bounds, blitter,
                        ir.top, ir.bottom, step, clip);
  }
}
