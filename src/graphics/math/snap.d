module graphics.math.snap;

import std.math;

// Grid-crossing decisions must not depend on whether upstream FP evaluation
// (transform matrices, Bernstein polys, FMA contraction...) lands one ULP
// above or below an integer: coordinates within a few ULP of a grid line are
// artifacts of scaling transforms (e.g. 75.0000015f from a 225 * 1/3 scale).
// Snapping them onto the line makes the walker's floor/ceil/== decisions
// against integers build-invariant, while genuine off-grid geometry (more
// than a few ULP away) passes through untouched.
T snapToGrid(T)(T v)
{
    immutable T r = cast(T) round(v);
    // ULP step via nextDown: this Phobos has no std.math.ulp
    immutable T step = fabs(v) - cast(T) nextDown(fabs(v));
    return fabs(v - r) <= 4 * step ? r : v;
}

// floor/ceil for values about to become pixel coordinates. These are the
// discontinuous operations where a coordinate one ULP off the line grows
// into a whole pixel of shift (floor(44.999999994f) is 44), so the grid
// artifacts get pulled back onto the line before the integerisation.
int floorSnap(T)(T v) { return cast(int) floor(snapToGrid(v)); }
int ceilSnap(T)(T v) { return cast(int) ceil(snapToGrid(v)); }

// For values that must land on a lattice (period m): snap v onto the
// nearest multiple of m when it is within k ULPs of basis. The ULP-of-
// basis yardstick matters when v arrived through chained products,
// inverses or cancellations: its error scales with the magnitude those
// operated on - a nearly cancelled v carries that error while its own
// ULP is absurdly small.
T snapToMultiple(T)(T v, T m, T basis, int k = 4)
{
    immutable T target = round(v / m) * m;
    // ULP step via nextDown: this Phobos has no std.math.ulp
    immutable T step = basis - cast(T) nextDown(basis);
    return fabs(v - target) <= k * step ? target : v;
}

unittest
{
    // Transform artifacts land on the line; genuine subpixel offsets don't.
    assert(snapToGrid(75.0000015f) == 75.0f);
    assert(snapToGrid(74.999992f) == 75.0f); // within 1 ULP below
    assert(snapToGrid(150.000003f) == 150.0f);
    assert(snapToGrid(75.0f) == 75.0f);
    assert(snapToGrid(75.0007f) == 75.0007f);
    assert(snapToGrid(0.0f) == 0.0f);
    assert(snapToGrid(-16.000001f) == -16.0f);
    assert(snapToGrid(3.0000000000000004) == 3.0); // exactly 1 ULP: artifact
    assert(snapToGrid(3.000000001) == 3.000000001); // millions of ULPs: real

    assert(floorSnap(44.999999994f) == 45);
    assert(floorSnap(45.0000076f) == 45);
    assert(floorSnap(44.5f) == 44);
    assert(ceilSnap(75.0000015f) == 75);
    assert(ceilSnap(74.999992f) == 75);
    assert(ceilSnap(75.2f) == 76);

    // Chained inverses smear a few ULP of the magnitude they operated on,
    // so the lattice tolerance counts ULPs of v, not of the quotient.
    assert(snapToMultiple(299.99998f, 7.5f, 299.99998f) == 300.0f); // 1 ULP of 300
    assert(snapToMultiple(300.5f, 7.5f, 300.5f) == 300.5f); // a real 0.5 offset
    assert(snapToMultiple(7.9999995f, 8.0f, 7.9999995f) == 8.0f);
    assert(snapToMultiple(8.00004f, 8.0f, 8.00004f) == 8.00004f); // beyond 4 ULP
}
