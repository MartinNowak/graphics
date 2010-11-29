module skia.core.regionpath;

import std.array;
import std.algorithm : reduce;
debug import std.stdio : writeln;

import skia.core.blitter;
import skia.core.path;
import skia.core.region;
import skia.core.rect;

/****************************************
 * Glue module between regions and paths.
 */

struct ScanLine
{
  RunType[] runs;
  RunType lastY;

  this(RunType initialY) {
    this.lastY = initialY;
  }

  @property string toString() const {
    return "ScanLine runs:" ~ to!string(this.runs.length)
      ~ "lastY: " ~ to!string(this.lastY);
  }
  void append(RunType x, RunType width) {
    // Extend the current scanline?
    if (this.runs.length > 0
        && this.runs[$-1] == x) {
      this.runs[$-1] = x + width;
    }
    else {
      this.runs ~= [x, x + width];
    }
  }
}

class RgnBuilder : Blitter
{
  ScanLine[] scanLines;
  RunType top;

  @property string toString() const {
    auto res = "RgnBuilder top:" ~ to!string(this.top);
    foreach(sl; this.scanLines) {
      res ~= to!string(sl) ~ "\n";
    }
    return res;
  }

  private @property ref ScanLine currScanLine() {
    assert(!this.scanLines.empty);
    return this.scanLines[$-1];
  }

  private @property ref ScanLine prevScanLine() {
    assert(this.scanLines.length > 1);
    return this.scanLines[$-2];
  }

  bool isNewLine(RunType y) {
    if (this.scanLines.empty) {
      return true;
    }
    else {
      return y > this.currScanLine.lastY;
    }
  }

  void appendScanLine(RunType y) {
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

  void collapsePrev() {
    if (this.scanLines.length > 1
        && this.prevScanLine.lastY + 1 == this.currScanLine.lastY
        && this.prevScanLine.runs == this.currScanLine.runs) {
      this.prevScanLine.lastY = this.currScanLine.lastY;
      this.scanLines.popBack();
    }
  }

  void blitH(int x, int y, uint width) {
    if (this.isNewLine(y)) {
      this.collapsePrev();
      this.appendScanLine(y);
    }
    this.currScanLine.append(x, width);
  }

  void done() {
    this.collapsePrev();
  }

  uint computeRunCount() {
    return reduce!"a + 3 + b.runs.length"(1, this.scanLines);
  }

  IRect getRect() {
    assert(this.scanLines.length == 1);
    assert(this.currScanLine.runs.length == 2);

    auto left = this.currScanLine.runs[0];
    auto top = this.top;
    auto right = this.currScanLine.runs[1];
    auto bottom = this.currScanLine.lastY + 1;
    return IRect(left, top , right, bottom);
  }

  RunType[] getRuns() {
    RunType[] runs;
    runs ~= this.top;
    foreach(sl; this.scanLines) {
      runs ~= sl.lastY + 1;
      runs ~= sl.runs.length;
      if (sl.runs.length)
        runs ~= sl.runs;
      runs ~= Region.RunTypeSentinel;
    }
    runs ~= Region.RunTypeSentinel;
    return runs;
  }
}
