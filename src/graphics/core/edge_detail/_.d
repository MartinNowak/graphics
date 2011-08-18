module graphics.core.edge_detail._;

import graphics.core.edge_detail.edge : Edge;
import graphics.core.edge_detail.line_edge : lineEdge, clippedLineEdge;
import graphics.core.edge_detail.quad_edge : quadraticEdge, clippedQuadraticEdge;
import graphics.core.edge_detail.cubic_edge : cubicEdge, clippedCubicEdge;

alias Edge!float FEdge;
alias Edge!double DEdge;
