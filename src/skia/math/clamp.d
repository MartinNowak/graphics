module skia.math.clamp;

private {
  import std.functional : binaryFun;
  import std.algorithm : min, max;
}

T1 clampToRange(T1, T2, T3)(T1 value, T2 left, T3 right) {
  assert(right >= left);
  return max(left, min(value, right));
}

bool fitsIntoRange(string interval="[)", T1, T2, T3)(T1 value, T2 left, T3 right) {
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
