module graphics.core.scan;

import std.algorithm, std.math, std.range;
import graphics.core.blitter, graphics.core.edgebuilder, graphics.core.edge_detail._,
  graphics.core.blitter_detail.clipping_blitter, graphics.core.path, graphics.core.wavelet.raster,
  graphics.math._, graphics.util.format;
import guip.rect, guip.point;


// debug=WALK_EDGES; // verbose tracing for walk_edges
debug(WALK_EDGES) import std.stdio;

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
  return fillPathImpl!AAScale(path, clip, blitter);
}
void fillPath(in Path path, in IRect clip,
              Blitter blitter) {
  return fillPathImpl!1(path, clip, blitter);
}

void fillPathImpl(size_t Scale)
(in Path path, in IRect clip, Blitter blitter) {
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
      graphics.core.wavelet.raster.blitEdges(path, clip, blitter, ir.top, ir.bottom);
      //      blitEdges!(Scale)(path, clip, blitter,
      //                        ir.top, ir.bottom);
    }
  }
}

Blitter getClippingBlitter(Blitter blitter, in IRect clip, in IRect ir) {
  if (!clip.intersects(ir))
    return null;

  if (clip.left >= ir.left || clip.right <= ir.right) // TODO: maybe use > <
    return new RectBlitter(blitter, clip);
  else
    return blitter;
}

private void blitEdges(size_t Scale)(
  in Path path, IRect clip,
  Blitter blitter,
  int yStart, int yEnd) {

  clip.top = max(yStart, clip.top);
  clip.bottom = min(yEnd, clip.bottom);
  auto edges = buildEdges(path, clip);

  // TODO: handle inverseFillType, path.FillType
  if (path.fillType == Path.FillType.Winding
      || path.fillType == Path.FillType.InverseWinding) {
    markBuffer.length = Scale * clip.width;
    auto nzbuf = cast(Block!Scale[])markBuffer;

    walkEdges!(Scale, Block!Scale)(edges, clip, blitter, -1, nzbuf);
  } else {
    auto eobuf = cast(BitBlock!Scale[])markBuffer;
    eobuf.length = clip.width;
    walkEdges!(Scale, BitBlock!Scale)(edges, clip, blitter, 1, eobuf);
  }
}

// TLS cache to avoid dynamic allocations
byte[] markBuffer;

template BitBlock(size_t Scale) if (Scale <= 8) {
  alias byte BitBlock;
}
template BitBlock(size_t Scale) if (Scale > 8 &&  Scale <= 16) {
  alias short BitBlock;
}

union Block(size_t Scale : 1) { ubyte wide; byte[1] val; }
union Block(size_t Scale : 2) { ushort wide; byte[2] val; }
union Block(size_t Scale : 4) { uint wide; byte[4] val; }
union Block(size_t Scale : 8) { ulong wide; byte[8] val; }
union Block(size_t Scale : 16) { ulong[2] wide; byte[16] val; }

Block!Scale sumBlock(size_t Scale)(Block!Scale a, Block!Scale b) {
  Block!Scale result;
  foreach(i; 0 .. Scale) {
    result.val[i] = checkedTo!byte(a.val[i] + b.val[i]);
  }
  return result;
}

private void walkEdges(size_t Scale, Mark)(
  FEdge[] edges,
  in IRect area,
  Blitter blitter,
  byte windingMask,
  Mark[] marks)
{
  if (area.empty)
    return;

  debug(WALK_EDGES) std.stdio.writefln("walkEdges %s", edges);
  auto sortedEdges = sort!("a.firstY < b.firstY")(edges);
  FEdge[] workingSet;

  int y = area.top;
  enum offset = 1.0f / Scale;

  while (y < area.bottom) {
    foreach(i; 0 .. Scale) {
      debug(WALK_EDGES) std.stdio.writeln("cury:", y, "WS: ", workingSet);

      workingSet ~= takeNextEdges(y + i * offset, sortedEdges);
      workingSet = updateWorkingSet(workingSet, y + i * offset, offset);
      markLines!(Scale, Mark)(i, workingSet, area.left, marks);

      debug(WALK_EDGES) std.stdio.writeln("WSB: ", workingSet);
    }
    blitLine!(Scale, Mark)(y, blitter, area.left, marks, windingMask);
    ++y;
  }
}

// TODO: handle the case where line end and another's line begin would
// join at e.g. (10.0, 10.0). Currently these are closed intervals in
// both directions and leeds to cancelation.
static auto takeNextEdges(T, Range)(T cury, ref Range sortedEdges) {
  auto remaining = sortedEdges.upperBound(firstYComparable(cury));
  auto newEdges = sortedEdges[0 .. sortedEdges.length - remaining.length];
  sortedEdges = remaining;
  return newEdges.release;
}

private static Edge!T firstYComparable(T)(T firstY) {
  Edge!T edge;
  edge.p0.y = firstY;
  return edge;
}

