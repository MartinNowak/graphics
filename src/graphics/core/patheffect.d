module graphics.core.patheffect;

import graphics.core.path;

interface PathEffect {
  Path filterPath(Path path, ref float width) const;
}
