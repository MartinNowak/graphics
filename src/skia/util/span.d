module skia.util.span;

private {
  import std.algorithm : move;
  import std.array;
  import std.range;
  import std.conv : to;

  import std.metastrings;
  import std.typecons;
  import skia.util.format;
  import skia.math.clamp;
  debug import std.stdio;
}


//==============================================================================

struct Span(T, Index = size_t) {
  this(Index start, Index end, in T value) {
    this.start = start;
    this.end = end;
    this.value = value;
  }
  @property string toString() const {
    return fmtString("Span: start: %s end: %s value: %s", this.start, this.end, this.value);
  }
  @property Index length() const {
    return checkedTo!Index(this.end - this.start);
  }
  Index start;
  Index end;
  T value;
}


//==============================================================================

enum Policy {
  Sparse,
  PreAllocate,
}

struct SpanAccumulator(T, Index = size_t, Policy policy = Policy.Sparse) {
private:
  struct Node {
    Tuple!(Index, "dist", T, "value") _node;
    alias _node this;
    this(Index dist, in T value) {
      this.dist = dist;
      this.value = value;
    }
    @property string toString() const {
      return fmtString("Node dist:%s val:%s", this.dist, this.value);
    }
  }
  alias Span!(T, Index) TSpan;

  Index start;
  Index end;
  static if (!is(T == void)) T bottom;
  Node[] nodes;

public:

  this(Index start, Index end, T init = T.init) {
    assert(end > start);
    this.start = start;
    this.end = end;

    static if (policy == Policy.Sparse) {
      this.nodes.length = 1;
    } else {
      this.nodes.length = end - start;
    }
    this.nodes.front = Node(checkedTo!Index(end - start), init);
    this.bottom = init;
  }

  this(in SpanAccumulator other) {
    this = other;
  }

  ref SpanAccumulator opAssign(in SpanAccumulator other) {
    this.start = other.start;
    this.end = other.end;
    this.nodes = other.nodes.dup;
    return this;
  }

  void opOpAssign(string op, T2)(in Span!(T2, Index) span) {
    assert(span.end > span.start);

    auto slice = this[span.start .. span.end];
    assert(slice.nodes.length);

    foreach(ref Node node; slice) {
      mixin("node.value" ~ op ~ "= span.value;");
    }
  }

  @property string toString() const {
    return fmtString("SpanAccumulator!(%s) start: %s \n\tnodes:%s",
                        typeid(T), this.start, this.nodes);
  }

  bool opEquals(ref const SpanAccumulator other) const {
    return this.start == other.start
      && this.end == other.end
      && this.nodes == other.nodes;
  }

  Range opSlice() {
    return Range(this.start, this.nodes.save);
  }

  Range opSlice(Index x, Index y) {
    auto start = this.breakAt(x);
    auto end = this.breakAt(y);
    return Range(x, this.nodes[start .. end]);
  }

  //! join consecutive spans with same values
  void collapse() {
    //! recursive collapse
    static if(__traits(compiles, this.nodes.front.value.collapse())) {
      foreach(ref Node node; this[])
        node.value.collapse();
    }

    if (this.nodes.length <= 1)
      return;

    auto result = this.nodes.save;
    auto src = this.nodes.save;
    src.popFront;
    while (!src.empty) {
      if (src.front.value != result.front.value) {
        result.popFront;
        move(src.front, result.front);
      } else {
        result.front.dist += src.front.dist;
      }
      src.popFront;
    };
    this.nodes = this.nodes[0 .. 1 + $ - result.length];
  }

  void reset(in TSpan init) {
    this.nodes.length = init.length;
    this.start = init.start;
    this.end = init.end;
    this.nodes.front = Node(init.length, init.value);
  }

private:

  static struct Range {
    Node[] nodes;
    Index start;

    this(Index start, Node[] nodes) {
      this.nodes = nodes;
    }

    alias int delegate(ref TSpan) SpanIterDg;
    int opApply(SpanIterDg dg) {
      auto pos = this.start;
      foreach(ref Node node; this) {
        auto ret = dg(TSpan(pos, checkedTo!Index(pos + node.dist), node.value));
        if (ret) return ret;
        pos += node.dist;
      }
      return 0;
    }

