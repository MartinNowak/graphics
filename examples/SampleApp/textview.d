module SampleApp.textview;

debug import std.stdio : writeln;
import skia.core.canvas, skia.core.pmcolor, skia.core.matrix, skia.core.paint, skia.core.path, skia.views.view2, skia.core.fonthost._;
import guip.event, guip.point, guip.rect, guip.size, layout.hint;
import std.range, std.array;


class TextView : View
{
  string[] texts;
  string text;
  enum State { One, Two, Three, Four }
  State state;

  this() {
    this.texts = ["Dann folgte ein Tag", "dem anderen", "ohne",
                  "dasz die Grundfragen des Lebens", "gelöst worden wären."];
    this.text = "abcdefghijklmnopqrstuvwxyz";
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (e.isRelease()) {
      this.state = cast(State)((this.state + 1) % (State.max + 1));
      this.requestRedraw(IRect(size));
    }
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    scope auto textPaint = new TextPaint(Black, TypeFace.findFace("DejaVu Sans"));
    scope auto framePaint = new Paint(Orange);
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
      path.addRoundRect(baseline, 50.0f, 50.0f);
      auto t = to!string(take(cycle("text rendered on path"), 200));
      canvas.drawTextOnPath(t, path, textPaint);

      break;

    case State.Four:
      textPaint.textAlign = TextPaint.TextAlign.Center;
      auto metrics = textPaint.fontMetrics();
      auto cnt = texts.length;
      auto space = size.height - cnt * (metrics.ascent - metrics.descent);
      space /= cnt + 1;
      auto pt = FPoint(bounds.center.x, metrics.ascent + space);
      auto lineInc = metrics.ascent - metrics.descent + space;
      foreach(line; texts) {
        canvas.drawText(line, pt, textPaint);
        pt.y = pt.y + lineInc;
      }
      break;
    }
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(1200, 0.2), Hint(1200, 0.2));
  }
}
