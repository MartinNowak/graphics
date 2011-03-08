module skia.core.scan;

private {
  import std.algorithm;
  import std.range : assumeSorted, retro;

  import skia.core.blitter;
  import skia.core.blitter_detail.clipping_blitter;
  import skia.core.path;
  import skia.core.rect;
  import skia.core.edgebuilder;
  import skia.core.edge_detail._;
  debug import std.stdio;
}

// debug=WALK_EDGES; // verbose tracing for walk_edges

void fillIRect(Blitter)(IRect rect, in IRect clip, Blitter blitter) {
  if (rect.empty)
    return;

  if (rect.intersect(clip))
    blitter.blitRect(rect);
  else
    assert(0);
}

enum AAScale = 4;
enum AAStep = 1.0f / AAScale;

void antiFillPath(in Path path, in IRect clip,
                  Blitter blitter) {
  return fillPathImpl(path, clip, blitter, AAScale);
}
void fillPath(in Path path, in IRect clip,
              Blitter blitter) {
  return fillPathImpl(path, clip, blitter, 1);
}
void fillPathImpl(in Path path, in IRect clip,
                     Blitter blitter, uint stepScale) {
  if (clip.empty) {
    return;
  }

  auto ir = path.ibounds;

  if (ir.empty) {
    if (path.inverseFillType) {
      blitter.blitRect(clip);
    }
    return;
  }

  blitter = getClippingBlitter(blitter, clip, ir);

  if (!(blitter is null)) {
    if (path.inverseFillType) {
      blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      blitEdges!(fillLine)(path, clip, blitter,
                           ir.top, ir.bottom, stepScale);
    }
  }
}

Blitter getClippingBlitter(Blitter blitter, in IRect clip, in IRect ir) {
  if (!clip.intersects(ir))
    return null;

  if (clip.left >= ir.left || clip.right <= ir.right)
    return new RectBlitter(blitter, clip);
  else
    return blitter;
}

private void blitEdges(alias blitLineFunc)(
  in Path path, in IRect clip,
  Blitter blitter,
  int yStart, int yEnd,
  int stepScale) {

  auto edges = buildEdges(path, clip);
  yStart = max(yStart, clip.top);
  yEnd = min(yEnd, clip.bottom);

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
  auto fInc = 1.0f / stepScale;
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
  auto remaining = sortedEdges.upperBound(firstYComparable(curY));
  auto newEdges = sortedEdges[0 .. sortedEdges.length - remaining.length];
  sortedEdges = remaining;
  return newEdges.release;
}

private static Edge!T firstYComparable(T)(T firstY) {
  Edge!T edge;
  edge.p0.y = firstY;
  return edge;
}

static R1 updateWorkingSet(R1, T)(R1 curWorkingSet, T curY, T step)
{
  bool pred(Edge!T edge) {
    return edge.lastY <= curY;
  }
  curWorkingSet = remove!(pred, SwapStrategy.unstable)(curWorkingSet);

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

void blitAboveAndBelow(Blitter blitter, in IRect ir, in IRect clip) {}

version(unittest) {
  private import skia.core.point;
}


void antiHairPath(in Path path, in IRect clip,
                  Blitter blitter) {
  return hairPathImpl(path, clip, blitter, AAScale);
}
void hairPath(in Path path, in IRect clip,
              Blitter blitter) {
  return hairPathImpl(path, clip, blitter, 1);
}

void hairPathImpl(in Path path, in IRect clip,
                     Blitter blitter, int stepScale) {
  if (path.empty) {
    return;
  }

  auto ir = path.ibounds.inset(-1, -1);

  blitter = getClippingBlitter(blitter, clip, ir);

  if (blitter) {
    // TODO chose SkRgnBlitter, SkRectBlitter
    if (path.inverseFillType) {
      // inverse and stroke ?
      // blitAboveAndBelow(blitter, ir, clip);
    }
    else {
      blitEdges!(dotLine)(path, clip, blitter,
                          ir.top, ir.bottom, stepScale);
    }
  }
}
