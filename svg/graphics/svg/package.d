module graphics.svg;

// The SVG engine comes in two halves: graphics.svg.parser turns a document
// into a sealed node arena + id registry (Document), graphics.svg.render
// walks that arena and paints it. `renderSVG` is the entry point that
// stitches the two together.
public import graphics.svg.parser, graphics.svg.render;
