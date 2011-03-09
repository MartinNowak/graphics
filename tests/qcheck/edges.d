module skia.core.edgesTest;

private {
  import std.algorithm : iota;
  import std.stdio : writefln;
  import std.random : uniform;
  import std.typecons;
  import std.typetuple;
  import std.array : appender;
  import std.math : abs;

  import skia.core.edgebuilder;
  import skia.core.edge_detail._;
  import skia.core.edge_detail.edge : EdgeType;
  import skia.core.edge_detail.algo;
  import skia.core.point;

  import skia.util.format;

  import qcheck._;
}

// debug=SPLIT;

Edge!T lineMaker(T)(Point!T[2] pts) {
  auto app = appender!(Edge!T[]);
  lineEdge(app, pts);
  assert(app.data.length > 0);
  auto idx = uniform(0u, app.data.length);
  return app.data[idx];
}

Edge!T quadMaker(T)(Point!T[3] pts) {
  auto app = appender!(Edge!T[]);
  quadraticEdge(app, pts);
  assert(app.data.length > 0);
  auto idx = uniform(0u, app.data.length);
  return app.data[idx];
}

Edge!T cubicMaker(T)(Point!T[4] pts) {
  auto app = appender!(Edge!T[]);
  cubicEdge(app, pts);
  assert(app.data.length > 0);
  auto idx = uniform(0u, app.data.length);
  return app.data[idx];
}

bool splitBezierLines(FPoint[2] pts) {
  enum tol = 5e-3;
  auto ptss = splitBezier(pts, 0.5f);
  foreach(t; iota(0.0, 0.5, 1e-2)) {
    auto expX = pts[0].x * (1-t) + pts[1].x * t;
    auto expY = pts[0].y * (1-t) + pts[1].y * t;
    auto ts = t * 2.0;
    auto actualX = ptss[0][0].x * (1-ts) + ptss[0][1].x * ts;
    auto actualY = ptss[0][0].y * (1-ts) + ptss[0][1].y * ts;
    debug(SPLIT) writefln("splitL t:%s ex:%s ey:%s ax:%s ay:%s",
             t, expX, expY, actualX, actualY);
    debug(SPLIT) writefln("diffX: %s diffY: %s",
                          abs(expX - actualX), abs(expY - actualY));
    if (abs(expX - actualX) > abs(tol * expX))
      return false;
    if (abs(expY - actualY) > abs(tol * expY))
      return false;
  }
  foreach(t; iota(0.5, 1.0, 1e-2)) {
    auto expX = pts[0].x * (1-t) + pts[1].x * t;
    auto expY = pts[0].y * (1-t) + pts[1].y * t;
    auto ts = (t - 0.5) * 2.0;
    auto actualX = ptss[1][0].x * (1-ts) + ptss[1][1].x * ts;
    auto actualY = ptss[1][0].y * (1-ts) + ptss[1][1].y * ts;
    debug(SPLIT) writefln("splitL t:%s ex:%s ey:%s ax:%s ay:%s",
             t, expX, expY, actualX, actualY);
    debug(SPLIT) writefln("diffX: %s diffY: %s",
                          abs(expX - actualX), abs(expY - actualY));
    if (abs(expX - actualX) > abs(tol * expX))
      return false;
    if (abs(expY - actualY) > abs(tol * expY))
      return false;
  }
  return true;
}

