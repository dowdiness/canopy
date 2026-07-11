///|
fn lower_disconnect_ports(
  doc : @graph_dsl.GraphDoc,
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> Result[SourceOperationEdit, String] {
  if source_port != "out" {
    return Err("graph-dsl source disconnections must use port 'out'")
  }
  let source_node = match graph_node_for_canvas_id(doc, source) {
    Some(node) => node
    None => return Err("cannot lower DisconnectPorts: missing source node")
  }
  let target_node = match graph_node_for_canvas_id(doc, target) {
    Some(node) => node
    None => return Err("cannot lower DisconnectPorts: missing target node")
  }
  match
    doc.lower_remove_connection(
      target_node.binding(),
      target_port,
      source_node.binding(),
    ) {
    Some(edit) => Ok(ExactLoweredEdit(edit))
    None => Err("cannot lower DisconnectPorts: missing edge")
  }
}
