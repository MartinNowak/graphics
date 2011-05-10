module skia.bezier.clip;

import skia.bezier.chop, skia.bezier.curve;
import guip.point, guip.rect;
import std.algorithm, std.conv;

bool clipMonoBezier(T, size_t K)(ref const Point!T[K] curve, ref const Rect!T rect, ref Point!T[K] clipped) {
  assert(!rect.empty);
  assert(monotonicX(curve) && monotonicY(curve));
  return clipMonoBezierX!T(curve, rect.left, rect.right, clipped)
    && clipMonoBezierY!T(clipped, rect.top, rect.bottom, clipped);
}


bool clipMonoBezierX(T)(ref const Point!T[2] line, T left, T right, ref Point!T[2] clipped) {
  const lenscale = 1. / (line[1].x - line[0].x);
  auto t0 = (left - line[0].x) * lenscale;
  auto t1 = (right - line[0].x) * lenscale;
  return clipLineImpl!T(line, t0, t1, clipped);
}

bool clipMonoBezierY(T)(ref const Point!T[2] line, T top, T bottom, ref Point!T[2] clipped) {
  const lenscale = 1. / (line[1].y - line[0].y);
  auto t0 = (top - line[0].y) * lenscale;
  auto t1 = (bottom - line[0].y) * lenscale;
  return clipLineImpl!T(line, t0, t1, clipped);
}

bool clipLineImpl(T)(ref const Point!T[2] line, T t0, T t1, ref Point!T[2] clipped) {
  if (t0 !>= 0 && t1 !>= 0 || t0 !<= 1 && t1 !<= 1)
    return false;
  auto s0 = min(t0, t1);
  auto s1 = max(t0, t1);
  assert(s0 <>= s1);
  if (s0 <= 0 && s1 >= 1) {
    if (line !is clipped) // no self assign
      clipped = line;
  } else
    sliceBezier(line, max(0, s0), min(1, s1), clipped);
  return true;
}

version(unittest) import std.stdio;
unittest {
  FPoint[2] line = [FPoint(0, 0), FPoint(2, 2)];
  auto clip = FRect(0, 0, 1, 1);
  FPoint[2] clipped;
  assert(clipMonoBezier(line, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(1, 1)]);
  line[1] = FPoint(2, 1);
  assert(clipMonoBezier(line, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(1, 0.5)]);
  line[1] = FPoint(1, 2);
  assert(clipMonoBezier(line, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(0.5, 1)]);

  line = [FPoint(-2, -2), FPoint(2, 2)];
  assert(clipMonoBezier(line, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(1, 1)]);

  line = [FPoint(-2, -1), FPoint(2, -0.5)];
  assert(!clipMonoBezier(line, clip, clipped));

  line = [FPoint(-2, -1), FPoint(2, 1)];
  assert(clipMonoBezier(line, clip, clipped));
  assert(clipped == [FPoint(0, 0), FPoint(1, 0.5)]);
}
