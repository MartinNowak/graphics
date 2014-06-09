module graphics.math.poly;

import std.algorithm, std.math, std.numeric, std.traits, std.typetuple;

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
    if (a == 0 || b == 0)
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

    immutable discriminant = b * b - 4 * a * c;
    if (discriminant < 0)
        return 0;

    immutable div = 1 / (2 * a);
    if (discriminant == 0)
    {
        x[0] = -b * div;
        return 1;
    }
    else
    {
        immutable root = sqrt(discriminant);
        x[0] = (-b + root) * div;
        x[1] = (-b - root) * div;
        if (x[1] < x[0])
            swap(x[0], x[1]);
        return 2;
    }
}

enum tolerance = 1e-4;
// debug=Illinois;
// debug = IllinoisStats;
debug(IllinoisStats) import std.stdio;
debug(IllinoisStats)
{
    size_t sumIterations;
    size_t numRuns;
    static ~this()
    {
        std.stdio.writefln("mean iterations %s", 1.0 * sumIterations / numRuns);
    }
}

T findRootIllinois(T, R)(scope R delegate(T) f, T a, T b)
{
    size_t iterations;
    R fa = f(a);
    R fb = f(b);
    T gamma = 1.0;
    do
    {
        T c = (gamma * b * fa - a * fb) / (gamma * fa - fb);
        T fc = f(c);
        debug(Illinois) writeln("illinois step: ", iterations,
                                " a: ", a, " fa: ", fa,
                                " b: ", b, " fb: ", fb,
                                " c: ", c, " fc: ", fc);
        if (fc < tolerance && fc > -tolerance)
        {
            debug(Illinois)
                writeln("converged after: ", iterations,
                        " at: ", c);
            debug(IllinoisStats)
            {
                .sumIterations += iterations + 1;
                ++.numRuns;
            }
            return c;
        }
        else
        {
            if ((fc < 0) != (fb < 0))
            {
                a = b;
                fa = fb;
                gamma = 1.0;
            }
            else
            {
                gamma = 0.5;
            }
            b = c;
            fb = fc;
        }
    } while (++iterations < 1000);
    assert(0, std.string.format(
               "Failed to converge. Interval [f(%s)=%s .. f(%s)=%s]",
               a, fa, b, fb));
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
