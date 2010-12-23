module skia.math.m128;

private {
  import std.traits;
  import std.conv : to;
  import std.typetuple;
  import std.typecons;
}

static assert(isStaticArray!(float[4]));

align(16) struct m128 {
  this(TS...)(TS ta) {
    enum mem = TypedMember!(Tuple!TS);
    __traits(getMember, this, mem) = tuple(ta);
  }

  static m128 fromOne(T)(T t) {
    static const size_t K = 16 / T.sizeof;
    return m128(tupleRepeatN!(K, T).get(t).tupleof);
  }

  union {
    Tuple!(TTRepeatN!(int, 4)) ints;
    Tuple!(TTRepeatN!(uint, 4)) uints;
    Tuple!(TTRepeatN!(short, 8)) shorts;
    Tuple!(TTRepeatN!(ushort, 8)) ushorts;
    Tuple!(TTRepeatN!(byte, 16)) bytes;
    Tuple!(TTRepeatN!(ubyte, 16)) ubytes;

    // Move the floats here so this union is null initialized;
    Tuple!(TTRepeatN!(float, 4)) floats;
    Tuple!(TTRepeatN!(double, 2)) doubles;
  }
}

template tupleRepeatN(size_t N, T) {
  Tuple!(TTRepeatN!(T, N)) get(T t) {
    typeof(return) res;
    initWith(t, res.tupleof);
    return res;
  }
}
void initWith(T, TS...)(T val, ref TS ts) if(is(T == TS[0])) {
  foreach(i, _; ts) {
    ts[i] = val;
  }
}

template TTRepeatN(T, size_t N) if(N > 1) {
  alias TypeTuple!(T, TTRepeatN!(T, N-1)) TTRepeatN;
}

template TTRepeatN(T, size_t N) if(N == 1) {
  alias T TTRepeatN;
}

template TypedMember(T) {
  enum TypedMember = FindMember!(T, __traits(allMembers, m128));
}

template FindMember(T, Names...) {
  static if (Names.length == 0)
    static assert(0, "No member of this type");

  static if (is(typeof(__traits(getMember, m128, Names[0])) == T)) {
    enum FindMember = Names[0];
  } else {
    enum FindMember = FindMember!(T, Names[1 .. $]);
  }
}


unittest {
  assert(m128(1.0f, 1.0f, 1.0f, 1.0f) == m128.fromOne(1.0f));
  auto mm_1 = m128(1.0f, 1.0f, 1.0f, 1.0f);
  auto mm_2 = m128.fromOne(1.0f);
  assert(mm_1 == mm_2);
  assert(mm_2.floats[3] == 1.0f);
  assert(mm_1.floats[0] == mm_2.floats[3]);

  auto res = m128.fromOne!byte(1);
  foreach(b; res.bytes.tupleof) {
    assert(b == 1);
  }
}
