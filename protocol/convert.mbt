// proj_to_view_node: Converts ProjNode[T] + SourceMap into ViewNode.
// Requires T : Renderable to extract kind_tag, label, and other display info.

///|
/// Convert a ProjNode tree and its SourceMap into a ViewNode tree.
/// Uses the Renderable trait to extract display information from each AST node.
pub fn[T : @loomcore.Renderable] proj_to_view_node(
  node : @core.ProjNode[T],
  source_map : @core.SourceMap,
  annotations? : Map[@core.NodeId, Array[ViewAnnotation]] = {},
  source_text? : String? = None,
) -> ViewNode {
  let node_id = node.id()
  let kind_tag = @loomcore.Renderable::kind_tag(node.kind)
  let label = @loomcore.Renderable::label(node.kind)
  let text_range = match source_map.get_range(node_id) {
    Some(r) => (r.start, r.end)
    None => (node.start, node.end)
  }
  let token_spans : Array[TokenSpan] = []
  match source_map.token_spans.get(node_id) {
    Some(roles) =>
      for role, range in roles {
        token_spans.push(TokenSpan(role~, start=range.start, end=range.end))
      }
    None => ()
  }
  // Extract visible text from "text" or "code" token span when source_text is provided
  let text : String? = match source_text {
    Some(src) =>
      match source_map.token_spans.get(node_id) {
        Some(roles) =>
          match roles.get("text") {
            Some(range) => Some(src[range.start:range.end].to_string())
            None =>
              match roles.get("code") {
                Some(range) => Some(src[range.start:range.end].to_string())
                None => None
              }
          }
        None => None
      }
    None => None
  }
  let editable = text is Some(_)
  let children : Array[ViewNode] = []
  for child in node.children {
    children.push(
      proj_to_view_node(child, source_map, annotations~, source_text~),
    )
  }
  let node_annotations = match annotations.get(node_id) {
    Some(anns) => anns
    None => []
  }
  {
    id: node_id,
    kind_tag,
    label,
    text,
    text_range,
    token_spans,
    editable,
    css_class: kind_tag,
    children,
    annotations: node_annotations,
  }
}

///|
/// Count nodes in a ViewNode tree.
pub fn ViewNode::node_count(self : ViewNode) -> Int {
  let mut count = 1
  for child in self.children {
    count = count + child.node_count()
  }
  count
}
