module skia.core.shader;

import skia.core.pmcolor;

interface Shader {
  void getRange(int x, int y, ref PMColor[] data);
  @property bool opaque() const;
}

class ColorShader : Shader {
  PMColor color;
  this(Color color) {
    this(PMColor(color));
  }
  this(PMColor color) {
    this.color = color;
  }

  void getRange(int x, int y, ref PMColor[] data) {
    data[] = color;
  }

  @property bool opaque() const {
    return color.opaque;
  }
}
