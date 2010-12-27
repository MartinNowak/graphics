module skia.core.stroke_detail.capper;

private {
  import skia.core.paint;
}
alias void function() Capper;
Capper getCapper(Paint.Cap capStyle) {
  return &NullCapper;
}

void NullCapper() {}


