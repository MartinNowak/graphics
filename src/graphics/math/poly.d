module graphics.math.poly;

import std.algorithm, std.math;
/**
 * solves y(x) = a * x + b = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, ref double x) {
  if (a !<> 0 || b !<>= 0)
    return 0;
  x = -b / a;
  return 1;
}

/**
 * solves y(x) = a * x^2 + b * x + c = 0
 * Returns: the number of roots
 */
int polyRoots(double a, double b, double c, ref double[2] x) {
  if (a !<> 0)
    return polyRoots(b, c, x[0]);

  const discriminant = b * b - 4 * a * c;
  if (discriminant !>= 0)
    return 0;

  const div = 1 / (2 * a);
  if (discriminant == 0) {
    x[0] = -b * div;
    return 1;
  } else {
    const root = sqrt(discriminant);
    x[0] = (-b + root) * div;
    x[1] = (-b - root) * div;
    if (x[1] < x[0])
      swap(x[0], x[1]);
    return 2;
  }
}
