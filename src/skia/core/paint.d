module skia.core.paint;

private {
  import skia.core.color;
  import skia.core.drawlooper;
}

class Paint
{
  Color color;
  DrawLooper drawLooper;

  this(Color color) {
    this.color = color;
  }
}
