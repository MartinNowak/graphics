module skia.core.scan;

private {
  import std.algorithm;
  import std.range : assumeSorted, retro;

  import skia.core.blitter;
  import skia.core.blitter_detail.clipping_blitter;
  import skia.core.path;
  import skia.core.region;
  import skia.core.rect;
  import skia.core.regionpath;
  import skia.core.edgebuilder;
  import skia.core.edge_detail._;
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

enum AAScale = 4;
enum AAStep = 1.0f / AAScale;

void antiFillPath(in Path path, in Region clip,
                  Blitter blitter) {
  return fillPathImpl(path, clip, blitter, AAScale);
}
void fillPath(in Path path, in Region clip,
              Blitter blitter) {
  return fillPathImpl(path, clip, blitter, 1);
}
void fillPathImpl(in Path path, in Region clip,
                     Blitter blitter, uint stepScale) {
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

  blitter = getClippingBlitter(blitter, clip, ir);

  if (!(blitter is null)) {
    if (path.inverseFillType) {
      blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      blitEdges!(fillLine)(path, clip.bounds, blitter,
                           ir.top, ir.bottom, stepScale, clip);
    }
  }
}

Blitter getClippingBlitter(Blitter blitter, in Region clip, in IRect ir) {
  if (clip.quickReject(ir))
    return null;

  if (clip.isRect()) {
    // only need a wrapper blitter if we're horizontally clipped
    if (clip.bounds.left >= ir.left || clip.bounds.right <= ir.right)
      return new RectBlitter(blitter, clip.bounds);
  } else {
    assert(clip.isComplex());
    return new RegionBlitter(blitter, clip);
  }
  return blitter;
}

private void blitEdges(alias blitLineFunc)(
  in Path path, in IRect clipRect,
  Blitter blitter,
  int yStart, int yEnd,
  int stepScale, in Region clip) {

  auto edges = buildEdges(path, clipRect);
  yStart = max(yStart, clipRect.top);
  yEnd = min(yEnd, clipRect.bottom);

  // TODO: handle inverseFillType, path.FillType
  walkEdges!(blitLineFunc)(edges, path.fillType, blitter, stepScale, yStart, yEnd);
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

private void walkEdges(alias blitLineFunc, Range)(
  Range edges,
  Path.FillType fillType,
  ref Blitter blitter,
  int stepScale,
  int yStart, int yEnd)
{
  debug(WALK_EDGES) writefln("walkEdges %s", edges);
  auto sortedEdges = truncateOutOfRange(
    sort!("a.firstY < b.firstY")(edges),
    yStart, yEnd);

  FEdge[] workingSet;
  const int windingMask =
    (fillType == Path.FillType.Winding ||
     fillType == Path.FillType.InverseWinding)
    ? -1
    : 1;

  auto iCurY = yStart;
  auto superCnt = 0;
  auto fInc = 1.0 / stepScale;
  auto fCurY = iCurY + superCnt * fInc;

  while (fCurY < yEnd) {
    debug(WALK_EDGES) writeln("fCurY:", fCurY, "WS: ",workingSet);

    workingSet ~= takeNextEdges(fCurY, sortedEdges);
    workingSet = updateWorkingSet(workingSet, fCurY, fInc);


    debug(WALK_EDGES) writeln("WSB: ", workingSet);

    blitLineFunc(fCurY, blitter, workingSet, windingMask);

    ++superCnt;
    if (superCnt == stepScale) {
      ++iCurY;
      superCnt = 0;
    }
    fCurY = iCurY + superCnt * fInc;
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


static void fillLine(Range, T)(
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

static void dotLine(Range, T)(
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
  path.fillType = Path.FillType.EvenOdd;
  auto clip = Region(IRect(100, 100));
  scope auto blitter = new RgnBuilder();

  fillPath(path, clip, blitter);
  blitter.done();

  assert(blitter.scanLines.bounds == IRect(0, 0, 53, 14), to!string(blitter.scanLines.bounds));
}


void antiHairPath(in Path path, in Region clip,
                  Blitter blitter) {
  return hairPathImpl(path, clip, blitter, AAScale);
}
void hairPath(in Path path, in Region clip,
              Blitter blitter) {
  return hairPathImpl(path, clip, blitter, 1);
}

void hairPathImpl(in Path path, in Region clip,
                     Blitter blitter, int stepScale) {
  if (path.empty) {
    return;
  }

  auto ir = path.ibounds;
  ir.inset(-1, -1);

  blitter = getClippingBlitter(blitter, clip, ir);

  if (blitter) {
    // TODO chose SkRgnBlitter, SkRectBlitter
    if (path.inverseFillType) {
      // inverse and stroke ?
      // blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      blitEdges!(dotLine)(path, clip.bounds, blitter,
                          ir.top, ir.bottom, stepScale, clip);
    }
  }
}
