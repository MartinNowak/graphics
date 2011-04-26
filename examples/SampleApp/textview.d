module SampleApp.textview;

debug import std.stdio : writeln;
import skia.core.canvas, skia.core.pmcolor, skia.core.matrix, skia.core.paint, skia.core.path, skia.views.view2, skia.core.fonthost._;
import guip.event, guip.point, guip.rect, guip.size, layout.hint;
import std.range, std.array;


class TextView : View
{
  string[] texts;
  string text;
  enum { Left, Right, PathText, EnumLimit }
  int which;

  this() {
    this.texts = ["Dann folgte ein Tag", "dem anderen", "ohne",
                  "dasz die Grundfragen des Lebens", "gelöst worden wären.", "VA"];
    this.text = "abcdefghijklmnopqrstuvwxyz";
  }

  override void onButton(ButtonEvent e, ISize size) {
    if (e.isRelease()) {
      this.which = (this.which + 1) % EnumLimit;
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

    switch (this.which) {
    case Left: {
      textPaint.textAlign = TextPaint.TextAlign.Right;
      auto pt = fPoint(bounds.center);
      canvas.drawTextAsPaths("text rendered from outlines", pt, textPaint);

      break;
    }
    case Right: {
      textPaint.textAlign = TextPaint.TextAlign.Right;
      auto pt = fPoint(bounds.center);
      auto metrics = textPaint.fontMetrics();
      canvas.drawRect(
          FRect(0.5f, pt.y + metrics.ascent, size.width - 0.5f, pt.y + metrics.descent),
          framePaint);
      canvas.drawText("text rendered from bitmaps", pt, textPaint);

      break;
    }
    case PathText: {
      auto metrics = textPaint.fontMetrics();
      auto baseline = fRect(bounds).inset(-metrics.top, -metrics.top);

      auto up = metrics.underlinePos;
      framePaint.strokeWidth = metrics.underlineThickness;
      framePaint.color = Black;
      canvas.drawRoundRect(baseline.inset(up, up), 50.0f, 50.0f, framePaint);

      Path path;
      path.addRoundRect(baseline, 50.0f, 50.0f);
      auto t = to!string(take(cycle("text rendered on path"), 200));
      canvas.drawTextOnPath(t, path, textPaint);

      break;
    }
    default:
      assert(0);
    }
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(1200, 0.2), Hint(1200, 0.2));
  }
}
