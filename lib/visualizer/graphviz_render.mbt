///|
fn attr(key : String, value : String) -> @dot.Attribute {
  { key, value }
}

///|
fn attrs(attributes : Array[@dot.Attribute]) -> @dot.AttributeList {
  { attributes, }
}

///|
fn node_id(id : String) -> @dot.NodeId {
  { id, port: None }
}

///|
fn node_color(status : VisualNodeStatus) -> String {
  match status {
    Neutral => "#3b4252"
    Active => "#5e81ac"
    Changed => "#a3be8c"
    Failed => "#bf616a"
  }
}

///|
fn node_fill(status : VisualNodeStatus) -> String {
  match status {
    Neutral => "#eceff4"
    Active => "#d8dee9"
    Changed => "#e5f1dc"
    Failed => "#f3d6d8"
  }
}

///|
fn node_label(node : VisualNode) -> String {
  let base = node.label.unwrap_or(node.id)
  match node.detail {
    Some(detail) => base + "\n" + detail
    None => base
  }
}

///|
fn node_statement(node : VisualNode) -> @dot.Statement {
  NodeStmt(
    node_id(node.id),
    Some(
      attrs([
        attr("label", node_label(node)),
        attr("color", node_color(node.status)),
        attr("fontcolor", "#1f2933"),
        attr("fillcolor", node_fill(node.status)),
      ]),
    ),
  )
}

///|
fn edge_statement(edge : VisualEdge) -> @dot.Statement {
  let edge_attrs = match edge.label {
    Some(label) => Some(attrs([attr("label", label)]))
    None => None
  }
  EdgeStmt(node_id(edge.from), [(Directed, node_id(edge.to))], edge_attrs)
}

///|
fn VisualGraph::to_dot_graph(self : VisualGraph) -> @dot.Graph {
  let statements : Array[@dot.Statement] = [
    AttrStmt(
      GraphAttr,
      attrs([attr("rankdir", "LR"), attr("bgcolor", "transparent")]),
    ),
    AttrStmt(
      NodeAttr,
      attrs([
        attr("shape", "box"),
        attr("style", "rounded,filled"),
        attr("fontname", "Inter"),
      ]),
    ),
    AttrStmt(EdgeAttr, attrs([attr("color", "#6b7280")])),
  ]
  for node in self.nodes {
    statements.push(node_statement(node))
  }
  for edge in self.edges {
    statements.push(edge_statement(edge))
  }
  { strict: false, directed: true, id: self.id, statements }
}

///|
/// Render this visualization graph as DOT text using the local Graphviz formatter.
pub fn VisualGraph::to_dot(self : VisualGraph) -> String {
  @dot.format_graph(self.to_dot_graph())
}

///|
/// Render this visualization graph as SVG using the local Graphviz layout and SVG renderer.
pub fn VisualGraph::to_svg(self : VisualGraph) -> String {
  let layout = @layout.compute_layout(self.to_dot_graph())
  @graph_svg.render_svg(layout)
}

///|
/// Render this visualization graph as SVG with an explicit Graphviz SVG config.
pub fn VisualGraph::to_svg_with_config(
  self : VisualGraph,
  config : @graph_svg.SvgConfig,
) -> String {
  let layout = @layout.compute_layout(self.to_dot_graph())
  @graph_svg.render_svg_with_config(layout, config)
}
