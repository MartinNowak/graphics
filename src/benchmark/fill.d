module benchmark.fill;

private {
  import std.algorithm : map, min, reduce;
  import Date = std.date;
  import std.array;
  import std.stdio;

  import skia.core.bitmap;
  import skia.core.canvas;
  import skia.core.color : Red, Black;
  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;

  import skia.core.edgebuilder;
  import benchmark._;
}

static this() {
  registerBenchmark!(runFillPlain)();
  registerBenchmark!(runFillPlainWithAlpha)();
  registerBenchmark!(runFillAntiAliased)();
  registerBenchmark!(runFillAntiAliasedWithAlpha)();
}

////////////////////////////////////////////////////////////////////////////////

enum numRuns = 50;
enum xSize = 1000;
enum ySize = 1000;

////////////////////////////////////////////////////////////////////////////////

static Canvas canvas;
static Bitmap bitmap;
static Paint paintFill;
static Paint paintFillAA;
static Paint paintHairLine;
static Paint paintHairLineAA;
static IRect rect;

static this() {
  bitmap = new Bitmap(Bitmap.Config.ARGB_8888, xSize, ySize);
  canvas = new Canvas(bitmap);
  paintFill = new Paint(Black);
  paintFill.antiAlias = false;
  paintFillAA = new Paint(Black);
  paintFillAA.antiAlias = true;
  paintHairLine = new Paint(Black);
  paintHairLine.antiAlias = false;
  paintHairLine.fillStyle = Paint.Fill.Stroke;
  paintHairLineAA = new Paint(Black);
  paintHairLineAA.fillStyle = Paint.Fill.Stroke;
  paintHairLineAA.antiAlias = true;

  rect = IRect(xSize, ySize);
}

////////////////////////////////////////////////////////////////////////////////

void rectangles(string paint)() {
  mixin("canvas.drawRect(rect, "~paint~");");
}

void roundRect(string paint)() {
  mixin("canvas.drawRoundRect(rect, xSize >> 5, ySize >> 5, "~paint~");");
}

void circles(string paint)() {
  mixin("canvas.drawCircle(FPoint(xSize*0.5, ySize*0.5),
                    min(xSize, ySize)*0.5, "~paint~");");
}

////////////////////////////////////////////////////////////////////////////////

void BenchConfig(string paint)(BenchmarkReporter reporter) {
  reporter.log!(LogLevel.Info)("--------------------"~paint~"--------------------");
  const numRuns = reporter.numHint;
  reporter.bench!(rectangles!(paint))();
  reporter.bench!(roundRect!(paint))();
  reporter.bench!(circles!(paint))();
}

void runFillPlain(BenchmarkReporter reporter) {
  BenchConfig!("paintFill")(reporter);
  BenchConfig!("paintHairLine")(reporter);
}

void runFillPlainWithAlpha(BenchmarkReporter reporter) {
  paintFill.color.a = ubyte.max >> 1; paintHairLine.color.a = ubyte.max >> 1;
  scope(exit) paintFill.color.a = ubyte.max; paintHairLine.color.a = ubyte.max;

  BenchConfig!("paintFill")(reporter);
  BenchConfig!("paintHairLine")(reporter);
}

void runFillAntiAliased(BenchmarkReporter reporter) {
  BenchConfig!("paintFillAA")(reporter);
  BenchConfig!("paintHairLineAA")(reporter);
}

void runFillAntiAliasedWithAlpha(BenchmarkReporter reporter) {
  paintFillAA.color.a = ubyte.max >> 1; paintHairLineAA.color.a = ubyte.max >> 1;
  scope(exit) paintFillAA.color.a = ubyte.max; paintHairLineAA.color.a = ubyte.max;

  BenchConfig!("paintFillAA")(reporter);
  BenchConfig!("paintHairLineAA")(reporter);
}
