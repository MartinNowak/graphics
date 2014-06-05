import graphics, graphics.bezier.cartesian, graphics.bezier.curve, graphics.math.clamp;
import qcheck;
import std.algorithm, std.math;

unittest {
  assert(beziota(1.0, 3.0).length == 1);
  assert(beziota(1.0 - 1e-10, 3.0).length == 2);
  assert(beziota(0.99, 3.0).length == 2);
  assert(beziota(1.1, 3.0).length == 1);
  assert(beziota(1.6, 3.0).length == 1);
  assert(beziota(1.0, 3.01).length == 2);
  assert(beziota(1.1, 3.01).length == 2);
  assert(beziota(1.6, 3.01).length == 2);
  assert(beziota(3.0, 1.0).length == 1);
  assert(beziota(3.1, 1.0).length == 2);
  assert(beziota(3.1, 0.9).length == 3);
  assert(beziota(3.0, 0.9).length == 2);
  assert(beziota(-1.0, -3.0).length == 1);
  assert(beziota(-1.0, -3.1).length == 2);
  assert(beziota(-1.1, -3.1).length == 2);
  assert(beziota(-1.6, -3.1).length == 2);

  assert(beziota(1.0, 3.0).position == 1);
  assert(beziota(1.0, -1.0).position == 0);
  assert(beziota(1.1, 3.0).position == 1);
  assert(beziota(1.6, 3.0).position == 1);
  assert(beziota(1.1, 3.01).position == 1);
  assert(beziota(3.0, 1.0).position == 2);
  assert(beziota(0.0, 1.0).position == 0);
  assert(beziota(0.0, -2.0).position == -1);
  assert(beziota(0.6, 3.0).position == 0);
  assert(beziota(1.0 - 1e-10, 3.0).position == 0);

  // test empty beziotas for correct position
  assert(beziota(0.0, 0.0).position == 0);
  assert(beziota(0.1, 0.1).position == 0);
  assert(beziota(0.6, 0.6).position == 0);
  assert(beziota(1.0, 1.0).position == 1);
  assert(beziota(1.0+1e-10, 1.0+1e-10).position == 1);
  assert(beziota(1.0-1e-10, 1.0-1e-10).position == 0);
  assert(beziota(0.0, 0.5).position == 0);
  assert(beziota(-0.1, 0.5).position == -1);

  foreach(t; beziota(0.300140381f, 0.0f))
    assert(fitsIntoRange!("()")(t, 0, 1));

  QCheckResult testBeziota(T, size_t K)(Point!T[K] pts)
  {
      if (!monotonic!"x"(pts) || !monotonic!"y"(pts))
          return QCheckResult.discard;

      foreach(t; beziota!("x", T, K)(pts))
          assert(fitsIntoRange!("()")(t, 0, 1));
      foreach(t; beziota!("y", T, K)(pts))
          assert(fitsIntoRange!("()")(t, 0, 1));

      auto testf = (double a, double b) { assert(b > a); return b; };
      reduce!(testf)(0.0, beziota!("x", T, K)(pts));
      reduce!(testf)(0.0, beziota!("y", T, K)(pts));

      return QCheckResult.ok;
  }

  // funny parser error w/o static
  static Point!T[K] gen(T, size_t K)()
  {
      auto xdir = sgn(getArbitrary!int());
      auto ydir = sgn(getArbitrary!int());

      Point!T[K] res = void;
      Config config = { minValue : -1_000, maxValue : 1000 };
      res[0] = getArbitrary!(Point!T)(config);
      foreach(i; 1 .. K)
      {
          auto d = getArbitrary!(Vector!T)(config);
          res[i].x = res[i-1].x + xdir * abs(d.x);
          res[i].y = res[i-1].y + ydir * abs(d.y);
      }
      return res;
  }

  import std.typetuple;
  foreach(T; TypeTuple!(float, double))
  {
      foreach(K; TypeTuple!(2, 3, 4))
      {
          quickCheck!(testBeziota!(T , K), gen!(T, K))();
      }
  }
}
