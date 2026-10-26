module graphics.math.poly;

import graphics.math.clamp;
import std.algorithm, std.math, std.numeric, std.string, std.traits, std.typetuple;

/*
 * this should live somewhere else
 */
template SIota(size_t start, size_t end) if (start < end)
{
    alias TypeTuple!(start, SIota!(start + 1, end)) SIota;
}

template SIota(size_t start, size_t end) if (start == end)
{
    alias TypeTuple!() SIota;
}


/*
 * solves y(x) = a * x + b = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, ref double x)
in { assert(!a.isNaN && !b.isNaN); }
body
{
    if (a == 0)
        return 0;
    x = -b / a;
    return 1;
}

/*
 * solves y(x) = a * x^2 + b * x + c = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, double c, ref double[2] x)
in { assert(!a.isNaN && !b.isNaN && !c.isNaN); }
body
{
    if (a == 0)
        return polyRoots(b, c, x[0]);

    const delta4 = b * b / 4 - a * c;          // half-discriminant
    if (delta4 < 0)
        return 0;
    if (delta4 == 0)
    {
        x[0] = -b / (2 * a);
        return 1;
    }
    const d2 = sqrt(delta4);
    const q = -(b / 2 + ((b > 0) ? d2 : -d2));  // |q| = |b/2| + d2 — no cancellation
    x[0] = q / a;
    x[1] = c / q;                               // Vieta partner (product = c/a)
    if (x[1] < x[0])
        swap(x[0], x[1]);
    return 2;
}

unittest {
    double x;
    assert(polyRoots(2.0, 0.0, x) == 1 && x == 0.0);   // root at zero, previously dropped
    assert(polyRoots(0.0, 2.0, x) == 0);
    assert(polyRoots(0.0, 0.0, x) == 0);
    assert(polyRoots(1.0, -2.0, x) == 1 && x == 2.0);

    double[2] ts;
    assert(polyRoots(0.0, 1.0, 0.0, ts) == 1 && ts[0] == 0.0);  // degenerate quadratic (a == 0)
    assert(polyRoots(1.0, 1.0, 0.0, ts) == 2 && ts[0] == -1.0 && ts[1] == 0.0);
    assert(polyRoots(1.0, 0.0, -1.0, ts) == 2 && ts[0] == -1.0 && ts[1] == 1.0);  // b == 0
    assert(polyRoots(1.0, 2.0, 1.0, ts) == 1 && ts[0] == -1.0);  // double root
    // near-coincident roots: the naive quadratic formula loses the small root
    // to cancellation; q/Vieta keeps it (true value c/(2a) = 5e-17)
    assert(polyRoots(1.0, -2.0, 1e-16, ts) == 2);
    assert(isClose(ts[0], 5e-17));
    assert(isClose(ts[1], 2.0));
}

/*
 * Evaluates polynomial p[0] * t^(K-1) + ... + p[K-1] and its derivative
 * p'(t) at t in one Horner pass.
 *
 * Returns [p(t), p'(t)].
 */
double[2] polyAndDer(T, size_t K)(ref const T[K] c, double t)
{
    double p = c[0], d = 0.0;
    foreach (k; 1 .. K)
    {
        d = d * t + p;
        p = p * t + c[k];
    }
    return [p, d];
}

// debug=Newton;
// debug = NewtonStats;
debug(NewtonStats) import std.stdio;
debug(NewtonStats)
{
    size_t sumIterations;
    size_t numRuns;
    static ~this()
    {
        std.stdio.writefln("mean iterations %s", 1.0 * sumIterations / numRuns);
    }
}

/*
 * Finds the single root of f(t) = poly!T(coeff, t) - v in (x0, x1),
 * returned within xError of the root, measured in t-space.
 *
 * Port of `RootFinderNewton::FindClosed` from C. Yuksel,
 * "High-Performance Polynomial Root Finding for Graphics" (HPG 2022),
 * https://www.cemyuksel.com/research/polynomials/
 *
 * Precondition (holds for BezIota): f is monotone on [x0, x1] with exactly
 * one root in (x0, x1); y0 = f(x0) is provided by the caller (who knows it
 * exactly) and is nonzero, and f(x1) has the opposite sign.
 *
 * The pure-Newton warm start from the midpoint is only compiled in for
 * degree K <= 3 (`if constexpr (N <= 3)` in the original); degree 4 goes
 * straight to the bracketed Newton/bisection loop. The bracket strictly
 * shrinks each iteration, so termination is guaranteed.
 *
 * boundError: when true, a Newton step of size <= xError is verified to
 * straddle the root before returning (via the xError-beyond test point and,
 * for xError == 0, nextafter); when false, such a step is returned
 * directly, which is safe for monotone f since a Newton step cannot
 * overshoot the root by more than the step size.
 */
