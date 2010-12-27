module skia.core.stroke_detail.joiner;

private {
  import skia.core.paint;
}
alias void function() Joiner;
Joiner getJoiner(Paint.Join joinStyle) {
  return &NullJoiner;
}

void NullJoiner() {}
