module test.wavelet_raster;

import skia.core.paint, skia.core.path, skia.core.wavelet.raster;
import guip._;

void main() {
  enum res = 2048;
  auto bmp = Bitmap();
  bmp.setConfig(Bitmap.Config.A8, res, res);
  bmp.getBuffer!ubyte[] = 255;

  Path path;
  path.moveTo(FPoint(0, 1000));
  path.quadTo(FPoint(res, 1000), FPoint(res, 1000 + res));
  auto wr = pathToWavelet(path);
//  auto wr = WaveletRaster(IRect(res, res));
//  wr.insertEdge([FPoint(0, 0), FPoint(res, 0), FPoint(res/2, res/2)]);
//  wr.insertEdge([FPoint(res/2, res/2), FPoint(res, res), FPoint(0, res)]);
//  wr.insertEdge([FPoint(0, res), FPoint(0, 0)]);
  std.stdio.writeln("coeffs", wr.root.coeffs);
  auto blitdg = bmpBlit(bmp);
  writeNodeToGrid!blitdg(wr.root, wr.rootConst, IPoint(0, 0), res);
  bmp.save("pathwavelet.png");

//  auto grid = bmp.getBuffer!ubyte[];
//  foreach(y; 0 .. res) {
//    std.stdio.writeln(grid[y*res .. y*res + res]);
//  }
}