double findRootNewton(T, size_t K, bool boundError=false)(ref const T[K] coeff, double v,
                               double x0, double x1, double y0, double xError)
{
    assert(y0 != 0);

    debug(NewtonStats) size_t iterations = 0;

    double ep2 = 2 * xError;
    double xr = 0.5 * (x0 + x1); // mid point
    if (x1 - x0 <= ep2)
        return xr;

    // pure Newton warm start for degree <= 3 (FindClosed's `if constexpr (N <= 3)`)
    static if (K <= 3)
    {
        double xr0 = xr;
        for (size_t safetyCounter = 0; safetyCounter < 16; ++safetyCounter)
        {
            debug(NewtonStats) ++iterations;
            auto pd = polyAndDer!(T, K)(coeff, xr);
            double xn = clampToRange(xr - (pd[0] - v) / pd[1], x0, x1);
            if (abs(xr - xn) <= xError)
            {
                debug(NewtonStats)
                {
                    .sumIterations += iterations;
                    ++.numRuns;
                }
                return xn;
            }
            xr = xn;
        }
        if (!isFinite(xr)) xr = xr0;
    }

    // bracketed Newton with bisection fallback
    double yr = poly!T(coeff, xr) - v;
    double xb0 = x0;
    double xb1 = x1;

    while (true)
    {
        debug(NewtonStats) ++iterations;
        immutable side = signbit(y0) != signbit(yr); // IsDifferentSign(y0, yr)
        if (side)
            xb1 = xr;
        else
            xb0 = xr;

        auto pd = polyAndDer!(T, K)(coeff, xr);
        double xn = xr - yr / pd[1];
        if (xn > xb0 && xn < xb1) // valid Newton step
        {
            double stepsize = abs(xr - xn);
            xr = xn;
            if (stepsize > xError)
            {
                yr = poly!T(coeff, xr) - v;
            }
            else
            {
                static if (boundError)
                {
                    double xs;
                    if (xError == 0)
                    {
                        xs = nextafter(side ? xb1 : xb0, side ? xb0 : xb1);
                    }
                    else
                    {
                        xs = side ? xn - xError : xn + xError; // xn - MultSign(xError, side - 1)
                        if (xs == xn)
                            xs = nextafter(side ? xb1 : xb0, side ? xb0 : xb1);
                    }
                    double ys = poly!T(coeff, xs) - v;
                    int s = ((y0 < 0) != (ys < 0)) ? 1 : 0;
                    if (side != s)
                    {
                        debug(NewtonStats)
                        {
                            .sumIterations += iterations;
                            ++.numRuns;
                        }
                        return xn;
                    }
                    xr = xs;
                    yr = ys;
                }
                else
                {
                    debug(NewtonStats)
                    {
                        .sumIterations += iterations;
                        ++.numRuns;
                    }
                    break;
                }
            }
        }
        else // Newton step failed
        {
            xr = 0.5 * (xb0 + xb1);
            if (xr == xb0 || xr == xb1 || xb1 - xb0 <= ep2)
            {
                static if (boundError)
                {
                    if (xError == 0)
                    {
                        double xm = side ? xb0 : xb1;
                        double ym = poly!T(coeff, xm) - v;
                        if (abs(ym) < abs(yr))
                            xr = xm;
                    }
                }
                break;
            }
            yr = poly!T(coeff, xr) - v;
        }
    }

    debug(NewtonStats)
    {
        .sumIterations += iterations;
        ++.numRuns;
    }
    return xr;
}

unittest
{
    // f(t) = poly(t) - v, root checked against an analytic value
    // K=2: f(t) = 2t - 1, root at 0.5
    {
        double[2] c = [2.0, 0.0];
        auto t = findRootNewton(c, 1.0, 0.0, 1.0, -1.0, 1e-6);
        assert(abs(t - 0.5) <= 1e-6);
    }
    // K=3: f(t) = t^2 + t - 0.5, root at (sqrt(3)-1)/2
    {
        double[3] c = [1.0, 1.0, 0.0];
        auto t = findRootNewton(c, 0.5, 0.0, 1.0, -0.5, 1e-6);
        assert(abs(t - (sqrt(3.0) - 1.0) / 2.0) <= 1e-6);
    }
    // K=4: f(t) = t^3 - t^2 + t - 0.1, root near 0.11094 (monotone: f' > 0);
    // reference root via 80 bisections on f(t) = poly(t) - v
    {
        double[4] c = [1.0, -1.0, 1.0, -0.1];
        immutable v = 0.0;
        auto t = findRootNewton(c, v, 0.0, 1.0, -0.1, 1e-6);
        double a = 0.0, b = 1.0;
        foreach (i; 0 .. 80)
        {
            double m = 0.5 * (a + b);
            if (poly!double(c, m) < v) a = m; else b = m;
        }
        assert(abs(t - 0.5 * (a + b)) <= 1e-6);
    }
    // cubic vertex at warm start: p(t) = 10(t-0.5)^3 + 4, v = 5,
    // x0 = 0.5 where p'(x0) = 0, root at 0.5 + cbrt(0.1)
    {
        double[4] c = [10.0, -15.0, 7.5, 2.75];
        auto t = findRootNewton(c, 5.0, 0.5, 1.0, -1.0, 1e-6);
        assert(abs(t - (0.5 + cbrt(0.1))) <= 1e-6);
    }
}

