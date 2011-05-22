module skia.math.fixed_ary;

private {
  import std.traits : Unqual, CommonType, isDynamicArray, isTypeTuple;
}

Unqual!(typeof(T[0]))[N] fixedAry(size_t N, T)(in T dynAry) if(isDynamicArray!T)
  in {
    assert(dynAry.length >= N);
  } body {
  typeof(return) result;
  foreach(i, ref resVal; result) {
    resVal = dynAry[i];
  }
  return  result;
}


Unqual!(CommonType!(TS))[TS.length] fixedAry(size_t N, TS...)(TS ts) if(!isDynamicArray!(TS[0])) {
  typeof(return) result;
  foreach(i, t; ts) {
    result[i] = t;
  }
  return  result;
}

unittest {
  auto fAry = fixedAry!2([1, 2]);
  static assert(is(typeof(fAry) == int[2]));
  assert(fAry == [1, 2]);

  auto mAry = fixedAry!3(1, 1.0, 2.0f);
  static assert(is(typeof(mAry) == double[3]));
  assert(mAry == [1.0, 1.0, 2.0]);
}
