module skia.core.shader;

import skia.core.pmcolor;

interface Shader {
  const(PMColor)[] getRange(int xStart, int xEnd, int y);
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

  const(PMColor)[] getRange(int xStart, int xEnd, int y)
  in {
    assert(xEnd >= xStart);
  } body {
    PMColor[] result;
    result.length = xEnd - xStart;
    result[] = color;
    return result;
  }

  @property bool opaque() const {
    return color.opaque;
  }
}
