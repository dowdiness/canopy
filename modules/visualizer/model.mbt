///|
/// Rendering state used to style a graph node.
pub(all) enum VisualNodeStatus {
  Neutral
  Active
  Changed
  Failed
}

///|
/// A node in a renderer-neutral visualization graph.
pub struct VisualNode {
  priv id : String
  priv label : String?
  priv detail : String?
  priv status : VisualNodeStatus
}

///|
/// A directed edge in a renderer-neutral visualization graph.
pub struct VisualEdge {
  priv from : String
  priv to : String
  priv label : String?
}

///|
/// Renderer-neutral graph model consumed by the Graphviz and SVG renderers.
pub struct VisualGraph {
  priv id : String?
  priv nodes : Array[VisualNode]
  priv edges : Array[VisualEdge]
}

///|
/// Create a neutral graph node.
pub fn VisualNode::VisualNode(
  id : String,
  label? : String,
  detail? : String,
  status? : VisualNodeStatus = Neutral,
) -> VisualNode {
  { id, label, detail, status }
}

///|
/// Create a directed graph edge.
pub fn VisualEdge::VisualEdge(
  from : String,
  to : String,
  label? : String,
) -> VisualEdge {
  { from, to, label }
}

///|
/// Create an empty visualization graph.
pub fn VisualGraph::VisualGraph(id? : String) -> VisualGraph {
  { id, nodes: [], edges: [] }
}

///|
/// Add a node to this graph.
pub fn VisualGraph::add_node(self : VisualGraph, node : VisualNode) -> Unit {
  self.nodes.push(node)
}

///|
/// Add a directed edge to this graph.
pub fn VisualGraph::add_edge(self : VisualGraph, edge : VisualEdge) -> Unit {
  self.edges.push(edge)
}
