module skia.core.regionpath;

private {
 import std.array;
 import std.algorithm : reduce;
 debug(PRINTF) import std.stdio : writeln;

 import skia.core.blitter;
 import skia.core.path;
 import skia.core.region;
 import skia.core.rect;
}
//version=VERBOSE;
//debug=PRINTF;

/****************************************
 * Glue module between regions and paths.
 */
class RgnBuilder : Blitter
{
  ScanLines scanLines;

  @property string toString() const {
    return "RgnBuilder scanLines:" ~ to!string(this.scanLines);
  }

  override void blitFH(float y, float xStart, float xEnd) {
    debug(PRINTF) writeln("RgnBuilder.blitH", "x:", x, "y:",y, "w:",width);
    this.scanLines.appendSpan(this.round(y), this.round(xStart), this.round(xEnd - xStart));
  }

  void done() {
    this.scanLines.collapsePrev();
  }
}

private {
  import std.algorithm : max, min;
  import std.conv : to;

  import skia.core.rect;
}

package {
  alias int ValueT;
}

private struct Span
{
  ValueT begin;
  ValueT end;

  @property string toString() const {
    return to!string(this.begin) ~
      "-" ~ to!string(this.end);
  }

  this(ValueT begin, ValueT end) {
    this.begin = begin;
    this.end = end;
  }

  Span joinSpan(ValueT begin, ValueT end) const {
    return Span(min(this.begin, begin), max(this.end, end));
  }
}

/** ScanLine
 *  struct holding a single scanline.
 */
private struct ScanLine {
  Span[] spans;
  ValueT lastY;

  this(ValueT initialY) {
    this.lastY = initialY;
  }

  Span joinSpan(Span v) const {
    return this.spans.length > 0
      ? v.joinSpan(this.spans[0].begin, this.spans[$-1].end)
      : v;
  }
  @property string toString() const {
      auto res = "ScanLine numSp:" ~ to!string(this.spans.length)
        ~ " lastY: " ~ to!string(this.lastY);
      version(VERBOSE)
        res ~= " Spans->" ~ to!string(this.spans);
      return res;
  }

  void append(ValueT x, ValueT width) {
    assert(width > 0);
    if (this.spans.length > 0
        && this.spans[$-1].end == x) {
      this.spans[$-1].end = x + width;
    }
    else {
      this.spans ~= Span(x, x + width);
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

/****************************************
 *
 */
struct ScanLines {
package:
  ScanLine[] scanLines;
  ValueT top;
  IRect _bounds;
  bool boundsAreClean;

  enum NumRectScanLines = 1;

public:
  string toString() const {
    string res;
    res ~= "ScanLines, bounds: " ~ to!string(this.bounds) ~
      "\ttop: " ~ to!string(this.top) ~ "\n";
    version(VERBOSE)
      res ~= to!string(this.scanLines);
    return res;
  }

package:

  @property bool empty() const {
    return this.scanLines.empty;
  }
  void appendSpan(ValueT y, ValueT x, ValueT width) {
    if (this.isNewLine(y)) {
      this.collapsePrev();
      this.appendScanLine(y);
    }
    this.currScanLine.append(x, width);
  }

  void collapsePrev() {
    if (this.scanLines.length > 1
        && this.prevScanLine.lastY + 1 == this.currScanLine.lastY
        && this.prevScanLine.spans == this.currScanLine.spans) {
      this.prevScanLine.lastY = this.currScanLine.lastY;
      this.scanLines.popBack();
    }
  }

  @property IRect bounds() const {
    if (this.boundsAreClean) {
      return this._bounds;
    }
    else {
      auto ncThis = cast(ScanLines*)&this;
      ncThis._bounds = this.computeBounds();
      ncThis.boundsAreClean = true;
      return ncThis._bounds;
    }
  }

  Region.Type getType() const {
    if (this.scanLines.empty || this.bounds.empty) {
      return Region.Type.Empty;
    }
    else if (this.scanLines.length == ScanLines.NumRectScanLines) {
      return Region.Type.Rect;
    }
    else {
      return Region.Type.Complex;
    }
  }

  void opAssign(in IRect rect) {
    this.scanLines.length = 0;

    this.top = rect.top;
    this.appendScanLine(rect.bottom);
    this.currScanLine.append(rect.left, rect.right);

    this._bounds = rect;
    this.boundsAreClean = true;
  }

  void opAssign(in ScanLines scanLines) {
    this.scanLines = scanLines.scanLines.dup;
    this.top = scanLines.top;
    this._bounds = scanLines._bounds;
    this.boundsAreClean = scanLines.boundsAreClean;
  }

private:

  IRect getRect() const {
    assert(this.scanLines.length == 1);
    assert(this.currScanLine.spans.length == 1);

    auto left = this.currScanLine.spans[0].begin;
    auto top = this.top;
    auto right = this.currScanLine.spans[0].end;
    auto bottom = this.currScanLine.lastY + 1;
    return IRect(left, top , right, bottom);
  }

  bool isNewLine(ValueT y) {
    if (this.scanLines.empty) {
      return true;
    }
    else {
      return y > this.currScanLine.lastY;
    }
  }

  void appendScanLine(ValueT y) {
    this.boundsAreClean = false;
    if (this.scanLines.empty) {
      this.top = y;
      this.scanLines ~= ScanLine(y);
    }
    else {
      assert(y > this.currScanLine.lastY);
      // insert empty scanline between y jump
      if (y - 1 > this.currScanLine.lastY) {
        this.scanLines ~= ScanLine(y - 1);
      }
      this.scanLines ~= ScanLine(y);
    }
  }

  private @property const(ScanLine) currScanLine() const {
    assert(!this.scanLines.empty);
    return this.scanLines[$-1];
  }

  private @property ref ScanLine currScanLine() {
    assert(!this.scanLines.empty);
    return this.scanLines[$-1];
  }

  private @property ref ScanLine prevScanLine() {
    assert(this.scanLines.length > 1);
    return this.scanLines[$-2];
  }


  IRect computeBounds() const
  {
    if (this.scanLines.empty) {
      return IRect();
    }
    if (this.scanLines.length == NumRectScanLines)
    {
      return this.getRect();
    }
    else {
      IRect bounds;
      auto xspan = Span(ValueT.max, ValueT.min);
      bounds.top = this.top;
      foreach(sl; this.scanLines) {
        xspan = sl.joinSpan(xspan);
      }
      bounds.left = xspan.begin;
      bounds.right = xspan.end;
      bounds.bottom = this.scanLines[$-1].lastY + 1;
      return bounds;
    }
  }
}


unittest
{
  ScanLines sl;
  for (auto i = 0; i < 100; ++i) {
    sl.appendSpan(10 + i, 0, 100);
  }
  sl.collapsePrev();
  assert(sl.getType() == Region.Type.Rect);
  assert(sl.bounds() == IRect(0, 10, 100, 110));

  sl = ScanLines.init;
  sl.appendSpan(10, 10, 20);
  sl.appendSpan(13, 11, 20);
  sl.appendSpan(15, 12, 20);
  sl.appendSpan(17, 13, 20);
  sl.collapsePrev();
  assert(sl.bounds() == IRect(10, 10, 33, 18));
}
