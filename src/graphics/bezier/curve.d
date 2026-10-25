module graphics.bezier.curve;

import guip.point;
import graphics.math.clamp, graphics.math.poly;
import std.algorithm, std.math;

void bezToPoly(T)(ref T[2] line)
{
    immutable c0 = -line[0] + line[1];
    immutable c1 = line[0];
    line[0] = c0;
    line[1] = c1;
}

void bezToPoly(T)(ref T[3] quad)
{
    immutable c0 = quad[0] - 2 * quad[1] + quad[2];
    immutable c1 = 2 * (-quad[0] + quad[1]);
    immutable c2 = quad[0];
    quad[0] = c0;
    quad[1] = c1;
    quad[2] = c2;
}

void bezToPoly(T)(ref T[4] cubic)
{
    immutable c0 = -cubic[0] + 3 * (cubic[1] - cubic[2]) + cubic[3];
    immutable c1 = 3 * (cubic[0] - 2 * cubic[1] + cubic[2]);
    immutable c2 = 3 * (-cubic[0] + cubic[1]);
    immutable c3 = cubic[0];
    cubic[0] = c0;
    cubic[1] = c1;
    cubic[2] = c2;
    cubic[3] = c3;
}

void bezToPoly(T, size_t K)(ref const Point!T[K] curve, ref T[K] x, ref T[K] y)
{
    foreach(i; SIota!(0, K))
    {
        x[i] = curve[i].x;
        y[i] = curve[i].y;
    }
    bezToPoly(x);
    bezToPoly(y);
}

Point!T evalBezier(T, size_t K)(ref const Point!T[K] bez, double t)
{
    assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
    T[K] x=void, y=void;
    bezToPoly(bez, x, y);
    return Point!T(poly!T(x, t), poly!T(y, t));
}

Point!T evalBezierDer(T, size_t K)(ref const Point!T[K] bez, double t)
{
    assert(fitsIntoRange!("[]")(t, 0.0, 1.0));
    T[K] x=void, y=void;
    bezToPoly(bez, x, y);
    return Point!T(polyDer!T(x, t), polyDer!T(y, t));
}

// creates a line from two points
void constructBezier(T)(Point!T p0, Point!T p1, ref Point!T[2] line)
{
    line[0] = p0;
    line[1] = p1;
}

// creates a quadratic bezier from two points and the derivative a t=0
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, ref Point!T[3] quad)
{
    quad[1] = quad[0] = p0;
    quad[1].x += cast(T)0.5 * d0.x;
    quad[1].y += cast(T)0.5 * d0.y;
    quad[2] = p1;
}

// creates a cubic bezier from two points and the derivatives a t=0 and t=1
void constructBezier(T)(Point!T p0, Point!T p1, Vector!T d0, Vector!T d1, ref Point!T[4] cubic)
{
    cubic[1] = cubic[0] = p0;
    cubic[1].x += cast(T)(1./3.) * d0.x;
    cubic[1].y += cast(T)(1./3.) * d0.y;
    cubic[3] = cubic[2] = p1;
    cubic[2].x -= cast(T)(1./3.) * d1.x;
    cubic[2].y -= cast(T)(1./3.) * d1.y;
}

// Derivative's roots (critical points) of `curve` along `dir`, kept in the
// open interval (0, 1). `ts` holds up to 2 results; returns the count,
// sorted ascending.
// K=2: none (returns 0)
// K=3: derivative linear     -> 2-arg polyRoots (exact)
// K=4: derivative quadratic  -> 3-arg polyRoots (stable q/Vieta)
int criticalPoints(string dir, T, size_t K)(ref const Point!T[K] curve, ref double[2] ts)
{
    T[K] c = void;
    foreach(i; SIota!(0, K))
        c[i] = __traits(getMember, curve[i], dir);
    static if (K == 2)
        return 0;
    else
    {
        bezToPoly(c);
        static if (K == 3)
        {
            // p'(t) = 2 * c[0] * t + c[1]
            int cnt = polyRoots(2 * c[0], c[1], ts[0]);
            return cnt && fitsIntoRange!("()")(ts[0], 0, 1) ? 1 : 0;
        }
        else
        {
            // p'(t) = 3 * c[0] * t^2 + 2 * c[1] * t + c[2]
            int cnt = polyRoots(3 * c[0], 2 * c[1], c[2], ts);
            int res = 0;
            foreach(i; 0 .. cnt)
                if (fitsIntoRange!("()")(ts[i], 0, 1))
                    ts[res++] = ts[i];
            return res;
        }
    }
}

// thin count-only wrapper for asserts. Counts interior critical points,
// except those whose extremum value lies within a few ulps of an endpoint
// value: subdividing a curve whose derivative vanishes exactly at the
// split point / endpoint in float shifts that critical point slightly
// inside (0, 1), and the shift is value noise, not a real wiggle.
int criticalCount(string dir, T, size_t K)(ref const Point!T[K] curve)
{
  double[2] ts = void;
  auto cnt = criticalPoints!(dir, T, K)(curve, ts);
  debug if (cnt >= 2) {
    import graphics.math.poly: poly;
    // two interior critical points are impossible on a monotone segment
    // except as float noise at the endpoints; count only the real wiggles
    T[K] v = void;
    foreach(i; SIota!(0, K))
      v[i] = __traits(getMember, curve[i], dir);
    bezToPoly(v);
    const v0 = poly!T(v, 0.0);
    const v1 = poly!T(v, 1.0);
    const tol = 16.0 * T.epsilon * max(cast(double)abs(v0), cast(double)abs(v1));
    foreach (t; ts) {
        const val = poly!T(v, t);
        if (abs(val - v0) <= tol || abs(val - v1) <= tol)
            --cnt;
    }
  }
  return cnt;
}

bool monotonic(string dir, T, size_t K)(Point!T[K] curve) {
  foreach(i; 1 .. K-1) {
    const rel =
        (__traits(getMember, curve[i], dir) - __traits(getMember, curve[i-1], dir)) *
        (__traits(getMember, curve[i+1], dir) - __traits(getMember, curve[i], dir));
    assert(!rel.isNaN);
    if (rel < 0)
      return false;
  }
  return true;
}

unittest {
  FPoint[3] quad = [FPoint(0, 0), FPoint(1, 1), FPoint(0, 0)];
  double[2] ts;
  auto cnt = criticalPoints!"y"(quad, ts);
  assert(cnt > 0);
  assert(isClose(ts[0], 0.5));
  cnt = criticalPoints!"x"(quad, ts);
  assert(cnt > 0);
  assert(isClose(ts[0], 0.5));
}
