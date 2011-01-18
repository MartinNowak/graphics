module skia.util.format;

private {
  import std.array : appender;
  import std.format : formattedWrite;
}

string formatString(TL...)(string fmt, TL tl) {
  auto writer = appender!string();
  formattedWrite(writer, fmt, tl);
  return writer.data;
}
