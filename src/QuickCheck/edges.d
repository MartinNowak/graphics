module skia.core.edgesTest;

private {
  import std.algorithm : iota;
  import std.stdio : writefln;
  import std.random : uniform;

  import skia.core.edgebuilder;
  import skia.core.point;
  import quickcheck._;
}

// debug=SPLIT;
version(unittest) {
  FEdge lineMaker(FPoint[2] pts) {
    auto app = appender!(FEdge[]);
    lineEdge(app, pts);
    assert(app.data.length > 0);
    auto idx = uniform(0u, app.data.length);
    return app.data[idx];
  }

  FEdge quadMaker(FPoint[3] pts) {
    auto app = appender!(FEdge[]);
    quadraticEdge(app, pts);
    assert(app.data.length > 0);
    auto idx = uniform(0u, app.data.length);
    return app.data[idx];
  }

  FEdge cubicMaker(FPoint[4] pts) {
    auto app = appender!(FEdge[]);
    cubicEdge(app, pts);
    assert(app.data.length > 0);
    auto idx = uniform(0u, app.data.length);
    return app.data[idx];
  }

  bool splitBezierLines(FPoint[2] pts) {
    enum tol = 5e-3;
    auto ptss = splitBezier!2(pts, 0.5f);
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
    enum tol = 5e-3;
    auto ptss = splitBezier!K(pts, 0.5f);
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
}
unittest {
  //  quickCheck!(splitBezierLines, lineMaker, Policies.RandomizeMember)();
  //  quickCheck!(splitBezierCheck!(2), Policies.RandomizeMember)();
  quickCheck!(splitBezierCheck!(2), Policies.RandomizeMember)();
  quickCheck!(splitBezierCheck!(3), Policies.RandomizeMember)();
  quickCheck!(splitBezierCheck!(4), Policies.RandomizeMember)();
}

unittest {
  auto edges = getArbitrary!(FEdge[], cubicMaker, Policies.RandomizeMember)();
  writeln(edges);
}