static R1 updateWorkingSet(R1, T)(R1 curWorkingSet, T cury, T step)
{
  bool pred(Edge!T edge) {
    return edge.lastY <= cury;
  }
  curWorkingSet = remove!(pred, SwapStrategy.unstable)(curWorkingSet);

  foreach(ref edge; curWorkingSet) {
    edge.updateEdge(cury, step);
  }
  return curWorkingSet;
}

float hoffset(size_t Scale : 1)(size_t vidx) {
  assert(vidx < Scale);
  enum offsets = [0.0f];
  return offsets[vidx];
}
float hoffset(size_t Scale : 2)(size_t vidx) {
  assert(vidx < Scale);
  enum offsets = [0.5f, 0.0f];
  return offsets[vidx];
}
float hoffset(size_t Scale : 4)(size_t vidx) {
  assert(vidx < Scale);
  enum offsets = [0.5f, 0.0f, 0.75f, 0.25f];
  return offsets[vidx];
}
float hoffset(size_t Scale : 8)(size_t vidx) {
  assert(vidx < Scale);
  enum offsets = [5.f/8.f, 0.f, 3.f/8.f, 6.f/8.f, 1.f/8.f, 4.f/8.f, 7.f/8.f, 2.f/8.f];
  return offsets[vidx];
}
float hoffset(size_t Scale : 16)(size_t vidx) {
  assert(vidx < Scale);
  enum offsets = [1.f/8.f, 8.f/8.f, 4.f/8.f, 15.f/8.f, 11.f/8.f, 3.f/8.f, 6.f/8.f, 14.f/8.f,
                  10.f/8.f, 3.f/8.f, 7.f/8.f, 12.f/8.f, 0.f/8.f, 9.f/8.f, 5.f/8.f, 13.f/8.f];
  return offsets[vidx];
}

void markLines(size_t Scale, Mark)(size_t vidx, FEdge[] edges, int leftOff, Mark[] marks) {
  assert(vidx < Scale);
  assert(marks.length > 0);

  auto hoff = hoffset!Scale(vidx);
  auto right = marks.length - 1;
  foreach(ref edge; edges) {
    auto pos = clampToRange(truncate(edge.curX + hoff) - leftOff, 0, right);
    static if (is(Mark == Block!Scale))
      marks[pos].val[vidx] += edge.winding;
    else
      marks[pos] ^= (1 << vidx);
  }
}

ubyte calcAlphaBlock(size_t Scale)(Block!Scale broom, byte mask) {
  uint cnt;
  foreach(i; 0 .. Scale)
    if (broom.val[i] & mask)
      ++cnt;
  return cast(ubyte)(cnt * 255 / Scale);
}

ubyte calcAlphaBit(size_t Scale)(BitBlock!Scale broom) {
  uint cnt;
  while (broom) {
    cnt += broom & 0x1;
    broom >>>= 1;
  }
  assert(cnt <= Scale);
  return cast(ubyte)(cnt * 255 / Scale);
}

void blitLine(size_t Scale, Mark)
  (int y, Blitter blitter, int leftOff, Mark[] marks, byte mask)
if(is(Mark == Block!Scale)) {
  Block!Scale broom;
  int left;
  ubyte alpha;
  foreach(int right, ref pix; marks) {
    static if (Scale > 8)
      auto hasVal = pix.wide[0] != 0 || pix.wide[1] != 0;
    else
      auto hasVal = pix.wide != 0;
    if (hasVal) {
      broom = sumBlock!Scale(broom, pix);
      static if (Scale > 8) { pix.wide[0] = 0; pix.wide[1] = 0; } else { pix.wide = 0; }
      auto newAlpha = calcAlphaBlock!Scale(broom, mask);
      if (newAlpha != alpha) {
        if (alpha)
          blitter.blitAlphaH(y, left + leftOff, right + leftOff, alpha);
        alpha = newAlpha;
        left = right;
      }
    }
  }
}

void blitLine(size_t Scale, Mark)
(int y, Blitter blitter, int leftOff, Mark[] marks, byte /*mask*/)
if (is(Mark == BitBlock!Scale)) {
  BitBlock!Scale broom;
  int left;
  ubyte alpha;
  foreach(int right, ref pix; marks) {
    if (pix) {
      broom ^= pix;
      pix = 0;
      auto newAlpha = calcAlphaBit!Scale(broom);
      if (newAlpha != alpha) {
        if (alpha)
          blitter.blitAlphaH(y, left + leftOff, right + leftOff, alpha);
        alpha = newAlpha;
        left = right;
      }
    }
  }
}

static void fillLine(Range, T)(
  T curY,
  Blitter blitter,
  Range edges,
  byte windingMask)
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
  byte windingMask)
{
  foreach(ref edge; edges) {
    blitter.blitFH(curY, edge.curX, edge.curX + 1.0f);
  }
}

void blitAboveAndBelow(Blitter blitter, in IRect ir, in IRect clip) {}

version(unittest) {
  private import guip.point;
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
      assert(0, "unimplemented");
    }
  }
}
