module skia.core.paint;
import skia.core.color;

struct Paint
{
  this(Color color) {
    this.color = color;
  }

  Color color;
}