    alias int delegate(ref Node) NodeIterDg;
    int opApply(NodeIterDg dg) {
      auto nodesR = this.nodes.save;

      while(!nodesR.empty) {
        auto ret = dg(nodesR.front);
        if (ret) return ret;

        static if (policy == Policy.Sparse)
          nodesR.popFront;
        else
          nodesR.popFrontN(nodesR.front.dist);
      }
      return 0;
    }
  }

  size_t breakAt(Index where)
  in {
    assert(where >= this.start);
  }
  out (ret) {
    debug this.check();
    assert(ret <= this.nodes.length);
  }
  body {
    if (where <= this.start) {
      if (auto length = this.start - where)
        this.extendLeft(checkedTo!(Index)(length));
      return 0;
    }

    if (where >= this.end) {
      if (auto length = where - this.end)
        this.extendRight(checkedTo!(Index)(length));
      return this.nodes.length;
    }

    size_t idx = 0;
    while (where > nodes[idx].dist) {
      where -= nodes[idx].dist;
      static if (policy == Policy.Sparse)
        ++idx;
      else
        idx += nodes[idx].dist;
      assert(idx < this.nodes.length);
    }
    auto oldLen = this.nodes[idx].dist;
    auto newLen = where;
    if (newLen == oldLen)
      static if (policy == Policy.Sparse)
        return idx + 1;
      else
        return idx + where;

    assert(oldLen > newLen);
    this.nodes[idx].dist = newLen;

    auto remaining = checkedTo!(Index)(oldLen - newLen);
    auto newNode = Node(remaining, this.nodes[idx].value);

    static if (policy == Policy.Sparse) {
      this.nodes.insert(idx + 1, newNode);
      return idx + 1;
    } else {
      this.nodes[idx + where] = newNode;
      return idx + where;
    }
  }

  void extendLeft(Index length) {
    assert(length > 0);

    auto newNode = Node(length, this.bottom);

    static if (policy == Policy.Sparse)
      this.nodes.insert(0, newNode);
    else
      this.nodes.insert(0, chain([newNode], repeat(Node.init, length - 1)));

    this.start = checkedTo!(Index)(this.start - length);
  }

  void extendRight(Index length) {
    assert(length > 0);

    auto newNode = Node(length, this.bottom);

    static if (policy == Policy.Sparse)
      this.nodes.insert(this.nodes.length, newNode);
    else
      this.nodes.insert(this.nodes.length, chain(repeat(Node.init, length - 1), [newNode]));

    this.end = checkedTo!(Index)(this.end + length);
  }

  debug void check() {
    auto pos = this.start;
    auto nodesR = this.nodes.save;

    while (!nodesR.empty) {
      pos += nodesR.front.dist;
      static if (policy == Policy.Sparse)
        nodesR.popFront;
      else
        nodesR.popFrontN(nodesR.front.dist);
    }
    assert(pos == this.end);
  }
}

//==============================================================================

version(unittest):

void checkExpectations(Acc, Span)(Acc acc, Span[] exp) {
  foreach(Span span; acc[]) {
    assert(!exp.empty && span == exp.front, fmtString("exp:%s act:%s", exp, span));
    exp.popFront;
  }
}

void checkFor(T, Idx, Policy policy)() {

  auto acc = SpanAccumulator!(T, Idx, policy)(0, 100, 1);
  acc += Span!(T, Idx)(20, 80, 2);

  checkExpectations(acc, [
                      Span!(T, Idx)(0, 20, 1),
                      Span!(T, Idx)(20, 80, 3),
                      Span!(T, Idx)(80, 100, 1),
                    ]);

  acc *= Span!(T, Idx)(15, 25, 2);
  checkExpectations(acc, [
                      Span!(T, Idx)(0, 15, 1),
                      Span!(T, Idx)(15, 20, 2),
                      Span!(T, Idx)(20, 25, 6),
                      Span!(T, Idx)(25, 80, 3),
                      Span!(T, Idx)(80, 100, 1),
                    ]);

  acc = SpanAccumulator!(T, Idx, policy)(0, 100, 1);
  checkExpectations(acc, [
                      Span!(T, Idx)(0, 100, 1),
                    ]);
}

