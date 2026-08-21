///|
fn incr_canvas_edge_endpoint_key(
  edge : @visualizer.RecomputeSnapshotEdge,
) -> String {
  "edge:" + incr_canvas_cell_id(edge.from) + "->" + incr_canvas_cell_id(edge.to)
}

///|
fn incr_canvas_edge_key(endpoint : String, ordinal : Int) -> String {
  if ordinal == 0 {
    endpoint
  } else {
    endpoint + "#" + ordinal.to_string()
  }
}

///|
fn incr_canvas_svg_attrs() -> @svg.Attrs {
  @svg.Attrs::build()
  .class("incr-canvas-svg")
  .width("100%")
  .height("220")
  .role("img")
  .aria_label("Interactive Incr dependency graph")
  .pointer_events("none")
}

///|
fn incr_canvas_edge_view(
  state : IncrCanvasState,
  edge : @visualizer.RecomputeSnapshotEdge,
) -> @svg.Svg? {
  match
    (
      incr_canvas_screen_position(state, edge.from),
      incr_canvas_screen_position(state, edge.to),
    ) {
    (Some(from), Some(to)) =>
      Some(
        @svg.node(
          "line",
          @svg.Attrs::build()
          .class("incr-canvas-edge")
          .x1(from.x().to_string())
          .y1(from.y().to_string())
          .x2(to.x().to_string())
          .y2(to.y().to_string()),
          ([] : Array[@svg.Svg]),
        ),
      )
    _ => None
  }
}

///|
fn incr_canvas_node_view(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
  node : @visualizer.RecomputeSnapshotNode,
) -> @svg.Svg? {
  match incr_canvas_screen_position(state, node.id) {
    Some(center) => {
      let status = incr_canvas_status(snapshot, node.id)
      let selected = state.selected.contains(node.id)
      let stroke = if selected { "#b090e0" } else { status.stroke() }
      let half_width = INCR_CANVAS_NODE_WIDTH / 2.0
      let half_height = INCR_CANVAS_NODE_HEIGHT / 2.0
      let cell_id = incr_canvas_cell_id(node.id)
      let transform = "translate(" +
        center.x().to_string() +
        " " +
        center.y().to_string() +
        ")"
      let rect = @svg.node(
        "rect",
        @svg.Attrs::build()
        .x((0.0 - half_width).to_string())
        .y((0.0 - half_height).to_string())
        .width(INCR_CANVAS_NODE_WIDTH.to_string())
        .height(INCR_CANVAS_NODE_HEIGHT.to_string())
        .rx("6")
        .fill(status.fill())
        .stroke(stroke),
        ([] : Array[@svg.Svg]),
      )
      let text = @svg.node(
        "text",
        @svg.Attrs::build().x("0").y("5").text_anchor("middle"),
        [@svg.text(incr_canvas_node_label(node))],
      )
      Some(
        @svg.node(
          "g",
          @svg.Attrs::build()
          .class("incr-canvas-node")
          .data_set("cell-id", cell_id)
          .transform(transform),
          [rect, text],
        ),
      )
    }
    None => None
  }
}

///|
/// Render the Ideal-local interactive graph as one keyed Rabbita SVG tree.
/// Positions remain screen-space projections from the local viewport; node
/// dimensions remain fixed screen pixels. Invalid projections omit only the
/// affected edge or node.
fn incr_canvas_svg_view(
  state : IncrCanvasState,
  snapshot : @visualizer.RecomputeSnapshot,
) -> Html {
  let children : Map[String, @svg.Svg] = Map([])
  let edge_ordinals : Map[String, Int] = Map([])
  for edge in snapshot.edges {
    match incr_canvas_edge_view(state, edge) {
      Some(line) => {
        let endpoint = incr_canvas_edge_endpoint_key(edge)
        let ordinal = edge_ordinals.get(endpoint).unwrap_or(0)
        edge_ordinals[endpoint] = ordinal + 1
        children[incr_canvas_edge_key(endpoint, ordinal)] = line
      }
      None => ()
    }
  }
  for node in snapshot.nodes {
    match incr_canvas_node_view(state, snapshot, node) {
      Some(group) => children["node:" + incr_canvas_cell_id(node.id)] = group
      None => ()
    }
  }
  @svg.Svg::to_html(@svg.keyed_node("svg", incr_canvas_svg_attrs(), children))
}
