module graphics.svg;

// The SVG engine lives in graphics.svg.render (parse + paint pipeline),
// with the XML cursor helper in graphics.svg.parser. `renderSVG` is the
// entry point.
public import graphics.svg.parser, graphics.svg.render;
