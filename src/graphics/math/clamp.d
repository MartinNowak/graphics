module graphics.math.clamp;

private {
  import std.conv : to;
  import std.traits : isNumeric;
  import std.functional : binaryFun;
  import std.algorithm : min, max;
}

T1 clampToRange(T1, T2, T3)(T1 value, T2 left, T3 right) {
  assert(right >= left);
  return max(left, min(value, right));
}

T clampTo(T, T2)(T2 value) {
  return checkedTo!T(clampToRange(value, T.min, T.max));
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

debug {
  T checkedTo(T, T2)(T2 val) if(isNumeric!T2) {
    return to!T(val);
  }
} else {
  T checkedTo(T, T2)(T2 val) if(isNumeric!T2) {
    return cast(T)(val);
  }
}
