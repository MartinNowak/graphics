module skia.math.quickCheck;

private {
  import skia.math._;
  import skia.math.rounding;
  import quickcheck._;
  import std.stdio;
}

QCheckResult checkClampToRange(T)(T value, T left, T right) {
  if (left > right)
    return QCheckResult.Reject;

  auto clamped = clampToRange(value, left, right);
  assert(clamped >= left);
  assert(clamped <= right);
  assert(!(value >= left && value <= right) || value == clamped);
  return QCheckResult.Ok;
}

QCheckResult checkFitsIntoRange(T)(T value, T left, T right) {
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

  return QCheckResult.Ok;
}

struct Comparable {
  this(size_t val) { this.val = val; }
  int opCmp(in Comparable rhs) {
    return rhs.val - this.val;
  }
  uint val;
}

class ComparableClass {
  this(size_t val) { this.val = val; }
  int opCmp(in ComparableClass rhs) {
    return rhs.val - this.val;
  }
  uint val;
}

void runClampToRange() {
  quickCheck!(checkClampToRange!float, count(1_000))();
  quickCheck!(checkClampToRange!real, count(1_000))();
  quickCheck!(checkClampToRange!byte, count(1_000))();
  quickCheck!(checkClampToRange!ushort, count(1_000))();
  quickCheck!(checkClampToRange!bool, count(20))();
  quickCheck!(checkClampToRange!Comparable, count(1_000))();
  quickCheck!(checkClampToRange!ComparableClass, count(1_000))();
}
void runFitsIntoRange() {
  quickCheck!(checkFitsIntoRange!float, count(1_000))();
  quickCheck!(checkFitsIntoRange!real, count(1_000))();
  quickCheck!(checkFitsIntoRange!byte, count(1_000))();
  quickCheck!(checkFitsIntoRange!ushort, count(1_000))();
  quickCheck!(checkFitsIntoRange!bool, count(20))();
  quickCheck!(checkFitsIntoRange!Comparable, count(1_000))();
  quickCheck!(checkFitsIntoRange!ComparableClass, count(1_000))();
}
QCheckResult checkTruncate(T)(T f) {
  return stdMathTruncate(f) == SSETruncate(f) ?
    QCheckResult.Ok : QCheckResult.Fail;
}
void runTruncate() {
  quickCheck!(checkTruncate!float, count(10_000),
              minValue(int.min), maxValue(int.max))();
  quickCheck!(checkTruncate!double, count(10_000),
              minValue(int.min), maxValue(int.max))();
}
unittest {
  runClampToRange();
  runFitsIntoRange();
  runTruncate();
}
