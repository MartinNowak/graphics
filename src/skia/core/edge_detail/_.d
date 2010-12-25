module skia.core.edge_detail._;

import skia.core.edge_detail.edge : Edge;
import skia.core.edge_detail.line_edge : lineEdge, clippedLineEdge;
import skia.core.edge_detail.quad_edge : quadraticEdge, clippedQuadraticEdge;
import skia.core.edge_detail.cubic_edge : cubicEdge, clippedCubicEdge;

alias Edge!float FEdge;
alias Edge!double DEdge;