unittest {
  checkFor!(double, int, Policy.Sparse)();
  checkFor!(int, ushort, Policy.Sparse)();
  checkFor!(double, ubyte, Policy.PreAllocate)();
  checkFor!(int, long, Policy.PreAllocate)();
}


unittest {
  auto acc = SpanAccumulator!(SpanAccumulator!int)(0, 5, SpanAccumulator!int(0, 10, 111));
  acc += Span!(Span!int)(2, 4, Span!int(0, 5, 666));

  void checkExpectations(Tuple!(int, int, Span!(int))[] exp) {
    foreach(Span!(SpanAccumulator!(int)) accsp; acc[]) {
      foreach(Span!int sp; accsp.value[]) {
        assert(tuple(accsp.start, accsp.end, sp) == exp.front,
               fmtString("exp:%s act:%s", exp.front, tuple(accsp.start, accsp.end, sp)));
        exp.popFront;
      }
    }
  }
  checkExpectations([
                      tuple(0, 2, Span!(int)(0, 10, 111)),
                      tuple(2, 4, Span!(int)(0, 5, 777)),
                      tuple(2, 4, Span!(int)(5, 10, 111)),
                      tuple(4, 5, Span!(int)(0, 10, 111)),
                    ]);
}

unittest {
  auto acc = SpanAccumulator!(bool)();
  acc |= Span!(bool)(0, 20, true);
  acc |= Span!(bool)(30, 50, true);
  Span!(bool)[] exp;

  exp ~= Span!(bool)(0, 20, true);
  auto span = Span!(bool)(20, 30, false);
  //! BUG 5564 workaround
  span.value = false;
  exp ~= span;
  exp ~= Span!(bool)(30, 50, true);
  checkExpectations(acc, exp);

  acc |= Span!(bool)(20, 30, true);
  exp[1].value = true;
  checkExpectations(acc, exp);

  acc.collapse();
  assert(acc.nodes.length == 1);
  checkExpectations(acc, [Span!(bool)(0, 50, true)]);

  acc.check();

  acc ^= Span!(bool)(10, 15, true);
  acc ^= Span!(bool)(45, 50, true);
  acc &= Span!(bool)(50, 55, true);
  exp = [Span!bool(0, 10, true)];
  span = Span!bool(10, 15, false); span.value = false; exp ~= span;
  exp ~= Span!bool(15, 45, true);
  span = Span!bool(45, 50, false); span.value = false; exp ~= span;
  span = Span!bool(50, 55, false); span.value = false; exp ~= span;
  checkExpectations(acc, exp);

  acc.collapse();
  exp = exp[0 .. 3];
  span = Span!bool(45, 55, false); span.value = false; exp ~= span;
  checkExpectations(acc, exp);


  /*
  checkExpectations(acc, [
                      Span!(bool)(0, 20, true),
                      Span!(bool)(20, 30, false),
                      Span!(bool)(30, 50, true),
                    ]);
  */
}

unittest {
  auto acc = SpanAccumulator!(bool)();
  acc |= Span!(bool)(0, 20, true);
  acc |= Span!(bool)(20, 50, true);
  acc.collapse();
  checkExpectations(acc, [Span!bool(0, 50, true)]);
}

unittest {
  auto acc1 = SpanAccumulator!(bool)(0, 8, true);
  auto acc2 = SpanAccumulator!(bool)(0, 8, true);
  assert(acc1 == acc2);
}

unittest {
  writeln("COLFAIL");
  auto acc = SpanAccumulator!(SpanAccumulator!bool)();
  acc |= Span!(Span!bool)(0, 20, Span!bool(0, 5, true));
  acc |= Span!(Span!bool)(0, 20, Span!bool(5, 8, true));
  acc |= Span!(Span!bool)(20, 50, Span!bool(0, 5, true));
  acc |= Span!(Span!bool)(20, 50, Span!bool(5, 8, true));
  acc.collapse();
  checkExpectations(acc, [
                      Span!(SpanAccumulator!bool)(0, 50, SpanAccumulator!bool(0, 8, true))
                    ]);
}