real Calc(string s)(FPoint[2] pts, real t) {
  return mixin("pts[0]."~s~" * (1-t) + pts[1]."~s~" * t");
}
real Calc(string s)(FPoint[3] pts, real t) {
  return mixin("pts[0]."~s~" * (1-t) * (1-t) + 2 * pts[1]."~s~" * (1-t) * t
    + pts[2]."~s~" * t * t");
}
real Calc(string v)(FPoint[4] pts, real t)
  if (v == "x" || v == "y")
{
  auto v0 = mixin("pts[0]."~v);
  auto v1 = mixin("pts[1]."~v);
  auto v2 = mixin("pts[2]."~v);
  auto v3 = mixin("pts[3]."~v);
  auto mt = 1 - t;
  return mt*mt*mt*v0 + 3*t*mt*mt*v1 + 3*t*t*mt*v2 + t*t*t*v3;
}

bool splitBezierCheck(int K)(FPoint[K] pts) {
  enum tol = 1e-2;
  auto ptss = splitBezier(pts, 0.5f);
  auto idx = 0;
  auto stride = 0.5;
  do {
    foreach(t; iota(idx * stride, (idx + 1) * stride, 1e-2)) {
      auto expX = Calc!("x")(pts, t);
      auto expY = Calc!("y")(pts, t);
      auto ts = (t - (idx * stride)) / stride;
      auto actualX = Calc!("x")(ptss[idx], ts);
      auto actualY = Calc!("y")(ptss[idx], ts);
      debug(SPLIT) writefln("splitL t:%s ex:%s ey:%s ax:%s ay:%s",
                            t, expX, expY, actualX, actualY);
      debug(SPLIT) writefln("diffX: %s diffY: %s",
                            abs(expX - actualX), abs(expY - actualY));
      if (abs(expX - actualX) > abs(tol * expX))
        return false;
      if (abs(expY - actualY) > abs(tol * expY))
        return false;
    }
    idx += 1;
  } while(idx * stride < 1.0);
  return true;
}

unittest {
  //  quickCheck!(splitBezierLines, lineMaker, Policies.RandomizeMember)();
  //  quickCheck!(splitBezierCheck!(2), Policies.RandomizeMember)();
  quickCheck!(splitBezierCheck!(2))();
  quickCheck!(splitBezierCheck!(3))();
  quickCheck!(splitBezierCheck!(4))();
}


bool monotonicEdge(T)(Edge!T edge) {
  auto ts = iota(0.0, 1.0, 0.001);
  auto curY = edge.firstY;
  auto hold = T.max;
  foreach(t; ts) {
    auto newY = edge.calcT!("y")(t);
    if (newY < curY) {
      hold = min(hold, curY);
      if (abs(newY - hold) > abs(10 * Edge!T.tol * hold))
        throw new Exception(
          fmtString("failed newY:%.8f curY:%.8f curT:%.8f hold:%.8f tol:%.8f",
                       newY, curY, t, hold, abs(Edge!T.tol * hold)));
    } else
      hold = T.max;
    curY = newY;
  }
  return true;
}
bool verifyLines(T)(Edge!T edge) {
  return edge.type == EdgeType.Line
    && edge.lastY >= edge.firstY
    && monotonicEdge(edge)
    && (edge.lastY > edge.firstY ? verifyXYT(edge) : true);
}

QCheckResult verifyQuads(T)(Edge!T edge) {
  if (edge.type == EdgeType.Line) {
    return QCheckResult.Reject;
  }
  const Success =
    (edge.type == EdgeType.Quad)
    && edge.lastY >= edge.firstY
    && monotonicEdge(edge)
    && verifyXYT(edge);

  return Success ? QCheckResult.Success : QCheckResult.Fail;
}
bool verifyCubics(T)(Edge!T edge) {
  return (edge.type == EdgeType.Cubic
          || edge.type == EdgeType.Line)
    && edge.lastY >= edge.firstY
    && monotonicEdge(edge)
    && verifyXYT(edge, 8e-2);
}

bool verifyXYT(T)(Edge!T edge, double tol=5e-2) {
  auto ts = iota(0, 1000, 1);
  auto step = 0.001;
  foreach (it; ts) {
    auto te = it * step;
    auto y = edge.calcT!("y")(te);
    auto t = edge.getT(y);
    assert(abs(t - te) <= tol,
           fmtString("t:%.7f te:%.7f y:%.7f tol:%.7f", t, te, y, tol));
  }
  return true;
}

template paramTuple(TL...) {
  alias TL paramTuple;
}

template verification(T) {
  bool run() {
    alias paramTuple!(Policies.RandomizeMembers, count(1_000), minValue(0), maxValue(5)) params;
    return quickCheck!(verifyLines!T, lineMaker!T, params)() &&
      quickCheck!(verifyQuads!T, quadMaker!T, params)() &&
      quickCheck!(verifyCubics!T, cubicMaker!T, params)();
  }
}

bool doRun() {
  return verification!float.run()
    && verification!double.run();
}
unittest {
  doRun();
}
