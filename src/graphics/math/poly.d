module graphics.math.poly;

import std.algorithm, std.math, std.traits;

/*
 * solves y(x) = a * x + b = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, ref double x)
{
    if (a !<> 0 || b !<>= 0)
        return 0;
    x = -b / a;
    return 1;
}

/*
 * solves y(x) = a * x^2 + b * x + c = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, double c, ref double[2] x)
{
    if (a !<> 0)
        return polyRoots(b, c, x[0]);

    immutable discriminant = b * b - 4 * a * c;
    if (discriminant !>= 0)
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
