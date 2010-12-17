private {
  import std.algorithm : map, min, reduce;
  import std.array;
  import std.date;
  import std.stdio;
  import std.bind;

  import skia.core.bitmap;
  import skia.core.canvas;
  import skia.core.color : Red, Black;
  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.rect;

  import skia.core.edgebuilder;
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
  paintFillAA = new Paint(Black);
  paintFillAA.antiAlias = true;
  paintHairLine = new Paint(Black);
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

void circles(string paint)() {
  mixin("canvas.drawCircle(FPoint(xSize*0.5, ySize*0.5),
                    min(xSize, ySize)*0.5, "~paint~");");
}
void roundRect(string paint)() {
  mixin("canvas.drawRoundRect(rect, xSize >> 5, ySize >> 5, "~paint~");");
}

void BenchConfig(string paint)() {
  writeln("--------------------"~paint~"--------------------");
  auto times = benchmark!(rectangles!(paint),
                          circles!(paint),
                          roundRect!(paint)
                          )
    (numRuns);
  foreach(ref time; times) {time /= numRuns;}
  writefln("Avg. times [rectangles: %sms, circles: %sms, roundRects: %sms]",
           times[0], times[1], times[2]);
}

void runBenchmark() {
  ulong[] times;
  rectangles!("paintFillAA")();

  BenchConfig!("paintFill");
  BenchConfig!("paintFillAA");
  BenchConfig!("paintHairLine");
  BenchConfig!("paintHairLineAA");

  writeln("\n--------------------With alpha == 127--------------------\n");

  BenchConfig!("paintFill");
  BenchConfig!("paintFillAA");
  BenchConfig!("paintHairLine");
  BenchConfig!("paintHairLineAA");
}

void benchSqrt() {
  real sum = 0.0;
  for (auto i = 0; i < 1_000_000; ++i) {
    sum += fast_sqrt(i);
  }
}

void benchCubicEdge() {
  auto app = appender!(FEdge[])();
}
int main() {
  runBenchmark();
  auto res = benchmark!(benchSqrt)(numRuns);
  writefln("benchSqrt %sns", res[0] / numRuns);
  return 0;
}