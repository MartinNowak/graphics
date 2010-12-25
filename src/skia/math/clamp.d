module skia.math.clamp;

private {
  import std.functional : binaryFun;
  import std.algorithm : min, max;
}

T clampToRange(T)(T value, T left, T right) {
  assert(right >= left);
  return max(left, min(value, right));
}

bool fitsIntoRange(T, string interval="[)")(T value, T left, T right) {
  static assert(interval.length == 2);
  return CmpOp!(interval[0])(left, value) && CmpOp!(interval[1])(value, right);
}

template CmpOp(char s) {
  static if (s == '[' || s == ']') {
    alias binaryFun!("a <= b") CmpOp;
  } else {
    static assert(s == '(' || s == ')');
    alias binaryFun!("a < b") CmpOp;
  }
}
