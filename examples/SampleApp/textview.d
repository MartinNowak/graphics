module SampleApp.textview;

private {
  debug private import std.stdio : writeln;

  import guip.size;
  import skia.core.canvas;
  import skia.core.color;
  import skia.core.matrix;

  import skia.core.paint;
  import skia.core.path;
  import guip.point;
  import skia.core.rect;
  import skia.views.view;
}


class TextView : View
{
  string[] texts;
  string text;
  enum { Left, Right, PathText, EnumLimit }
  int which;

  this() {
    this._flags.visible = true;
    this._flags.enabled = true;
    this.texts = ["Dann folgte ein Tag", "dem anderen", "ohne",
                  "dasz die Grundfragen des Lebens", "gelöst worden wären.", "VA"];
    this.text = "abcdefghijklmnopqrstuvwxyz";
  }

  override void onButtonPress(IPoint pt) {
    this.which = (this.which + 1) % EnumLimit;
    this.inval(this.bounds);
  }

  override void onDraw(Canvas canvas) {
    scope auto paintText = new Paint(Black);
    switch (this.which) {
    case Left: {
      paintText.textAlign = Paint.TextAlign.Right;
      auto pt = fPoint(this.bounds.center);
      canvas.drawTextAsPaths("TextRenderedFromOutlines", pt, paintText);

      break;
    }
    case Right: {
      paintText.textAlign = Paint.TextAlign.Right;
      auto pt = fPoint(this.bounds.center);
      canvas.drawText("TextRenderedFromBitmaps", pt, paintText);

      break;
    }
    case PathText: {
      Path path;
      auto frame = this.bounds.inset(10, 10);
      path.addRoundRect(fRect(frame), 50.0f, 50.0f);
      canvas.drawTextOnPath("TextRenderedOnPaths", path, paintText);

      break;
    }
    default:
      assert(0);
    }
  }
}
