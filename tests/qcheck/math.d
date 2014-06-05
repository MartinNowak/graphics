import graphics.math.clamp;
import qcheck;
import std.stdio;

QCheckResult checkClampToRange(T)(T value, T left, T right) {
  if (left > right)
    return QCheckResult.discard;

  auto clamped = clampToRange(value, left, right);
  assert(clamped >= left);
  assert(clamped <= right);
  assert(!(value >= left && value <= right) || value == clamped);
  return QCheckResult.ok;
}

bool checkFitsIntoRange(T)(T value, T left, T right) {
  auto doesFit = fitsIntoRange(value, left, right);
  assert(doesFit ^ (value < left || value >= right));

  //! default parameter, left closed, right open.
  assert(doesFit == fitsIntoRange!("[)")(value, left, right));

  doesFit = fitsIntoRange!("[]")(value, left, right);
  assert(doesFit ^ (value < left || value > right));

  doesFit = fitsIntoRange!("()")(value, left, right);
  assert(doesFit ^ (value <= left || value >= right));

  doesFit = fitsIntoRange!("(]")(value, left, right);
  assert(doesFit ^ (value <= left || value > right));

  return true;
}

struct Comparable {
  this(uint val) { this.val = val; }
  int opCmp(in Comparable rhs) {
    return rhs.val - this.val;
  }
  uint val;
}

class ComparableClass {
  this(uint val) { this.val = val; }
  int opCmp(in ComparableClass rhs) {
    return rhs.val - this.val;
  }
  uint val;
}

void runClampToRange() {
  Config config = { maxSuccess : 1000, maxDiscarded : 10_000 };

  quickCheck!(checkClampToRange!float)(config);
  quickCheck!(checkClampToRange!real)(config);
  quickCheck!(checkClampToRange!byte)(config);
  quickCheck!(checkClampToRange!ushort)(config);
  quickCheck!(checkClampToRange!bool)(config);
  quickCheck!(checkClampToRange!Comparable)(config);
  quickCheck!(checkClampToRange!ComparableClass)(config);
}
void runFitsIntoRange() {
  Config config = { maxSuccess : 1000 };

  quickCheck!(checkFitsIntoRange!float)(config);
  quickCheck!(checkFitsIntoRange!real)(config);
  quickCheck!(checkFitsIntoRange!byte)(config);
  quickCheck!(checkFitsIntoRange!ushort)(config);
  quickCheck!(checkFitsIntoRange!bool)(config);
  quickCheck!(checkFitsIntoRange!Comparable)(config);
  quickCheck!(checkFitsIntoRange!ComparableClass)(config);
}
unittest {
  runClampToRange();
  runFitsIntoRange();
}
