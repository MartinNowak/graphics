module skia.util.span;

private {
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
    return formatString("Span: start: %s end: %s value: %s", this.start, this.end, this.value);
  }
  @property Index length() const {
    return checkedTo!Index(this.end - this.start);
  }
  Index start;
  Index end;
  T value;
}

struct Span(T : void, Index = size_t) {
  this(Index start, Index end) {
    this.start = start;
    this.end = end;
  }
  @property string toString() const {
    return formatString("Span: start: %s end: %s", this.start, this.end);
  }
  @property Index length() const {
    return checkedTo!Index(this.end - this.start);
  }
  Index start;
  Index end;
}


//==============================================================================

enum Policy {
  Sparse,
  PreAllocate,
}

struct SpanAccumulator(T, Index = size_t, Policy policy = Policy.Sparse) {
private:
  static if (is(T == void))
    alias Tuple!(Index, "dist") Node;
  else
    alias Tuple!(Index, "dist", T, "value") Node;
  alias Span!(T, Index) TSpan;

  Index start;
  debug Index end;
  Node[] nodes;

public:

  this(Index start, Index end) {
    assert(end > start);
    this.start = start;
    debug this.end = end;

    static if (policy == Policy.Sparse) {
      this.nodes.length = 1;
    } else {
      this.nodes.length = end - start;
    }
    this.nodes.front.dist = checkedTo!Index(end - start);
  }

  static if (!is(T == void)) {
    this(Index start, Index end, T init = T.init) {
      this(start, end);
      this.nodes.front.value = init;
    }
  }

  this(in SpanAccumulator other) {
    this = other;
  }
  ref SpanAccumulator opAssign(in SpanAccumulator other) {
    this.start = other.start;
    debug this.end = other.end;
    this.nodes = other.nodes.dup;
    return this;
  }

  void opOpAssign(string op, T2)(in Span!(T2, Index) span) {
    assert(span.end > span.start);

    auto slice = this[span.start .. span.end];
    assert(slice.nodes.length);

    static if (!is(T == void)) {
      foreach(ref Node node; slice) {
        mixin("node.value" ~ op ~ "= span.value;");
      }
    }
  }

  @property string toString() const {
    return formatString("SpanAccumulator!(%s) start: %s \n\tnodes:%s", typeid(T), this.start, this.nodes);
  }

  Range opSlice() {
    return Range(this.start, this.nodes.save);
  }

  Range opSlice(Index x, Index y) {
    auto start = this.breakAt(x);
    auto end = this.breakAt(y);
    return Range(x, this.nodes[start .. end]);
  }

  void reset(in TSpan init) {
    this.nodes.length = init.length;
    this.start = init.start;
    debug this.end = init.end;
    this.nodes.front.dist = init.length;
    static if (!is(T == void))
      this.nodes.front.value = init.value;
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
        static if (is(T == void))
          auto span = TSpan(pos, checkedTo!Index(pos + node.dist));
        else
          auto span = TSpan(pos, checkedTo!Index(pos + node.dist), node.value);
        auto ret = dg(span);
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
    this.check();
    assert(ret <= this.nodes.length);
  }
  body {
    if (where == this.start)
      return 0;

    auto where_bak = where;
    size_t idx = 0;
    while (where > nodes[idx].dist) {
      where -= nodes[idx].dist;
      static if (policy == Policy.Sparse)
        ++idx;
      else
        idx += nodes[idx].dist;
      assert(idx < this.nodes.length, formatString("where:%s idx:%s len:%s",
                                                   where_bak, idx, this.nodes.length));
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
    static if (is(T == void))
      auto newNode = Node(remaining);
    else
      auto newNode = Node(remaining, this.nodes[idx].value);

    static if (policy == Policy.Sparse) {
      this.nodes.insert(idx + 1, newNode);
      return idx + 1;
    } else {
      this.nodes[idx + where] = newNode;
      return idx + where;
    }
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

void checkFor(T, Idx, Policy policy)() {

  auto acc = SpanAccumulator!(T, Idx, policy)(0, 100, 1);
  acc += Span!(T, Idx)(20, 80, 2);

  void checkExpectations(Span!(T, Idx)[] exp) {
    foreach(Span!(T, Idx) span; acc[]) {
      assert(!exp.empty && span == exp.front, formatString("exp:%s act:%s", exp, span));
      exp.popFront;
    }
  }

  checkExpectations([
                      Span!(T, Idx)(0, 20, 1),
                      Span!(T, Idx)(20, 80, 3),
                      Span!(T, Idx)(80, 100, 1),
                    ]);

  acc *= Span!(T, Idx)(15, 25, 2);
  checkExpectations([
                      Span!(T, Idx)(0, 15, 1),
                      Span!(T, Idx)(15, 20, 2),
                      Span!(T, Idx)(20, 25, 6),
                      Span!(T, Idx)(25, 80, 3),
                      Span!(T, Idx)(80, 100, 1),
                    ]);

  acc = SpanAccumulator!(T, Idx, policy)(0, 100, 1);
  checkExpectations([
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
  auto acc = SpanAccumulator!(void)(0, 100);
  acc += Span!void(20, 80);
  auto exps = [Span!void(0, 20), Span!void(20, 80), Span!void(80, 100)];
  foreach(Span!void sp; acc[]) {
    assert(sp == exps.front);
    exps.popFront;
  }
}

unittest {
  auto acc = SpanAccumulator!(SpanAccumulator!int)(0, 5, SpanAccumulator!int(0, 10, 111));
  acc += Span!(Span!int)(2, 4, Span!int(0, 5, 666));

  void checkExpectations(Tuple!(int, int, Span!(int))[] exp) {
    foreach(Span!(SpanAccumulator!(int)) accsp; acc[]) {
      foreach(Span!int sp; accsp.value[]) {
        assert(tuple(accsp.start, accsp.end, sp) == exp.front,
               formatString("exp:%s act:%s", exp.front, tuple(accsp.start, accsp.end, sp)));
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
  auto acc = SpanAccumulator!(SpanAccumulator!void)(0, 5, SpanAccumulator!void(0, 10));
  acc += Span!(Span!void)(2, 4, Span!void(0, 5));

  void checkExpectations(Tuple!(int, int, Span!(void))[] exp) {
    foreach(Span!(SpanAccumulator!(void)) accsp; acc[]) {
      foreach(Span!void sp; accsp.value[]) {
        assert(tuple(accsp.start, accsp.end, sp) == exp.front, to!string(exp.front));
        exp.popFront;
      }
    }
  }
  checkExpectations([
                      tuple(0, 2, Span!(void)(0, 10)),
                      tuple(2, 4, Span!(void)(0, 5)),
                      tuple(2, 4, Span!(void)(5, 10)),
                      tuple(4, 5, Span!(void)(0, 10)),
                    ]);
}
