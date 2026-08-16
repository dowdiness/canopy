///|
priv struct EdgeRenderProjection {
  id : String
  path_d : String
  selected : Bool
  aria_label : String
}

///|
fn finite_render_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn render_port_offset(
  node : NodeJson,
  ports : Array[PortDef],
  port_id : String,
) -> Double? {
  guard finite_render_number(node.h) && node.h >= 0.0 && ports.length() > 0 else {
    return None
  }
  match ports.search_by(fn(port) { port.id == port_id }) {
    None => None
    Some(index) => {
      let offset = (index + 1).to_double() *
        node.h /
        (ports.length() + 1).to_double()
      if finite_render_number(offset) {
        Some(offset)
      } else {
        None
      }
    }
  }
}

///|
fn render_world_point(x : Double, y : Double) -> @spatial.WorldPoint? {
  guard finite_render_number(x) && finite_render_number(y) else {
    return None
  }
  let point = @spatial.WorldPoint::from_xy(x=x, y=y) catch {
    @spatial.CoordinateError::NonFinite => return None
  }
  Some(point)
}

///|
fn render_output_anchor(
  node : NodeJson,
  port_id : String,
) -> @spatial.WorldPoint? {
  match render_port_offset(node, node.outputs, port_id) {
    None => None
    Some(offset) => render_world_point(node.x + node.w, node.y + offset)
  }
}

///|
fn render_input_anchor(
  node : NodeJson,
  port_id : String,
) -> @spatial.WorldPoint? {
  match render_port_offset(node, node.inputs, port_id) {
    None => None
    Some(offset) => render_world_point(node.x, node.y + offset)
  }
}

///|
fn render_bezier_path(
  source : @spatial.WorldPoint,
  target : @spatial.WorldPoint,
) -> String? {
  let sx = source.x()
  let sy = source.y()
  let tx = target.x()
  let ty = target.y()
  let dx = ((tx - sx).abs() * 0.5).max(40.0)
  let c1x = sx + dx
  let c2x = tx - dx
  guard [sx, sy, tx, ty, c1x, c2x].iter().all(finite_render_number) else {
    return None
  }
  Some("M \{sx} \{sy} C \{c1x} \{sy}, \{c2x} \{ty}, \{tx} \{ty}")
}

///|
fn edge_render_node_index(
  nodes : Array[NodeJson],
) -> Map[String, NodeJson] {
  Map::from_array(nodes.map(fn(node) { (node.id, node) }))
}

///|
fn project_edge_render(
  node_index : Map[String, NodeJson],
  edge : Edge,
  selected_edge : EdgeId?,
) -> EdgeRenderProjection? {
  let source_id = edge.source.to_string()
  let target_id = edge.target.to_string()
  let source = match node_index.get(source_id) {
    None => return None
    Some(node) => node
  }
  let target = match node_index.get(target_id) {
    None => return None
    Some(node) => node
  }
  let source_anchor = match render_output_anchor(source, edge.source_port) {
    None => return None
    Some(anchor) => anchor
  }
  let target_anchor = match render_input_anchor(target, edge.target_port) {
    None => return None
    Some(anchor) => anchor
  }
  let path_d = match render_bezier_path(source_anchor, target_anchor) {
    None => return None
    Some(path) => path
  }
  Some({
    id: edge.id.to_string(),
    path_d,
    selected: selected_edge == Some(edge.id),
    aria_label: "Disconnect \{source_id}.\{edge.source_port} → \{target_id}.\{edge.target_port}",
  })
}

///|
fn project_edge_renders(
  node_index : Map[String, NodeJson],
  edges : Array[Edge],
  selected_edge : EdgeId?,
) -> Array[EdgeRenderProjection] {
  edges.filter_map(fn(edge) {
    project_edge_render(node_index, edge, selected_edge)
  })
}

///|
fn pending_cursor_point(connection : ConnectingJson) -> @spatial.WorldPoint? {
  render_world_point(connection.cursor_x, connection.cursor_y)
}

///|
fn project_pending_path(
  node_index : Map[String, NodeJson],
  connecting : ConnectingJson?,
) -> String? {
  match connecting {
    None => None
    Some(connection) =>
      match node_index.get(connection.from) {
        None => None
        Some(source) =>
          match render_output_anchor(source, connection.from_port) {
            None => None
            Some(anchor) =>
              match pending_cursor_point(connection) {
                None => None
                Some(cursor) => render_bezier_path(anchor, cursor)
              }
          }
      }
  }
}