unittest
{
    // bracket already inside the error bound: return the midpoint at once
    {
        double[2] c = [1.0, 0.5];
        auto t = findRootNewton(c, 0.0, 0.0, 1e-9, 0.5, 1.0);
        assert(t == 5e-10);
    }

    // a double root at the warm-start midpoint poisons Newton with 0/0 = NaN;
    // after the safety loop the start is reset and the bracketed loop falls
    // back to bisection. The monotone/sign-change precondition is violated,
    // so only sanity (finite, inside the bracket) is asserted.
    {
        double[3] c = [1.0, -1.0, 0.25]; // (t - 0.5)^2
        auto t = findRootNewton(c, 0.0, 0.0, 1.0, 0.25, 1e-6);
        assert(isFinite(t) && t >= 0.0 && t <= 1.0);
    }

    // boundError: a converged Newton step is verified to straddle the root
    // against a test point offset by xError before being accepted
    {
        double[4] c = [1.0, -1.0, 1.0, -0.1];
        auto t = findRootNewton!(double, 4, true)(c, 0.0, 0.0, 1.0, -0.1, 1e-6);
        assert(abs(poly(c, t)) < 1e-6);
        auto t0 = findRootNewton!(double, 4, true)(c, 0.0, 0.0, 1.0, -0.1, 0.0);
        assert(abs(poly(c, t0)) < 1e-9); // verified via nextafter test points
    }

    // boundError retry: Newton approaches the triple root of t^3 only
    // linearly, so once the step size falls under xError = 0.1 the iterate
    // can still be farther away; the xn + xError straddle test then fails
    // and the search restarts from that verification point
    {
        double[4] c = [1.0, 0.0, 0.0, 0.0];
        auto t = findRootNewton!(double, 4, true)(c, 0.0, -1.0, 1.0, -1.0, 0.1);
        assert(isFinite(t) && abs(t) < 1.0 && abs(poly(c, t)) < 1e-3);
    }

    // the xError == 0 / xs == xn nextafter fallbacks stay uncovered: they
    // need stepsize == 0 or xError below ULP(xn), but a valid Newton step is
    // a distinct double strictly inside the bracket, which rules out both

    // the float instantiation (used by bezier chopping)
    {
        float[2] c = [2.0f, 0.0f];
        auto t = findRootNewton(c, 1.0, 0.0, 1.0, -1.0, 1e-6);
        assert(abs(t - 0.5) <= 1e-6);
    }

    // low-degree Horner evaluations and derivatives
    {
        double[3] c3 = [1.0, 2.0, 3.0]; // t^2 + 2t + 3
        assert(poly(c3, 2.0) == 11.0);
        assert(polyDer(c3, 2.0) == 6.0);

        double[2] c2 = [4.0, 5.0]; // 4t + 5
        assert(poly(c2, 3.0) == 17.0);
        assert(polyDer(c2, 3.0) == 4.0);
    }
}

/*
 * Evaluates polynome p[0] * t ^ (N-1) ... + p[N-1].
 */
CommonType!(T, T2) poly(T, T2)(ref const T[4] p, T2 t)
{
     return ((p[0] * t + p[1]) * t + p[2]) * t + p[3];
}

/// Ditto
CommonType!(T, T2) poly(T, T2)(ref const T[3] p, T2 t)
{
    return (p[0] * t + p[1]) * t + p[2];
}

/// Ditto
CommonType!(T, T2) poly(T, T2)(ref const T[2] p, T2 t)
{
    return p[0] * t + p[1];
}

/*
 * Evaluates derivative of polynome p[0] * t ^ (N-1) ... + p[N-1].
 */
CommonType!(T, T2) polyDer(T, T2)(ref const T[4] p, T2 t)
{
    return (3 * p[0] * t + 2 * p[1]) * t + p[2];
}

/// Ditto
CommonType!(T, T2) polyDer(T, T2)(ref const T[3] p, T2 t)
{
    return 2 * p[0] * t + p[1];
}

/// Ditto
CommonType!(T, T2) polyDer(T, T2)(ref const T[2] p, T2 t)
{
    return p[0];
}
