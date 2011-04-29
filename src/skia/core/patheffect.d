module skia.core.patheffect;

import skia.core.path;

interface PathEffect {
  Path filterPath(Path path, ref float width) const;
}
