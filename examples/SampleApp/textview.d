module SampleApp.textview;

debug import std.stdio : writeln;
import skia.core.canvas, skia.core.pmcolor, skia.core.matrix, skia.core.paint, skia.core.path, skia.views.view2, skia.core.fonthost._;
import guip.event, guip.point, guip.rect, guip.size, layout.hint;
import std.range, std.array;


class TextView : View
{
  enum mayröcker = [
      "Dann folgte ein Tag",
      "dem anderen",
      "ohne",
      "dasz die Grundfragen des Lebens",
      "gelöst worden wären.",
      "Friederike Mayröcker",
  ];
  string text;
  enum State { One, Two, Three, Four }
  State state;

  enum lorem = [
      "Lorem ipsum dolor sit amet, consetetur sadipscing elitr,",
      "sed diam nonumy eirmod tempor invidunt ut labore et",
      "dolore magna aliquyam erat, sed diam voluptua.",
      "At vero eos et accusam et justo duo dolores et ea rebum.",
      "Stet clita kasd gubergren, no sea takimata sanctus est Lorem",
      "ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur",
      "sadipscing elitr, sed diam nonumy eirmod tempor",
      "invidunt ut labore et dolore magna aliquyam erat,",
      "sed diam voluptua. At vero eos et accusam et justo",
      "duo dolores et ea rebum. Stet clita kasd gubergren,",
      "no sea takimata sanctus est Lorem ipsum dolor sit amet.",
  ];

  this() {
    this.text = "abcdefghijklmnopqrstuvwxyz";
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (e.isRelease()) {
      this.state = cast(State)((this.state + 1) % (State.max + 1));
      this.requestRedraw(IRect(size));
    }
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    //    scope auto textPaint = new TextPaint(Black, TypeFace.findFace("DejaVu Sans"));
    scope auto textPaint = new TextPaint(Color(lookupAttr("color")));
    textPaint.textSize = 9.0;
    scope auto framePaint = new Paint(Color(lookupAttr("border-color")));
    framePaint.fillStyle = Paint.Fill.Stroke;
    framePaint.strokeWidth = 1.0;
    framePaint.antiAlias = true;

    auto bounds = IRect(size);

    final switch (this.state) {
    case State.One:
      textPaint.textAlign = TextPaint.TextAlign.Right;
      auto pt = fPoint(bounds.center);
      canvas.drawTextAsPaths("text rendered from outlines", pt, textPaint);

      break;

    case State.Two:
      textPaint.textAlign = TextPaint.TextAlign.Right;
      auto pt = fPoint(bounds.center);
      auto metrics = textPaint.fontMetrics();
      canvas.drawRect(
          FRect(0.5f, pt.y - metrics.ascent, size.width - 0.5f, pt.y - metrics.descent),
          framePaint);
      canvas.drawText("text rendered from bitmaps", pt, textPaint);

      break;

    case State.Three:
      auto metrics = textPaint.fontMetrics();
      auto baseline = fRect(bounds).inset(metrics.top, metrics.top);

      auto up = metrics.underlinePos;
      framePaint.strokeWidth = metrics.underlineThickness;
      framePaint.color = Black;
      canvas.drawRoundRect(baseline.inset(-up, -up), 50.0f, 50.0f, framePaint);

      Path path;
      path.addRect(baseline);
      path.lineTo(baseline.center);
      path.addRect(baseline.inset(20, 20));
      auto t = to!string(take(cycle("text rendered on path"), 1500));
      canvas.drawTextOnPath(t, path, textPaint);

      break;

    case State.Four:
      textPaint.textAlign = TextPaint.TextAlign.Left;
      auto metrics = textPaint.fontMetrics();
      auto cnt = mayröcker.length;
      auto space = size.height - cnt * (metrics.ascent - metrics.descent);
      space /= cnt + 1;
      auto pt = FPoint(0, metrics.ascent + space);
      auto lineInc = metrics.ascent - metrics.descent + space;
      foreach(line; mayröcker[0 .. $ - 1]) {
        canvas.drawText(line, pt, textPaint);
        pt.y = pt.y + lineInc;
      }
      pt.x = bounds.center.x;
      //      textPaint.typeFace = TypeFace.defaultFace(TypeFace.Weight.Bold);
      textPaint.textSize = 14;
      textPaint.textAlign = TextPaint.TextAlign.Center;
      canvas.drawText(mayröcker[$-1], pt, textPaint);
      break;
    }
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(1200, 0.2), Hint(1200, 0.2));
  }
}
