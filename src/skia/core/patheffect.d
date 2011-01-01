module skia.core.patheffect;

private {
  import skia.core.path;
}

interface PathEffect {
  Path filterPath(Path path, ref float width) const;
}
