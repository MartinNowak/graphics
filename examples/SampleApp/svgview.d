module SampleApp.svgview;

debug import std.stdio;
import std.algorithm, std.exception, std.functional, std.string, std.range, std.xml, std.conv : to;
static import std.ctype;
import skia.core.canvas, skia.views.view2, skia.core.path, skia.core.paint;
import guip.color, guip.event, guip.point, guip.rect, guip.size, layout.hint;

class SvgView : View {
  this(string svgpath) {
    string svg;
    try {
      svg = cast(string)std.file.read(svgpath);
    } catch (Exception e) {
      std.stdio.writeln(e);
    }
    if (!svg.empty)
      parseSvg(svg);
  }

  override void onResize(ResizeEvent e) {
    this.requestRedraw(IRect(e.area.size));
  }

  override void onDraw(Canvas canvas, IRect area, ISize size) {
    canvas.translate(fPoint(IRect(size).center - this.bounds.center));
    foreach(ref path, ref style; lockstep(this.paths, this.styles)) {
      assert(!style.empty);
      if (style.fillColor.a) {
        scope auto paint = new Paint(style.fillColor);
        canvas.drawPath(path, paint);
      }
      if (style.strokeColor.a) {
        scope auto paint = new Paint(style.strokeColor);
        paint.fillStyle = Paint.Fill.Stroke;
        paint.strokeWidth = style.strokeWidth;
        canvas.drawPath(path, paint);
      }
    }
  }

  override SizeHint sizeHint() const {
    return SizeHint(Hint(this.bounds.width, 5.0), Hint(this.bounds.height, 5.0));
  }

  void parseSvg(string content) {
    auto svg = new DocumentParser(content);
    Style groupStyle;
    auto pathParser = (ElementParser pathElem) {
      if (auto curve = "d" in pathElem.tag.attr) {
        auto style = parseStyle(pathElem.tag.attr, groupStyle);
        Path path;
        if (!style.empty && parsePath(*curve, path)) {
          this.styles ~= style;
          this.paths ~= path;
          this.bounds.join(path.ibounds);
        }
      }
    };
    svg.onStartTag["path"] = pathParser;
    svg.onStartTag["g"] = (ElementParser group) {
      groupStyle = parseStyle(group.tag.attr, groupStyle);
      group.onStartTag["path"] = pathParser;
      group.parse();
      groupStyle = Style();
    };
    svg.parse();
    assert(this.paths.length == this.styles.length);
    std.stdio.writeln(this.paths.length);
  }

  static struct Style {
    @property bool empty() const {
      return this.strokeColor.a == 0 && this.fillColor.a == 0;
    }

    Color fillColor = Black;
    Color strokeColor = Color(0);
    float strokeWidth = 1.0f;
  }

  Style parseStyle(in string[string] attributes, in Style parentStyle) {
    Style style = parentStyle;

    auto styleDict = parseStyleAttribute("style" in attributes);
    auto attrDict = cast(string[string])attributes;

    // TODO: need to combine stroke and fill
    string* strokeW = "stroke-width" in styleDict;
    if (strokeW is null) strokeW = "stroke-width" in attrDict;
    if (strokeW !is null)
      style.strokeWidth = to!float(*strokeW);

    string* strokeC = "stroke" in styleDict;
    if (strokeC is null) strokeC = "stroke" in attrDict;
    if (strokeC !is null)
      style.strokeColor = toupper(*strokeC) == "NONE" ? Color(0) : color(*strokeC);

    string* fillC = "fill" in styleDict;
    if (fillC is null) fillC = "fill" in attrDict;
    if (fillC !is null)
      style.fillColor = toupper(*fillC) == "NONE" ? Color(0) : color(*fillC);

    return style;
  }

  static isdigit(dchar c) { return c == '.' || c == '-' || std.ctype.isdigit(c); }

  bool parsePath(string curve, out Path path) {
    curve = stripl(curve);
    if (!curve.length || (curve.front != 'M' && curve.front != 'm'))
      return false;

    float parseFloat() {
      auto tail = find!(not!isdigit)(curve);
      auto f = to!float(curve[0 .. $ - tail.length]);
      curve = stripl(tail);
      return f;
    }

    FPoint parsePt() {
      auto f0 = parseFloat();
      auto f1 = parseFloat();
      return FPoint(f0, f1);
    }

    auto lastPt = FPoint(0, 0);

    while (!curve.empty) {
      auto c = curve.front; curve.popFront;
      curve = stripl(curve);

      switch (c) {
      case 'm':
        lastPt += parsePt();
        path.moveTo(lastPt);
        break;

      case 'M':
        lastPt = parsePt();
        path.moveTo(lastPt);
        break;

      case 'l':
        lastPt += parsePt();
        path.lineTo(lastPt);
        break;

      case 'L':
        lastPt = parsePt();
        path.lineTo(lastPt);
        break;

      case 'c':
        auto c0 = lastPt + parsePt();
        auto c1 = lastPt + parsePt();
        lastPt += parsePt();
        path.cubicTo(c0, c1, lastPt);
        break;

      case 'C':
        auto c0 = parsePt();
        auto c1 = parsePt();
        lastPt = parsePt();
        path.cubicTo(c0, c1, lastPt);
        break;

      case 'z':
        path.close();
        //        lastPt = ??
        break;

      default:
        assert(0, "error" ~ to!string(c) ~ "|");
      }
    }
    return true;
  }

  string[string] parseStyleAttribute(in string* pstyles) {
    if (pstyles is null)
      return null;

    string styles = *pstyles;
    typeof(return) result;
    foreach(style; splitter(styles, ';')) {
      if (!style.empty) {
        auto semi = split(style, ":");
        enforce(semi.length == 2);
        result[strip(semi[0])] = strip(semi[1]);
      }
    }
    return result;
  }

  Path[] paths;
  Style[] styles;
  IRect bounds;
}
